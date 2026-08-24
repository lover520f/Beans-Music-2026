import SwiftUI
import UIKit

@main
struct BeansApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerManager()
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var favorites = FavoritesStore.shared
    /// 免责声明确认状态：未确认前不创建 RootView（主界面完全不加载，避免弹窗期间出现"无网络"等提示）
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false

    init() {
        // 启动时重新注册用户上传的全局字体（覆盖安装后依然生效）
        FontManager.reinstallIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            if disclaimerAccepted {
                RootView()
                    .environmentObject(auth)
                    .environmentObject(player)
                    .environmentObject(theme)
                    .environmentObject(favorites)
            } else {
                DisclaimerGate { disclaimerAccepted = true }
            }
        }
    }
}

// MARK: - 首次启动免责声明门禁（原生系统弹窗）

/// 未确认前只显示占位视图，不创建主界面；弹窗输入正确文字前"进入"按钮不可点、弹窗不消失
struct DisclaimerGate: View {
    let onConfirm: () -> Void
    @State private var showAlert = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.10, green: 0.11, blue: 0.17)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "beats.headphones")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Beans Music")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white)
                Text("正在初始化…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .onAppear { showAlert = true }
        .background(
            NativeDisclaimerAlert(isPresented: $showAlert, required: "我已了解并同意继续使用", onConfirm: onConfirm)
        )
    }
}

/// 原生系统弹窗（UIAlertController）：输入框未输入正确文字前，进入按钮不可点，弹窗不会消失
struct NativeDisclaimerAlert: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let required: String
    let onConfirm: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = PresenterHostVC()
        vc.onAppear = { [weak coordinator = context.coordinator] in
            coordinator?.presentIfNeeded()
        }
        context.coordinator.host = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.update(parent: self)
    }

    final class Coordinator: NSObject {
        private var parent: NativeDisclaimerAlert
        weak var host: UIViewController?
        private var alert: UIAlertController?
        private var confirmAction: UIAlertAction?

        init(parent: NativeDisclaimerAlert) { self.parent = parent }

        func update(parent: NativeDisclaimerAlert) {
            self.parent = parent
            presentIfNeeded()
        }

        func presentIfNeeded() {
            guard parent.isPresented, alert == nil, let host else { return }
            let alert = UIAlertController(
                title: "免责声明",
                message: "Beans Music 只用作个人学习研究，禁止用于商业及非法用途，如产生法律纠纷与本人无关。\n音乐 API 来自于 GitHub，非官方版 API；本软件不提供任何音频存储服务，如需下载音频，请支持正版！\n音乐版权归各网站所有，本站不承担任何法律责任和连带责任。",
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.placeholder = self.parent.required
                field.autocorrectionType = .no
                field.autocapitalizationType = .none
                field.clearButtonMode = .whileEditing
                field.addTarget(self, action: #selector(self.textChanged(_:)), for: .editingChanged)
            }
            let action = UIAlertAction(title: "进入软件", style: .default) { [weak self] _ in
                self?.parent.onConfirm()
            }
            action.isEnabled = false
            confirmAction = action
            alert.addAction(action)
            self.alert = alert
            host.present(alert, animated: true)
        }

        @objc private func textChanged(_ sender: UITextField) {
            confirmAction?.isEnabled = (sender.text ?? "") == parent.required
        }
    }
}

/// 承载弹窗的宿主控制器：等视图真正出现后再 present，避免"view not in window hierarchy"警告
final class PresenterHostVC: UIViewController {
    var onAppear: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}
