import SwiftUI

enum QRStatus: Equatable {
    case loading
    case waiting
    case scanned
    case success
    case expired
    case error(String)
}

/// 网易云音乐登录页：网页登录（默认）/ 扫码登录，排版与 QQ 登录一致
struct LoginView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: NetEaseLoginMode = .web
    @State private var key: String?
    @State private var status: QRStatus = .loading
    @State private var timer: Timer?

    enum NetEaseLoginMode: String, CaseIterable, Identifiable {
        case web = "网页登录"
        case scan = "扫码登录"
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
                    Text("登录网易云音乐")
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
                    ForEach(NetEaseLoginMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Group {
                    switch mode {
                    case .web:
                        webContent
                    case .scan:
                        scanContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    // MARK: - 网页登录

    private var webContent: some View {
        VStack(spacing: 8) {
            NetEaseWebLoginPanel(onSuccess: { dismiss() })
            Text("为方便未下载网易云音乐的用户可直接使用网页手机号登录")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 扫码登录内容（进入该页签时才启动二维码流程）

    private var scanContent: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("使用网易云音乐 App 扫码登录，同步你的歌单")
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)

            qrArea
                .frame(width: 250, height: 250)
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
    }

    @ViewBuilder
    private var qrArea: some View {
        ZStack {
            if let key {
                QRCodeView(text: NetEaseAPI.shared.qrLoginURL(key: key))
            } else {
                ProgressView().tint(Color.beansAmber)
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
    }

    private var statusView: some View {
        Group {
            switch status {
            case .loading:
                Text("正在生成二维码…")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            case .waiting:
                Label("请使用网易云音乐 App 扫码", systemImage: "qrcode.viewfinder")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
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

    // MARK: - 扫码流程

    private func startLogin() {
        timer?.invalidate()
        timer = nil
        status = .loading
        Task {
            do {
                let newKey = try await NetEaseAPI.shared.qrKey()
                await MainActor.run {
                    key = newKey
                    status = .waiting
                    startPolling(key: newKey)
                }
            } catch {
                await MainActor.run {
                    status = .error(error.localizedDescription)
                }
            }
        }
    }

    private func startPolling(key: String) {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task {
                do {
                    let code = try await NetEaseAPI.shared.qrCheck(key: key)
                    await MainActor.run {
                        handle(code)
                    }
                } catch {
                    // 网络抖动：跳过本次轮询，等待下一次
                }
            }
        }
    }

    private func handle(_ code: Int) {
        switch code {
        case 800:
            timer?.invalidate()
            timer = nil
            status = .expired
        case 802:
            status = .scanned
        case 803:
            timer?.invalidate()
            timer = nil
            status = .success
            Task {
                do {
                    try await auth.finishLogin()
                    // 登录成功：自动关闭登录页
                    dismiss()
                } catch {
                    status = .error(error.localizedDescription)
                }
            }
        default:
            if status == .scanned {
                status = .waiting
            }
        }
    }
}
