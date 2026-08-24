import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var qqAuth = QQMusicAuth.shared

    @State private var showHistory = false
    @State private var selectedPlaylist: Playlist?
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingDelete: Playlist?
    @State private var showDeleteConfirm = false
    @State private var source: SearchProvider = .netease
    @State private var qqPlaylists: [Playlist] = []
    @State private var qqLoading = false
    @State private var kugouPlaylists: [Playlist] = []
    @State private var kugouLoading = false
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 页面背景：同步开启时显示壁纸/背景色，否则默认氛围渐变
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    providerPicker
                    if source == .netease { playlistsSection } else if source == .qq { qqSection } else { kugouSection }
                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 190)
            }
            .scrollIndicators(.hidden)
            .refreshable { await auth.loadLibrary() }
        }
        .task { await auth.loadLibrary() }
        .task(id: source) {
            if source == .qq {
                await loadQQPlaylists()
            }
            if source == .kugou { await loadKugouPlaylists() }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .environmentObject(auth)
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistView(playlist: playlist)
                .environmentObject(player)
                .environmentObject(auth)
        }
        .alert("新建歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("输入歌单名称，创建后同步到\(source == .netease ? "网易云" : source == .qq ? "QQ 音乐" : "酷狗音乐")")
        }
        .confirmationDialog("确定删除歌单「\(pendingDelete?.name ?? "")」吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { confirmDeletePlaylist() }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("音乐库")
                        .font(BeansFont.appFont(30, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Text(source == .netease ? "网易云歌单" : source == .qq ? "QQ 音乐收藏与歌单" : "酷狗音乐歌单")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                GlassIconButton(systemName: "arrow.clockwise") {
                    BeansHaptics.tap()
                    Task { await auth.loadLibrary() }
                }
            }
        }
        .padding(.top, 8)
    }


    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的歌单", trailing: auth.isLoggedIn ? "新建" : nil) {
                if auth.isLoggedIn {
                    BeansHaptics.tap()
                    newPlaylistName = ""
                    showCreatePlaylist = true
                }
            }
            if !auth.isLoggedIn {
                EmptyStateView(icon: "music.note.list", text: "登录网易云音乐后即可查看你的歌单")
            } else if auth.playlists.isEmpty {
                createPlaylistCard
            } else {
                VStack(spacing: 0) {
                    ForEach(auth.playlists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.coverURL, size: 56, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount) 首")
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                BeansHaptics.tap()
                                requestDelete(playlist)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                    // 新建歌单行
                    Button {
                        BeansHaptics.tap()
                        newPlaylistName = ""
                        showCreatePlaylist = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                                    .foregroundStyle(Color.beansComment.opacity(0.45))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.beansComment)
                            }
                            Text("新建歌单")
                                .font(BeansFont.appFont(15, .medium))
                                .foregroundStyle(Color.beansComment)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .beansCardShadow(radius: 9, y: 3)
            }
        }
    }

    private var createPlaylistCard: some View {
        Button {
            BeansHaptics.tap()
            newPlaylistName = ""
            showCreatePlaylist = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(Color.beansComment.opacity(0.45))
                        .frame(width: 160, height: 160)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.beansComment)
                }
                Text("新建歌单")
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(Color.beansComment)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "最近播放", trailing: "查看全部") {
                showHistory = true
            }
            if player.history.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", text: "暂无播放记录")
            } else {
                VStack(spacing: 0) {
                    ForEach(player.history.prefix(5)) { song in
                        SongCell(song: song) {
                            playFromHistory(song)
                        }
                        Divider().overlay(Color.beansComment.opacity(0.15))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    /// 平台选择（网易云 / QQ音乐，样式与主页一致）
    private var providerPicker: some View {
        HStack(spacing: 4) {
            ForEach(SearchProvider.allCases) { p in
                Button {
                    BeansHaptics.tap()
                    if source != p { source = p }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: p.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(p.rawValue)
                            .font(BeansFont.appFont(13, .semibold))
                    }
                    .foregroundStyle(source == p ? Color.white : Color.beansComment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if source == p {
                            Capsule().fill(p.tint)
                        } else {
                            Capsule().fill(.clear)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
                        BeansGlass(shape: Capsule())
        }
        .clipShape(Capsule())
        .beansCardShadow(radius: 6, y: 2)
    }

    /// QQ 模式整体内容：用户歌单（创建 + 收藏同步）
    private var qqSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            qqPlaylistsSection
        }
    }

    /// 我的 QQ 歌单（登录后从 QQ 音乐拉取）
    private var qqPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的 QQ 歌单", trailing: qqAuth.isLoggedIn ? (qqPlaylists.isEmpty ? "新建" : "新建 · \(qqPlaylists.count) 个") : nil) {
                if qqAuth.isLoggedIn {
                    BeansHaptics.tap()
                    newPlaylistName = ""
                    showCreatePlaylist = true
                }
            }
            if !qqAuth.isLoggedIn {
                EmptyStateView(icon: "music.note.list", text: "登录 QQ 音乐后即可查看你的歌单")
            } else if qqLoading {
                LoadingStateView()
            } else if qqPlaylists.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "暂无 QQ 歌单")
            } else {
                VStack(spacing: 0) {
                    ForEach(qqPlaylists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.coverURL, size: 56, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount) 首")
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                BeansHaptics.tap()
                                requestDelete(playlist)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                }
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    // MARK: - 歌单新建 / 删除

    /// 酷狗模式整体内容：酷狗歌单（同步登录账号歌单）
    private var kugouSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            kugouPlaylistsSection
        }
    }

    /// 酷狗歌单广场（无需登录）
    private var kugouPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的酷狗歌单", trailing: kugouPlaylists.isEmpty ? nil : "\(kugouPlaylists.count) 个") {}
            if !kugouAuth.isLoggedIn {
                EmptyStateView(icon: "music.note.list", text: "登录酷狗音乐后即可查看你的歌单")
            } else if kugouLoading {
                LoadingStateView()
            } else if kugouPlaylists.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "暂未拉取到酷狗歌单\n可在「我的」检查酷狗登录状态")
            } else {
                VStack(spacing: 0) {
                    ForEach(kugouPlaylists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.coverURL, size: 56, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount) 首")
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                }
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    private func loadKugouPlaylists() async {
        guard kugouAuth.isLoggedIn, !kugouAuth.userID.isEmpty else {
            kugouPlaylists = []
            kugouLoading = false
            return
        }
        kugouLoading = true
        kugouPlaylists = (try? await KugouMusicAPI.shared.userPlaylists(userid: kugouAuth.userID)) ?? []
        kugouLoading = false
    }

    private func loadQQPlaylists() async {
        guard qqAuth.isLoggedIn else {
            qqPlaylists = []
            qqLoading = false
            return
        }
        qqLoading = true
        qqPlaylists = (try? await QQMusicAPI.shared.userPlaylists(uin: qqAuth.uin)) ?? []
        qqLoading = false
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.show("请输入歌单名称")
            return
        }
        switch source {
        case .netease:
            guard auth.isLoggedIn else {
                ToastCenter.shared.show("请先登录后再创建歌单")
                return
            }
            Task {
                do {
                    _ = try await NetEaseAPI.shared.createPlaylist(name: name)
                    ToastCenter.shared.show("歌单「\(name)」已创建")
                    newPlaylistName = ""
                    await auth.loadLibrary()
                } catch {
                    ToastCenter.shared.show("创建失败：\(error.localizedDescription)")
                }
            }
        case .qq:
            guard qqAuth.isLoggedIn else {
                ToastCenter.shared.show("请先登录 QQ 音乐后再创建歌单")
                return
            }
            Task {
                do {
                    let ok = try await QQMusicAPI.shared.createPlaylist(name: name)
                    if ok {
                        ToastCenter.shared.show("歌单「\(name)」已创建")
                        newPlaylistName = ""
                        await loadQQPlaylists()
                    } else {
                        ToastCenter.shared.show("创建失败，请确认已登录 QQ 音乐")
                    }
                } catch {
                    ToastCenter.shared.show("创建失败：\(error.localizedDescription)")
                }
            }
        case .kugou:
            guard kugouAuth.isLoggedIn else {
                ToastCenter.shared.show("请先登录酷狗音乐后再创建歌单")
                return
            }
            Task {
                do {
                    let ok = try await KugouMusicAPI.shared.createPlaylist(name: name)
                    if ok {
                        ToastCenter.shared.show("歌单「\(name)」已创建")
                        newPlaylistName = ""
                        await loadKugouPlaylists()
                    } else {
                        ToastCenter.shared.show("创建失败，请确认已登录酷狗音乐")
                    }
                } catch {
                    ToastCenter.shared.show("创建失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func requestDelete(_ playlist: Playlist) {
        pendingDelete = playlist
        showDeleteConfirm = true
    }

    private func confirmDeletePlaylist() {
        guard let playlist = pendingDelete else { return }
        switch source {
        case .netease:
            Task {
                do {
                    let ok = try await NetEaseAPI.shared.deletePlaylist(id: playlist.id)
                    if ok {
                        ToastCenter.shared.show("已删除歌单「\(playlist.name)」")
                        await auth.loadLibrary()
                    } else {
                        ToastCenter.shared.show("删除失败，请稍后再试")
                    }
                } catch {
                    ToastCenter.shared.show("删除失败：\(error.localizedDescription)")
                }
            }
        case .qq:
            Task {
                do {
                    let ok = try await QQMusicAPI.shared.deletePlaylist(dirid: playlist.id)
                    if ok {
                        ToastCenter.shared.show("已删除歌单「\(playlist.name)」")
                        await loadQQPlaylists()
                    } else {
                        ToastCenter.shared.show("删除失败，请确认已登录 QQ 音乐")
                    }
                } catch {
                    ToastCenter.shared.show("删除失败：\(error.localizedDescription)")
                }
            }
        case .kugou:
            Task {
                do {
                    let ok = try await KugouMusicAPI.shared.deletePlaylist(pid: playlist.id)
                    if ok {
                        ToastCenter.shared.show("已删除歌单「\(playlist.name)」")
                        await loadKugouPlaylists()
                    } else {
                        ToastCenter.shared.show("删除失败，请确认已登录酷狗音乐")
                    }
                } catch {
                    ToastCenter.shared.show("删除失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func playFromHistory(_ song: Song) {
        if let index = player.history.firstIndex(of: song) {
            player.play(songs: player.history, startAt: index)
        }
    }
}

