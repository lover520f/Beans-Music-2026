import SwiftUI
import UIKit

enum RootTab: String, CaseIterable, Identifiable {
    case discover
    case search
    case library
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "发现"
        case .search: return "搜索"
        case .library: return "音乐库"
        case .profile: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        case .profile: return "person.crop.circle"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue

    @State private var selection: RootTab = .discover
    @State private var showPlayer = false
    /// 首次启动免责声明：输入指定文字后才放行（UserDefaults 持久化，二次启动不再弹出）
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false
    @State private var disclaimerInput = ""
    @State private var showDisclaimer = false

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 系统原生 TabView：iOS 26 上 UITabBar 自动使用原生液态玻璃，
            // 按压折射反馈、拖动效果、高光均由系统渲染（与应用商店等系统 App 一致）。
            // 背景（壁纸/背景色）由每个 tab 页面内部的 GlassBackdrop 渲染，
            // 因为系统 TabView 的内容层会盖住 RootView 底层的 ZStack 背景。
            TabView(selection: $selection) {
                DiscoverView()
                    .tabItem { Label("发现", systemImage: "sparkles") }
                    .tag(RootTab.discover)
                SearchView()
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    .tag(RootTab.search)
                LibraryView()
                    .tabItem { Label("音乐库", systemImage: "music.note.list") }
                    .tag(RootTab.library)
                ProfileView()
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
                    .tag(RootTab.profile)
            }
            .tint(Color.beansAmber)

            // 迷你播放器：悬浮在系统 TabBar 上方
            VStack(spacing: 0) {
                Spacer()
                if player.currentSong != nil {
                    MiniPlayerView(showPlayer: $showPlayer)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 62)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(themeMode.colorScheme)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(favorites)
                .environmentObject(player)
                .environmentObject(auth)
        }
        .animation(.spring(duration: 0.4), value: player.currentSong?.id)
        .overlay(alignment: .bottom) {
            ToastView(center: ToastCenter.shared)
        }
        .onAppear {
            if !disclaimerAccepted {
                showDisclaimer = true
            }
        }
        .alert("免责声明", isPresented: $showDisclaimer) {
            TextField("请输入：我已了解并继续使用此软件", text: $disclaimerInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("进入软件", role: .cancel) {
                if disclaimerInput == "我已了解并继续使用此软件" {
                    disclaimerAccepted = true
                    BeansHaptics.success()
                } else {
                    disclaimerInput = ""
                    showDisclaimer = false
                    ToastCenter.shared.show("请输入：我已了解并继续使用此软件")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !disclaimerAccepted {
                            showDisclaimer = true
                        }
                    }
                }
            }
        } message: {
            Text("Beans Music 只用作个人学习研究，禁止用于商业及非法用途，如产生法律纠纷与本人无关。
音乐 API 来自于 GitHub，非官方版 API；本软件不提供任何音频存储服务，如需下载音频，请支持正版！
音乐版权归各网站所有，本站不承担任何法律责任和连带责任。")
        }
    }
}

// MARK: - 系统 TabBar 清透风格（实例级配置）
// 系统 TabView 创建之后，`UITabBar.appearance()` 全局代理对已存在的实例不再生效，
// 所以每个 tab 页面内放一个 TabBarAppearanceConfigurator，通过 tabBarController
// 拿到当前 UITabBar 实例，直接设置固定清透外观（全透明、无阴影）。

struct TabBarAppearanceConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        // 纯外观配置视图：禁止拦截触摸，避免透明全屏视图吃掉页面按钮点击
        controller.view.isUserInteractionEnabled = false
        DispatchQueue.main.async { Self.apply(from: controller) }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async { Self.apply(from: uiViewController) }
    }

    /// 固定清透风格：全透明背景、无阴影；选中态用主题色，
    /// 材质与模糊完全交给系统对底层页面内容的渲染，不再支持手动调节透明度
    private static func apply(from controller: UIViewController) {
        guard let tabBar = controller.tabBarController?.tabBar else { return }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        // 超薄材质模糊：与迷你播放器一致的清透玻璃透明度
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = UIColor.beansAmber
        tabBar.isTranslucent = true
    }
}
