import SwiftUI
import UIKit
import WebKit

/// 汽水音乐登录页：网页登录（推荐）/ 手动粘贴 sessionid
/// 确认后自动下发 sessionid 并同步账号歌单。
struct SodaLoginSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SodaLoginMode = .web

    enum SodaLoginMode: String, CaseIterable, Identifiable {
        case web = "抖音授权"
        case paste = "粘贴Session"
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

                HStack(spacing: 10) {
                    Image("BrandSoda")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("登录汽水音乐")
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
                    ForEach(SodaLoginMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Group {
                    switch mode {
                    case .web:
                        SodaWebLoginPanel(onSuccess: { dismiss() })
                    case .paste:
                        SodaSessionImportPanel(onSuccess: { dismiss() })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 网页登录（WKWebView 打开汽水音乐网页版，登录后自动读取 Cookie）

struct SodaWebLoginPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var pageLoaded = false
    @State private var syncing = false
    @State private var message = ""
    @State private var timer: Timer?
    @State private var lastHeader = ""
    let onSuccess: () -> Void

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 10) {
            Text("汽水音乐暂无独立网页登录，请使用抖音账号授权（同一字节账号体系）：扫码或手机号登录抖音后自动同步歌单")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            ZStack {
                SodaWebView(onLoaded: { pageLoaded = true })
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .padding(.horizontal, 20)

                if !pageLoaded {
                    ProgressView("正在加载抖音登录…")
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
            readCookies { header in
                guard !header.isEmpty, header != lastHeader else { return }
                importCookies(header)
            }
        }
    }

    private func syncNow() {
        syncing = true
        message = ""
        readCookies { header in
            syncing = false
            if header.isEmpty {
                message = "未检测到登录态，请先在抖音网页中扫码或手机号登录"
            } else {
                importCookies(header)
            }
        }
    }

    private func importCookies(_ header: String) {
        lastHeader = header
        SodaAuth.shared.importCookieHeader(header)
        timer?.invalidate()
        timer = nil
        syncing = true
        message = "正在验证登录态并同步歌单…"
        Task {
            let error = await SodaAuth.shared.verifyLogin()
            await MainActor.run {
                syncing = false
                if let error {
                    message = "已获取登录态，但歌单同步失败：\(error)"
                    ToastCenter.shared.show("汽水登录态已保存，歌单同步失败")
                } else {
                    message = "✓ 汽水音乐登录成功，歌单已同步"
                    BeansHaptics.success()
                    ToastCenter.shared.show("汽水音乐登录成功")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onSuccess()
                    }
                }
            }
        }
    }

    /// 从 WKWebView Cookie 存储读取登录态（优先汽水官网 qishui.com 域，兜底抖音 SSO sessionid）
    private func readCookies(_ completion: @escaping (String) -> Void) {
        let wanted = SodaAuth.webCookieNames
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            var parts: [String] = []
            var qishuiHasSession = false
            var douyinSession: [String] = []
            for cookie in cookies {
                let domain = cookie.domain.lowercased()
                if domain.contains("qishui.com") {
                    if cookie.name == "sessionid" || cookie.name == "sessionid_ss" || cookie.name == "sid_guard" {
                        qishuiHasSession = true
                    }
                    parts.append("\(cookie.name)=\(cookie.value)")
                } else if domain.contains("douyin.com") || domain.contains("bytedance.com") || domain.contains("amemv.com") {
                    if wanted.contains(cookie.name) || cookie.name.hasPrefix("sessionid") || cookie.name == "sid_guard" || cookie.name == "sid_tt" {
                        douyinSession.append("\(cookie.name)=\(cookie.value)")
                    }
                }
            }
            // 无 qishui 域登录态时，退回抖音 SSO sessionid（同一字节账号体系）
            if !qishuiHasSession {
                parts = douyinSession
            }
            DispatchQueue.main.async {
                completion(parts.isEmpty ? "" : parts.joined(separator: "; "))
            }
        }
    }
}

// MARK: - WKWebView 封装（打开抖音网页版授权登录，读取同体系登录态 Cookie）

struct SodaWebView: UIViewRepresentable {
    let onLoaded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://www.douyin.com/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoaded: () -> Void

        init(onLoaded: @escaping () -> Void) {
            self.onLoaded = onLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 自动点击「登录」按钮弹出登录框（抖音为 SPA，登录按钮由 JS 触发）
            let autoLoginJS = """
            (() => {
              const tryClick = () => {
                const els = document.querySelectorAll('button, [role="button"], div, span, a');
                for (const el of els) {
                  const t = (el.textContent || '').trim();
                  if (t === '登录' && el.offsetParent !== null) { el.click(); return true; }
                }
                return false;
              };
              if (!tryClick()) setTimeout(tryClick, 900);
            })();
            """
            webView.evaluateJavaScript(autoLoginJS, completionHandler: nil)
            DispatchQueue.main.async {
                self.onLoaded()
            }
        }
    }
}

// MARK: - 手动粘贴 sessionid

struct SodaSessionImportPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var sessionText = ""
    @State private var message = ""
    let onSuccess: () -> Void

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 12) {
            Text("在电脑浏览器登录汽水音乐网页版或抖音网页版后，按 F12 → Application → Cookies，找到 sessionid 的值复制到下方；也可以直接粘贴整段 Cookie（会自动提取 sessionid）")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            TextEditor(text: $sessionText)
                .font(BeansFont.appFont(11, .regular, .monospaced))
                .beansScrollContentBackgroundHidden()
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
                importSession()
            } label: {
                Label("导入登录态", systemImage: "arrow.down.doc")
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

    private func importSession() {
        let raw = sessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        var session = raw
        if raw.contains(";") || raw.contains("sessionid=") {
            // 整段 Cookie：提取 sessionid 值
            let parts = raw.split(separator: ";")
            if let hit = parts.first(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("sessionid=") }) {
                session = String(hit.split(separator: "=", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !session.isEmpty else {
            message = "未找到有效的 sessionid，请确认已完整复制"
            return
        }
        if raw.contains(";") || raw.contains("sessionid=") {
            SodaAuth.shared.importCookieHeader(raw)
        } else {
            SodaAuth.shared.importSessionID(session)
        }
        message = "✓ 汽水音乐登录成功"
        BeansHaptics.success()
        ToastCenter.shared.show("汽水音乐登录成功")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onSuccess()
        }
    }
}
