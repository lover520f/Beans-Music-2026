import SwiftUI

enum QRStatus: Equatable {
    case loading
    case waiting
    case scanned
    case success
    case expired
    case error(String)
}

/// 网易云登录方式：扫码 / 手机号
enum NeteaseLoginMode: String, CaseIterable, Identifiable {
    case qr
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: return "扫码登录"
        case .phone: return "手机号登录"
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore

    @State private var key: String?
    @State private var status: QRStatus = .loading
    @State private var timer: Timer?
    @Environment(\.dismiss) private var dismiss

    // 手机号登录
    @State private var mode: NeteaseLoginMode = .qr
    @State private var phone = ""
    @State private var password = ""
    @State private var captcha = ""
    @State private var useCaptcha = false
    @State private var smsCountdown = 0
    @State private var smsTimer: Timer?
    @State private var phoneBusy = false
    @State private var phoneError: String?

    var body: some View {
        let _ = theme.accent
        ZStack {
            GlassBackdrop()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "beats.headphones")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(LinearGradient.beansAccent)
                Text("Beans Music")
                    .font(BeansFont.appFont(34, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text("登录网易云音乐，同步你的歌单")
                    .font(BeansFont.appFont(14))
                    .foregroundStyle(Color.beansComment)

                Picker("登录方式", selection: $mode) {
                    ForEach(NeteaseLoginMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color.beansAmber)
                .frame(maxWidth: 320)

                Group {
                    if mode == .qr {
                        qrArea
                            .frame(width: 250, height: 250)
                            .padding(18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                        statusView
                    } else {
                        phoneForm
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear { startLogin() }
        .onDisappear {
            timer?.invalidate()
            smsTimer?.invalidate()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .phone {
                // 切到手机号登录时暂停二维码轮询，避免无意义请求
                timer?.invalidate()
                timer = nil
            } else if let key {
                status = .waiting
                startPolling(key: key)
            } else {
                startLogin()
            }
        }
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

    /// 手机号登录表单
    private var phoneForm: some View {
        VStack(spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.beansComment)
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.phonePad)
                    .font(BeansFont.appFont(16))
                    .foregroundStyle(Color.beansLabel)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker("", selection: $useCaptcha) {
                Text("密码登录").tag(false)
                Text("验证码登录").tag(true)
            }
            .pickerStyle(.segmented)
            .tint(Color.beansAmber)

            if useCaptcha {
                HStack(spacing: 10) {
                    TextField("请输入验证码", text: $captcha)
                        .keyboardType(.numberPad)
                        .font(BeansFont.appFont(16))
                        .foregroundStyle(Color.beansLabel)
                        .autocorrectionDisabled()
                    Button {
                        BeansHaptics.tap()
                        sendSMS()
                    } label: {
                        Text(smsCountdown > 0 ? "\(smsCountdown)s" : "发送验证码")
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(smsCountdown > 0 ? Color.beansComment : Color.beansAmber)
                    }
                    .disabled(smsCountdown > 0 || phoneBusy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                SecureField("请输入密码", text: $password)
                    .font(BeansFont.appFont(16))
                    .foregroundStyle(Color.beansLabel)
                    .textContentType(.password)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let phoneError {
                Text(phoneError)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            GlassButton(title: useCaptcha ? "验证码登录" : "密码登录", systemName: "arrow.right.circle.fill", prominent: true) {
                BeansHaptics.tap()
                phoneLogin()
            }
            .disabled(phoneBusy)
            .opacity(phoneBusy ? 0.55 : 1)

            if phoneBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.beansAmber)
            }

            Text("未注册的手机号验证通过后将自动创建网易云账号")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
        }
        .frame(width: 286)
        .frame(minHeight: 250)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
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

    // MARK: - 二维码登录流程

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
                    // 登录成功：二维码区域自动收起，无需手动下拉关闭
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

    // MARK: - 手机号登录流程

    /// 发送短信验证码，60 秒倒计时
    private func sendSMS() {
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.count >= 6 else {
            phoneError = "请输入正确的手机号"
            BeansHaptics.medium()
            return
        }
        phoneError = nil
        phoneBusy = true
        Task {
            do {
                try await NetEaseAPI.shared.sendSMSCode(phone: p)
                await MainActor.run {
                    phoneBusy = false
                    phoneError = "验证码已发送，请注意查收"
                    smsCountdown = 60
                    smsTimer?.invalidate()
                    smsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        if smsCountdown > 1 {
                            smsCountdown -= 1
                        } else {
                            smsTimer?.invalidate()
                            smsTimer = nil
                            smsCountdown = 0
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    phoneBusy = false
                    phoneError = error.localizedDescription
                    BeansHaptics.medium()
                }
            }
        }
    }

    /// 密码 / 验证码登录
    private func phoneLogin() {
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            phoneError = "请输入手机号"
            BeansHaptics.medium()
            return
        }
        if useCaptcha {
            guard !captcha.isEmpty else {
                phoneError = "请输入验证码"
                BeansHaptics.medium()
                return
            }
        } else {
            guard !password.isEmpty else {
                phoneError = "请输入密码"
                BeansHaptics.medium()
                return
            }
        }
        phoneError = nil
        phoneBusy = true
        Task {
            do {
                if useCaptcha {
                    try await NetEaseAPI.shared.loginByCaptcha(phone: p, captcha: captcha.trimmingCharacters(in: .whitespaces))
                } else {
                    try await NetEaseAPI.shared.loginByPassword(phone: p, password: password)
                }
                await MainActor.run {
                    phoneBusy = false
                    status = .success
                }
                try await auth.finishLogin()
                await MainActor.run {
                    smsTimer?.invalidate()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    phoneBusy = false
                    if let ne = error as? NetEaseError, case .needsCaptcha = ne {
                        useCaptcha = true
                        captcha = ""
                        phoneError = "该账号需要短信验证码，请使用验证码登录"
                    } else {
                        phoneError = error.localizedDescription
                    }
                    BeansHaptics.medium()
                }
            }
        }
    }
}
