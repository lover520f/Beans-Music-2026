import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue

    @State private var showHistory = false
    @State private var confirmLogout = false
    @State private var showQQLogin = false
    @State private var showLogin = false
    @State private var confirmQQLogout = false
    @State private var bgImageItem: PhotosPickerItem?
    @State private var appearanceExpanded = false
    @State private var weekRecord: [PlayRecordItem] = []
    @State private var allRecord: [PlayRecordItem] = []

    @State private var showNetEaseRank = false
    @State private var showFontImporter = false
    @State private var showSleepTimer = false
    @ObservedObject private var qqAuth = QQMusicAuth.shared

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var appVersionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Beans · \\(ver) (\\(build))"
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
                    userCard
                    featuresGrid
                    settingsSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 190)
            }
            .scrollIndicators(.hidden)
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
        .task(id: auth.isLoggedIn) { await loadNetEaseRank() }
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
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showQQLogin) {
            QQLoginSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet()
                .environmentObject(player)
        }
        .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                player.clearHistory()
                auth.logout()
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
        // 字体导入改用 UIDocumentPicker（asCopy 由系统直接复制到沙盒），避免 fileImporter 点选无反应/安全作用域读取失败
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

    private var userCard: some View {
        VStack(spacing: 16) {
            Button {
                BeansHaptics.tap()
                // 免登录使用：未登录时点击进入网易云登录（可选，用于同步歌单）
                if !auth.isLoggedIn {
                    showLogin = true
                }
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
                        Text(auth.user?.nickname ?? (auth.isLoggedIn ? "未登录" : "免登录 · 点击登录"))
                            .font(BeansFont.appFont(20, .bold))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(1)
                        Text(auth.isLoggedIn ? "UID \(auth.user?.uid ?? 0)" : "登录后可同步网易云歌单")
                            .font(BeansFont.appFont(12, .regular, .monospaced))
                            .foregroundStyle(Color.beansSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !auth.isLoggedIn {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.beansSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .padding(16)
        .background {
            GlassEffectContainer {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear, in: .rect(cornerRadius: 24))
            }
        }
        .beansCardShadow(radius: 10, y: 4)
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
                featureCell(icon: qqAuth.isLoggedIn ? "checkmark.seal.fill" : "globe", title: "QQ 音乐", subtitle: qqAuth.isLoggedIn ? (qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname) : "登录后播放 QQ 歌曲") {
                    BeansHaptics.tap()
                    if qqAuth.isLoggedIn {
                        confirmQQLogout = true
                    } else {
                        showQQLogin = true
                    }
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
                GlassEffectContainer {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private var settingsSection: some View {
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
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
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
            GlassEffectContainer {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
            .beansCardShadow(radius: 9, y: 3)
            }
        }
    }

    private func row(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 28)
                Text(title)
                    .font(BeansFont.appFont(15))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.beansSecondary.opacity(0.6))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Text("仅供学习交流，纯 AI 实现此应用\n接入网易云音乐、QQ 音乐等公开接口，请勿用于商业用途")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                GlassEffectContainer {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .beansCardShadow(radius: 9, y: 3)

            Button(role: .destructive) {
                confirmLogout = true
            } label: {
                Text("退出登录")
                    .font(BeansFont.appFont(15, .semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
            GlassEffectContainer {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
            }
            .buttonStyle(.plain)
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
                                    GlassEffectContainer {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(.clear)
                                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
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
