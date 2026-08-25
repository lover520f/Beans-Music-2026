import SwiftUI
import UIKit

/// 汽水音乐登录页：扫码登录（默认）/ 手动粘贴 sessionid
/// 扫码：使用「抖音 App」扫描二维码确认登录（汽水音乐官方登录页要求用抖音扫码），
/// 确认后自动下发 sessionid 并同步账号歌单。
struct SodaLoginSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SodaLoginMode = .scan

    enum SodaLoginMode: String, CaseIterable, Identifiable {
        case scan = "扫码登录"
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
                    case .scan:
                        SodaScanContent(onSuccess: { dismiss() })
                    case .paste:
                        SodaSessionImportPanel(onSuccess: { dismiss() })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 扫码登录

struct SodaScanContent: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var status: SodaScanStatus = .loading
    @State private var qrImage: UIImage?
    @State private var token = ""
    @State private var timer: Timer?
    @State private var waitingTicks = 0
    let onSuccess: () -> Void

    private enum SodaScanStatus: Equatable {
        case loading
        case waiting
        case scanned
        case success
        case expired
        case error(String)
    }

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 22) {
            Spacer()
            Text("使用抖音 App 扫码登录，同步你的汽水音乐歌单")
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)

            ZStack {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                } else {
                    ProgressView()
                        .tint(Color.beansAmber)
                        .frame(width: 250, height: 250)
                }
                if status == .expired || isError {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 34))
                        Text(isError ? errorText : "二维码已过期")
                            .font(BeansFont.appFont(13))
                        GlassButton(title: "刷新", systemName: "arrow.clockwise", prominent: true) {
                            startLogin()
                        }
                    }
                    .foregroundStyle(Color.beansLabel)
                    .frame(width: 210, height: 210)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)

            statusView

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .onAppear { startLogin() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    @ViewBuilder
    private var statusView: some View {
        Group {
            switch status {
            case .loading:
                Text("正在生成二维码…")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            case .waiting:
                VStack(spacing: 4) {
                    Label("请使用抖音 App 扫码", systemImage: "qrcode.viewfinder")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                    if waitingTicks > 8 {
                        Text("长时间未同步？可切换「粘贴 Session」方式登录，更稳定")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment.opacity(0.7))
                    }
                }
            case .scanned:
                Label("已扫码，请在手机上确认登录", systemImage: "checkmark.circle")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansSage)
            case .success:
                Label("登录成功，正在同步歌单…", systemImage: "checkmark.seal.fill")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansSage)
            case .expired:
                Text("二维码已过期")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            case .error(let message):
                Text(message)
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(height: 44)
    }

    private var isError: Bool {
        if case .error = status { return true }
        return false
    }

    private var errorText: String {
        if case .error(let message) = status { return message }
        return ""
    }

    // MARK: - 流程

    private func startLogin() {
        timer?.invalidate()
        timer = nil
        status = .loading
        qrImage = nil
        waitingTicks = 0
        Task {
            do {
                let (newToken, imageData) = try await SodaAuth.shared.fetchQRCode()
                await MainActor.run {
                    token = newToken
                    if let imageData, let image = UIImage(data: imageData) {
                        qrImage = image
                    }
                    status = .waiting
                    startPolling(token: newToken)
                }
            } catch {
                await MainActor.run {
                    status = .error(error.localizedDescription)
                }
            }
        }
    }

    private func startPolling(token: String) {
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task {
                do {
                    let state = try await SodaAuth.shared.poll(token: token)
                    await MainActor.run {
                        handle(state)
                    }
                } catch {
                    // 网络抖动：跳过本次轮询，等待下一次
                }
            }
        }
    }

    private func handle(_ state: SodaAuth.ScanState) {
        switch state {
        case .success:
            timer?.invalidate()
            timer = nil
            status = .success
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                BeansHaptics.success()
                ToastCenter.shared.show("汽水音乐登录成功")
                onSuccess()
            }
        case .scanned:
            status = .scanned
        case .expired:
            timer?.invalidate()
            timer = nil
            status = .expired
        case .error(let message):
            timer?.invalidate()
            timer = nil
            status = .error(message)
        case .waiting:
            waitingTicks += 1
            if status == .scanned { status = .waiting }
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
