import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue

    @State private var showHistory = false
    @State private var weekRecord: [PlayRecordItem] = []
    @State private var allRecord: [PlayRecordItem] = []

    @State private var showNetEaseRank = false
    @State private var showSleepTimer = false
    /// 统一账号登录面板（网易云 + QQ 音乐整合）
    @State private var showAccountHub = false
    /// 设置页（外观 + 歌词翻译等）
    @State private var showSettings = false
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var appVersionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Beans · \(ver)"
    }

    /// 两个平台登录状态的合并提示
    private var accountStatusLine: String {
        var parts: [String] = []
        if auth.isLoggedIn {
            parts.append("网易云 UID \(auth.user?.uid ?? 0)")
        }
        if kugouAuth.isLoggedIn {
            parts.append("酷狗音乐已登录")
        }
        if qqAuth.isLoggedIn {
            parts.append(qqAuth.nickname.isEmpty ? "QQ 已登录" : "QQ \(qqAuth.nickname)")
        }
        if parts.isEmpty { return "登录后可同步网易云歌单 / 播放 QQ 歌曲" }
        return parts.joined(separator: " · ")
    }

    /// 顶部标题 + 右上角设置齿轮
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的")
                    .font(BeansFont.appFont(30, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text("网易云 / QQ 音乐账号与外观设置")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansSecondary)
            }
            Spacer()
            GlassIconButton(systemName: "gearshape.fill") {
                BeansHaptics.tap()
                showSettings = true
            }
        }
        .padding(.top, 8)
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 页面背景：同步开启时显示壁纸/背景色，否则默认氛围渐变
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    userCard
                    featuresGrid
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 190)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: auth.isLoggedIn) {
            await loadNetEaseRank()
            await auth.refreshAccount()
            await qqAuth.fetchVIPStatus()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showNetEaseRank) {
            NetEaseRankSheet(week: weekRecord, all: allRecord)
                .environmentObject(player)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showAccountHub) {
            AccountHubSheet()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet()
                .environmentObject(player)
        }
    }

    private var userCard: some View {
        VStack(spacing: 16) {
            Button {
                BeansHaptics.tap()
                // 统一账号面板：网易云 + QQ 音乐登录整合在一起
                showAccountHub = true
            } label: {
                HStack(spacing: 14) {
                    // 头像：主题渐变描边环
                    AsyncImage(url: auth.user?.avatarURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.beansSecondary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .background(Color.beansGlassFill, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(auth.user?.nickname ?? (auth.isLoggedIn ? "网易云已登录" : "免登录 · 点击登录"))
                                .font(BeansFont.appFont(20, .bold))
                                .foregroundStyle(Color.beansLabel)
                                .lineLimit(1)
                            if auth.isLoggedIn, let badge = auth.user?.vipBadge {
                                VIPBadgeView(text: badge)
                            }
                        }
                        Text(accountStatusLine)
                            .font(BeansFont.appFont(12, .regular, .monospaced))
                            .foregroundStyle(Color.beansSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansSecondary.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if auth.isLoggedIn || qqAuth.isLoggedIn || kugouAuth.isLoggedIn {
                platformStatusRow
            }
        }
        .padding(16)
        .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .beansCardShadow(radius: 10, y: 4)
    }

    /// 每个登录平台单独展示登录成功状态（网易云 / QQ 音乐 / 酷狗音乐）
    private var platformStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if auth.isLoggedIn {
                platformChip(icon: "cloud.fill", name: "网易云", status: auth.user?.nickname ?? "已登录", badge: auth.user?.vipBadge)
            }
            if qqAuth.isLoggedIn {
                platformChip(icon: "play.rectangle.fill", name: "QQ 音乐", status: qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname, badge: qqAuth.vipBadge)
            }
            if kugouAuth.isLoggedIn {
                platformChip(icon: "music.note", name: "酷狗音乐", status: kugouAuth.nickname.isEmpty ? "已登录" : kugouAuth.nickname, badge: kugouAuth.vipBadge)
            }
        }
        .padding(.top, 2)
    }

    private func platformChip(icon: String, name: String, status: String, badge: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.beansAmber)
            Text(name)
                .font(BeansFont.appFont(12, .semibold))
                .foregroundStyle(Color.beansLabel)
            Text(status)
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansSecondary)
                .lineLimit(1)
            if let badge {
                VIPBadgeView(text: badge)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }



    /// 壁纸格子：点击应用为当前背景；使用中的壁纸显示主题色边框+勾选；右上角删除
    private func wallpaperCell(path: String) -> some View {
        let isActive = path == theme.backgroundImagePath
        return ZStack(alignment: .topTrailing) {
            Button {
                BeansHaptics.tap()
                theme.applyWallpaper(at: path)
            } label: {
                Group {
                    if let img = UIImage(contentsOfFile: path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.beansGlassFill
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.beansAmber)
                            .background(Circle().fill(.ultraThinMaterial))
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                BeansHaptics.medium()
                theme.deleteWallpaper(at: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.beansSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }

    /// 功能宫格：常用功能统一整合排版
    private var featuresGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的功能")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                featureCell(icon: "clock.arrow.circlepath", title: "播放历史", subtitle: "最近播放 \(player.history.count) 首") {
                    showHistory = true
                }
                featureCell(icon: "chart.bar.fill", title: "历史听歌排行", subtitle: auth.isLoggedIn ? "网易云同步" : "登录后可用") {
                    if auth.isLoggedIn {
                        showNetEaseRank = true
                    } else {
                        ToastCenter.shared.show("请先登录网易云账号")
                    }
                }
                featureCell(icon: "moon.zzz.fill", title: "定时关闭", subtitle: "播放到点自动停止") {
                    showSleepTimer = true
                }
                featureCell(icon: qqAuth.isLoggedIn || kugouAuth.isLoggedIn || auth.isLoggedIn ? "checkmark.seal.fill" : "globe", title: "账号与登录", subtitle: qqAuth.isLoggedIn || kugouAuth.isLoggedIn || auth.isLoggedIn ? accountStatusLine : "统一登录网易云 / QQ 音乐 / 酷狗音乐") {
                    BeansHaptics.tap()
                    showAccountHub = true
                }
            }
        }
    }

    private func featureCell(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 34, height: 34)
                    .background(Color.beansGlassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    /// 加载网易云听歌排行（本周 + 所有时间）
    private func loadNetEaseRank() async {
        guard let user = auth.user, auth.isLoggedIn else { return }

        async let w = try? NetEaseAPI.shared.playRecord(uid: user.uid, type: 1)
        async let a = try? NetEaseAPI.shared.playRecord(uid: user.uid, type: 0)
        let (wr, ar) = await (w, a)
        weekRecord = wr?.items ?? []
        allRecord = ar?.items ?? []

    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "关于")
            VStack(spacing: 8) {
                Label(appVersionText, systemImage: "beats.headphones")
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Text("网易云第三方客户端 · 数据来源网易云音乐")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .beansCardShadow(radius: 9, y: 3)
        }
    }
}

