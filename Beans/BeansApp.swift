import SwiftUI
import UIKit

@main
struct BeansApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerManager()
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var favorites = FavoritesStore.shared
    /// 免责声明确认状态：未确认前主界面在模糊层下方可见，确认后移除门禁
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false

    init() {
        // 启动时重新注册用户上传的全局字体（覆盖安装后依然生效）
        FontManager.reinstallIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(auth)
                    .environmentObject(player)
                    .environmentObject(theme)
                    .environmentObject(favorites)
                // 未确认前盖一层模糊门禁，主界面在底下可直接看到
                if !disclaimerAccepted {
                    DisclaimerGate { disclaimerAccepted = true }
                }
            }
        }
    }
}

// MARK: - 免责声明门禁（模糊背景 + 原生输入弹窗）

/// 未确认前盖一层毛玻璃模糊，透出主界面内容，同时弹原生输入弹窗
struct DisclaimerGate: View {
    let onConfirm: () -> Void
    @State private var showAlert = false

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
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
            if !presentIfNeeded(), parent.isPresented {
                // 宿主视图可能还没挂到窗口，稍后重试一次；viewDidAppear 也会再兜底一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    _ = self?.presentIfNeeded()
                }
            }
        }

        @discardableResult
        func presentIfNeeded() -> Bool {
            guard parent.isPresented, alert == nil, let host else { return false }
            // 宿主必须已经挂到窗口上才能 present，否则系统会静默失败（弹窗不出现）
            guard host.viewIfLoaded?.window != nil else { return false }
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
            host.present(alert, animated: true)
            self.alert = alert
            return true
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
