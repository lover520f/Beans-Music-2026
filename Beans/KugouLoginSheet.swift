import SwiftUI
import WebKit

// MARK: - 酷狗音乐登录（网页登录 + Cookie 导入）
// 酷狗没有公开扫码授权接口，采用与 QQ 音乐一致的方案：
// 应用内 WKWebView 打开 www.kugou.com 网页登录，登录后读取 kugou.com 域 Cookie；
// 或粘贴电脑浏览器 F12 复制的 Cookie。

struct KugouLoginSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: KugouLoginMode = .web

    enum KugouLoginMode: String, CaseIterable, Identifiable {
        case web = "网页登录"
        case paste = "粘贴Cookie"
        var id: String { rawValue }
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            GlassBackdrop()
            VStack(spacing: 16) {
                Capsule()
                    .fill(Color.beansComment.opacity(0.3))
                    .frame(width: 38, height: 4)
                    .padding(.top, 12)

                HStack {
                    Text("登录酷狗音乐")
                        .font(BeansFont.appFont(20, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Button {
                        BeansHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.beansComment)
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.9))
                }
                .padding(.horizontal, 24)

                Picker("登录方式", selection: $mode) {
                    ForEach(KugouLoginMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Group {
                    switch mode {
                    case .web:
                        KugouWebLoginPanel(onSuccess: { dismiss() })
                    case .paste:
                        KugouCookieImportPanel(onSuccess: { dismiss() })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 网页登录面板

struct KugouWebLoginPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var pageLoaded = false
    @State private var syncing = false
    @State private var message = ""
    @State private var timer: Timer?
    let onSuccess: () -> Void

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 10) {
            Text("在下方网页右上角点「登录」，支持手机号 / 扫码 / 账号密码登录，完成后自动同步")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            ZStack {
                KugouWebView(onLoaded: { pageLoaded = true })
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .padding(.horizontal, 20)

                if !pageLoaded {
                    ProgressView("正在加载酷狗音乐…")
                        .tint(Color.beansAmber)
                }
            }
            .frame(maxHeight: .infinity)

            if !message.isEmpty {
                Text(message)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(message.hasPrefix("✓") ? Color.beansSage : Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                syncNow()
            } label: {
                HStack(spacing: 6) {
                    if syncing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(syncing ? "正在读取登录状态…" : "同步登录状态")
                }
                .font(BeansFont.appFont(14, .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.beansAmber, in: Capsule())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.96))
            .disabled(syncing)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear { startAutoDetect() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func startAutoDetect() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            readCookies { dict in
                let auth = KugouMusicAuth.shared
                guard auth.hasAccountLogin(dict) else { return }
                auth.importCookies(dict, nickname: nil)
                finishSuccess()
            }
        }
    }

    private func syncNow() {
        syncing = true
        message = ""
        readCookies { dict in
            syncing = false
            let auth = KugouMusicAuth.shared
            guard !dict.isEmpty else {
                message = "未检测到有效登录态，请先在网页中完成酷狗音乐登录"
                return
            }
            auth.importCookies(dict, nickname: nil)
            finishSuccess()
        }
    }

    private func finishSuccess() {
        timer?.invalidate()
        timer = nil
        message = "✓ 酷狗音乐登录成功"
        BeansHaptics.success()
        ToastCenter.shared.show("酷狗音乐登录成功")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onSuccess()
        }
    }

    /// 从 WKWebView 默认 Cookie 存储读取登录态 Cookie
    private func readCookies(_ completion: @escaping ([String: String]) -> Void) {
        let wanted = KugouMusicAuth.webCookieNames
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            var dict: [String: String] = [:]
            for cookie in cookies where wanted.contains(cookie.name) {
                dict[cookie.name] = cookie.value
            }
            // 兜底：白名单未命中时，收下 kugou.com 域的全部 Cookie
            if dict["mid"] == nil || dict["kg_mid"] == nil {
                for cookie in cookies where cookie.domain.hasSuffix("kugou.com") {
                    dict[cookie.name] = cookie.value
                }
            }
            DispatchQueue.main.async {
                completion(dict)
            }
        }
    }
}

// MARK: - 手动粘贴 Cookie

struct KugouCookieImportPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var cookieText = ""
    @State private var message = ""
    let onSuccess: () -> Void

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 12) {
            Text("电脑浏览器打开 https://www.kugou.com 登录酷狗音乐后，按 F12 → Network → 刷新页面，点任意请求，复制 Request Headers 里的整段 Cookie 粘贴到下方")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            TextEditor(text: $cookieText)
                .font(BeansFont.appFont(11, .regular, .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(height: 160)
                .padding(.horizontal, 20)

            if !message.isEmpty {
                Text(message)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(message.hasPrefix("✓") ? Color.beansSage : Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                importCookie()
            } label: {
                Label("导入 Cookie", systemImage: "arrow.down.doc")
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.beansAmber, in: Capsule())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.96))
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .padding(.top, 8)
    }

    private func importCookie() {
        let dict = KugouMusicAuth.parseCookieHeader(cookieText)
        let auth = KugouMusicAuth.shared
        guard auth.hasValidLogin(dict) else {
            message = "Cookie 格式或登录态无效，请确认已完整复制"
            return
        }
        auth.importCookies(dict, nickname: nil)
        message = "✓ 酷狗音乐登录成功"
        BeansHaptics.success()
        ToastCenter.shared.show("酷狗音乐登录成功")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onSuccess()
        }
    }
}

// MARK: - WKWebView 封装（打开酷狗音乐网页版）

struct KugouWebView: UIViewRepresentable {
    let onLoaded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        // 桌面 UA：www.kugou.com 才会返回 PC 完整页（右上角登录入口，支持手机号 / 扫码）
        webView.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        if let url = URL(string: "https://www.kugou.com/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoaded: () -> Void
        init(onLoaded: @escaping () -> Void) { self.onLoaded = onLoaded }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded()
        }
    }
}