// MARK: - 统一账号登录面板（网易云 + QQ 音乐整合）

struct AccountHubSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showNeteaseLogin = false
    @State private var showQQLogin = false
    @State private var showKugouLogin = false
    @State private var confirmNeteaseLogout = false
    @State private var confirmQQLogout = false
    @State private var confirmKugouLogout = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "账号")
                        neteaseCard
                        qqCard
                        kugouCard
                        Text("网易云登录可同步歌单、收藏与听歌排行；QQ 音乐 / 酷狗音乐登录可播放更多歌曲")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansSecondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showNeteaseLogin) {
            LoginView()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showQQLogin) {
            QQLoginSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showKugouLogin) {
            KugouLoginSheet()
                .environmentObject(theme)
        }
        .confirmationDialog("退出网易云登录？", isPresented: $confirmNeteaseLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                auth.logout()
                ToastCenter.shared.show("已退出网易云账号")
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退出 QQ 音乐？", isPresented: $confirmQQLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                qqAuth.logout()
                ToastCenter.shared.show("已退出 QQ 音乐")
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退出酷狗音乐？", isPresented: $confirmKugouLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                kugouAuth.logout()
                ToastCenter.shared.show("已退出酷狗音乐")
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 网易云账号卡片
    private var neteaseCard: some View {
        Button {
            BeansHaptics.tap()
            if auth.isLoggedIn { confirmNeteaseLogout = true } else { showNeteaseLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandNetease")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("网易云音乐")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    HStack(spacing: 6) {
                        Text(auth.isLoggedIn ? (auth.user?.nickname ?? "已登录") : "未登录 · 扫码登录同步歌单")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansSecondary)
                            .lineLimit(1)
                        if auth.isLoggedIn, let badge = auth.user?.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(auth.isLoggedIn ? "退出" : "登录")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(auth.isLoggedIn ? Color.red : Color.beansAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(14)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    /// QQ 音乐账号卡片
    private var qqCard: some View {
        Button {
            BeansHaptics.tap()
            if qqAuth.isLoggedIn { confirmQQLogout = true } else { showQQLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandQQ")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("QQ 音乐")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    HStack(spacing: 6) {
                        Text(qqAuth.isLoggedIn ? (qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname) : "未登录 · 网页 / 扫码 / Cookie 登录")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansSecondary)
                            .lineLimit(1)
                        if qqAuth.isLoggedIn, let badge = qqAuth.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(qqAuth.isLoggedIn ? "退出" : "登录")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(qqAuth.isLoggedIn ? Color.red : Color.beansAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(14)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    /// 酷狗音乐账号卡片
    private var kugouCard: some View {
        Button {
            BeansHaptics.tap()
            if kugouAuth.isLoggedIn { confirmKugouLogout = true } else { showKugouLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandKugou")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("酷狗音乐")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    HStack(spacing: 6) {
                        Text(kugouAuth.isLoggedIn ? (kugouAuth.nickname.isEmpty ? "已登录" : kugouAuth.nickname) : "未登录 · 网页 / Cookie 登录")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansSecondary)
                            .lineLimit(1)
                        if kugouAuth.isLoggedIn, let badge = kugouAuth.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(kugouAuth.isLoggedIn ? "退出" : "登录")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(kugouAuth.isLoggedIn ? Color.red : Color.beansAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(14)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }
}

// MARK: - 设置页（外观 + 歌词翻译，从「我的」右上角齿轮进入）

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue
    /// 显示歌词翻译（借鉴 Kumone：网易云 tlyric）
    @AppStorage("beans.lyricTranslation") private var lyricTranslation = false
    /// 音质等级（借鉴 Kumone）
    @AppStorage("beans.audioQuality") private var audioQualityRaw = BeansAudioQuality.exhigh.rawValue
    /// 免费听歌 / 灰色歌曲解锁总开关（默认关闭，用户手动开启）
    @AppStorage("beans.enableUnblock") private var enableUnblock = false

    @State private var appearanceExpanded = false
    @State private var bgImageItem: PhotosPickerItem?
    @State private var showFontImporter = false
    /// 第三方音源管理
    @ObservedObject private var unblockStore = UnblockSourceStore.shared
    @State private var showSourceImport = false

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        appearanceSection
                        playbackSection
                        unblockSection
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onChange(of: bgImageItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    theme.addWallpaper(data)
                    BeansHaptics.success()
                }
            }
        }
        .sheet(isPresented: $showSourceImport) {
            ThirdPartySourceImportSheet()
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showFontImporter) {
            FontDocumentPicker { url in
                installFont(from: url)
            }
            .ignoresSafeArea()
        }
    }

    /// 校验扩展名并安装字体（asCopy 返回的 URL 已在沙盒内，可直接读取）
    private func installFont(from url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            ToastCenter.shared.show("请选择 ttf / otf 字体文件")
            return
        }
        if let name = FontManager.install(from: url) {
            BeansHaptics.success()
            ToastCenter.shared.show("字体已应用：\(name)")
        } else {
            ToastCenter.shared.show("字体安装失败，请使用 ttf / otf 文件")
        }
    }

    /// 外观设置（原「我的」页外观折叠内容）
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "外观")
            // 主题模式：液态玻璃行，点击展开 / 收起全部外观设置
            Button {
                BeansHaptics.select()
                withAnimation(.easeInOut(duration: 0.25)) {
                    appearanceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("主题模式")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Image(systemName: appearanceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansSecondary.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if appearanceExpanded {
            VStack(alignment: .leading, spacing: 14) {
                Picker("主题模式", selection: $themeModeRaw) {
                    ForEach(BeansThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("玻璃材质", selection: Binding(
                    get: { theme.fxStyle },
                    set: { theme.setFXStyle($0) }
                )) {
                    ForEach(BeansFXStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Divider().overlay(Color.beansSecondary.opacity(0.15))

                HStack {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("自定义强调色")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { theme.customAccent ?? Color.beansAmber },
                        set: { theme.setCustomAccent($0.hexString) }
                    ))
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        theme.clearCustomAccent()
                        BeansHaptics.select()
                    } label: {
                        Text("恢复预设")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(theme.customAccentHex == nil ? "使用预设主题" : "已自定义")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansSecondary)
                }

                    Divider().overlay(Color.beansSecondary.opacity(0.15))

                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("主页背景色")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { theme.customBackground ?? Color.beansBackground },
                            set: { theme.setBackground($0.hexString) }
                        ))
                        .labelsHidden()
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        PhotosPicker(selection: $bgImageItem, matching: .images) {
                            HStack(spacing: 8) {
                                Text("上传壁纸（可多张）")
                                    .font(BeansFont.appFont(15))
                                    .foregroundStyle(Color.beansLabel)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.beansAmber)
                            }
                        }
                    }
                    // 壁纸库：所有已上传壁纸，点击即应用为当前背景
                    if !theme.wallpaperPaths.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(theme.wallpaperPaths, id: \.self) { path in
                                wallpaperCell(path: path)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.beansSecondary)
                            Text("还没有壁纸，上传后会显示在这里")
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansSecondary)
                            Spacer()
                        }
                    }
                    HStack(spacing: 12) {
                        if theme.customBackgroundImage != nil {
                            Button {
                                theme.clearBackgroundImage()
                                BeansHaptics.select()
                            } label: {
                                Text("清除当前背景")
                                    .font(BeansFont.appFont(13, .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text(theme.customBackgroundImage == nil ? "当前：默认背景" : "当前：已应用壁纸")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansSecondary)
                    }
                Toggle(isOn: Binding(
                    get: { theme.backgroundSyncAll },
                    set: { theme.setBackgroundSyncAll($0) }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.beansAmber)
                        Text("同步到搜索 / 音乐库 / 我的")
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Divider().overlay(Color.beansSecondary.opacity(0.15))

                HStack {
                    Button {
                        theme.setBackground("")
                        BeansHaptics.select()
                    } label: {
                        Text("恢复默认背景")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Divider().overlay(Color.beansSecondary.opacity(0.15))

                HStack {
                    Image(systemName: "textformat")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("全局字体")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text(FontManager.installedFontName ?? "系统默认")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansSecondary)
                }
                HStack(spacing: 12) {
                    Button {
                        showFontImporter = true
                    } label: {
                        Text("上传字体")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        FontManager.clear()
                        BeansHaptics.select()
                        ToastCenter.shared.show("已恢复系统默认字体")
                    } label: {
                        Text("恢复默认字体")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                Text("支持 ttf / otf 字体，上传后全局生效（含歌词），重启保留")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)

            }
            .padding(16)
            .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
            .beansCardShadow(radius: 9, y: 3)
            }
        }
    }

    /// 播放与歌词设置（借鉴 Kumone：音质 / 免费听歌 / 显示歌词翻译）
    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "播放与歌词")
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("音质")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Picker("音质", selection: $audioQualityRaw) {
                        ForEach(BeansAudioQuality.allCases) { q in
                            Text(q.displayName).tag(q.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("无损与 Hi-Res 需要黑胶 VIP，未开通时自动回落到可用音质")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansSecondary)
                }

                Divider().overlay(Color.beansSecondary.opacity(0.15))

                Toggle(isOn: $enableUnblock) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("免费听歌")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text("灰色 / VIP / 周杰伦等版权歌曲自动从第三方音源匹配播放（默认关闭，手动开启）")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansSecondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Divider().overlay(Color.beansSecondary.opacity(0.15))

                Toggle(isOn: $lyricTranslation) {
                    HStack(spacing: 12) {
                        Image(systemName: "character.bubble.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示歌词翻译")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text("当前播放歌词下方显示译文（网易云 tlyric）")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansSecondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)
            }
            .padding(16)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .beansCardShadow(radius: 9, y: 3)
        }
    }

    /// 第三方音源管理：内置源开关 + 导入自定义源
    private var unblockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "第三方音源")
            VStack(spacing: 10) {
                unblockSourceToggle(id: "pyncmd", icon: "bolt.fill", title: "GD 音乐台", subtitle: "按网易云 ID 取高音质地址")
                unblockSourceToggle(id: "kuwo", icon: "music.note", title: "酷我音源", subtitle: "酷我搜索 + 双直链兜底")
                unblockSourceToggle(id: "kugou", icon: "music.note.list", title: "酷狗音乐音源", subtitle: "酷狗音乐搜索 + 播放直链")
                unblockSourceToggle(id: "bodian", icon: "waveform.badge.plus", title: "波点音源", subtitle: "波点签名取流（Splayer 解锁插件）")

                Divider().overlay(Color.beansSecondary.opacity(0.15))

                Button {
                    BeansHaptics.tap()
                    showSourceImport = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("导入第三方源")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.beansSecondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                if unblockStore.customSources.isEmpty {
                    Text("尚未导入自定义音源（JSON 配置：请求模板 + 播放地址字段路径）")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansSecondary)
                } else {
                    ForEach(unblockStore.customSources) { source in
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.beansAmber)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(BeansFont.appFont(14, .semibold))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                Text(source.kind == "netease-id" ? "按网易云 ID 查询" : "关键词查询")
                                    .font(BeansFont.appFont(10))
                                    .foregroundStyle(Color.beansSecondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                BeansHaptics.medium()
                                unblockStore.remove(source)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .beansCardShadow(radius: 9, y: 3)
        }
    }

    private func unblockSourceToggle(id: String, icon: String, title: String, subtitle: String) -> some View {
        Toggle(isOn: Binding(
            get: { unblockStore.isEnabled(id) },
            set: {
                unblockStore.setBuiltin(id, enabled: $0)
                ToastCenter.shared.show("部分音源开关需重启 App 后完全生效")
            }
        )) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BeansFont.appFont(14))
                        .foregroundStyle(Color.beansLabel)
                    Text(subtitle)
                        .font(BeansFont.appFont(10))
                        .foregroundStyle(Color.beansSecondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color.beansAmber)
    }

    private var footerNote: some View {
        VStack(spacing: 6) {
            Text("Beans · 仅供学习交流，纯 AI 实现此应用")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansSecondary.opacity(0.7))
            Text("接入网易云音乐、QQ 音乐、酷狗音乐等公开接口")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// 壁纸格子：点击应用为当前背景；使用中的壁纸显示主题色边框+勾选；右上角删除
    private func wallpaperCell(path: String) -> some View {
        let isActive = path == theme.backgroundImagePath
        return ZStack(alignment: .topTrailing) {
            Button {
                BeansHaptics.tap()
                theme.applyWallpaper(at: path)
            } label: {
                Group {
                    if let img = UIImage(contentsOfFile: path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.beansGlassFill
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.beansAmber)
                            .background(Circle().fill(.ultraThinMaterial))
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                BeansHaptics.medium()
                theme.deleteWallpaper(at: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.beansSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }
}

// MARK: - 网易云听歌排行详情

struct NetEaseRankSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    let week: [PlayRecordItem]
    let all: [PlayRecordItem]
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("范围", selection: $tab) {
                    Text("最近一周").tag(0)
                    Text("所有时间").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                let items = tab == 0 ? week : all
                if items.isEmpty {
                    EmptyStateView(icon: "chart.bar", text: "暂无播放记录")
                } else {
                    List {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                BeansHaptics.tap()
                                player.play(songs: items.map(\.song), startAt: index)
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(BeansFont.appFont(13, .bold, .rounded))
                                        .foregroundStyle(index < 3 ? Color.beansAmber : Color.beansSecondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.song.name)
                                            .font(BeansFont.appFont(15))
                                            .foregroundStyle(Color.beansLabel)
                                            .lineLimit(1)
                                        Text(item.song.artists)
                                            .font(BeansFont.appFont(12))
                                            .foregroundStyle(Color.beansSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(item.playCount) 次")
                                        .font(BeansFont.appFont(12, .regular, .monospaced))
                                        .foregroundStyle(Color.beansSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background {
                                                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .background(LinearGradient.beansBackdrop)
                }
            }
            .navigationTitle("听歌排行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 字体文件选择器（UIDocumentPicker 包装，比 SwiftUI fileImporter 稳定：所有文件可选，系统 asCopy 复制到沙盒）

struct FontDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FontDocumentPicker
        init(_ parent: FontDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

