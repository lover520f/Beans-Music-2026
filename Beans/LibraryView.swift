import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var showHistory = false
    @State private var selectedPlaylist: Playlist?
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingDelete: Playlist?
    @State private var showDeleteConfirm = false
    @State private var source: SearchProvider = .netease

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
                    if source == .netease { playlistsSection } else { qqFavoritesSection }
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
            Text("输入歌单名称，创建后同步到网易云")
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
                    Text(source == .netease ? "\(auth.playlists.count) 个歌单 · 本地收藏" : "\(favorites.qqFavoriteSongs.count) 首 QQ 收藏")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansSecondary)
                }
                Spacer()
                GlassIconButton(systemName: "arrow.clockwise") {
                    BeansHaptics.tap()
                    Task { await auth.loadLibrary() }
                }
            }
            // 统计胶囊行
            HStack(spacing: 10) {
                if source == .netease {
                    statPill(icon: "square.stack.fill", value: "\(auth.playlists.count)", label: "歌单")
                } else {
                    statPill(icon: "heart.fill", value: "\(favorites.qqFavoriteSongs.count)", label: "收藏")
                }
                statPill(icon: "clock.arrow.circlepath", value: "\(player.history.count)", label: "最近播放")
            }
        }
        .padding(.top, 8)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.beansAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(BeansFont.appFont(15, .bold, .rounded))
                    .foregroundStyle(Color.beansLabel)
                Text(label)
                    .font(BeansFont.appFont(10))
                    .foregroundStyle(Color.beansSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            GlassEffectContainer {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的歌单", trailing: "新建") {
                BeansHaptics.tap()
                newPlaylistName = ""
                showCreatePlaylist = true
            }
            if auth.playlists.isEmpty {
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
                                        .foregroundStyle(Color.beansSecondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansSecondary.opacity(0.6))
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
                        Divider().overlay(Color.beansSecondary.opacity(0.12))
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
                                    .foregroundStyle(Color.beansSecondary.opacity(0.45))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.beansSecondary)
                            }
                            Text("新建歌单")
                                .font(BeansFont.appFont(15, .medium))
                                .foregroundStyle(Color.beansSecondary)
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
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
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
                        .foregroundStyle(Color.beansSecondary.opacity(0.45))
                        .frame(width: 160, height: 160)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.beansSecondary)
                }
                Text("新建歌单")
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(Color.beansSecondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
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
                        Divider().overlay(Color.beansSecondary.opacity(0.15))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
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
                    .foregroundStyle(source == p ? Color.white : Color.beansSecondary)
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
            GlassEffectContainer {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.clear, in: Capsule())
            }
        }
        .clipShape(Capsule())
        .beansCardShadow(radius: 6, y: 2)
    }

    /// QQ 音乐收藏（红心歌曲，本地持久化 + 云端尽力同步）
    private var qqFavoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "QQ 收藏", trailing: favorites.qqFavoriteSongs.isEmpty ? nil : "\(favorites.qqFavoriteSongs.count) 首") {}
            if favorites.qqFavoriteSongs.isEmpty {
                EmptyStateView(icon: "heart", text: "还没有收藏的 QQ 歌曲\n在播放器点击红心即可收藏")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(favorites.qqFavoriteSongs.enumerated()), id: \.element.id) { index, song in
                        SongCell(song: song) {
                            player.play(songs: favorites.qqFavoriteSongs, startAt: index)
                        }
                        Divider().overlay(Color.beansSecondary.opacity(0.15))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    // MARK: - 歌单新建 / 删除

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.show("请输入歌单名称")
            return
        }
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
    }

    private func requestDelete(_ playlist: Playlist) {
        pendingDelete = playlist
        showDeleteConfirm = true
    }

    private func confirmDeletePlaylist() {
        guard let playlist = pendingDelete else { return }
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
    }

    private func playFromHistory(_ song: Song) {
        if let index = player.history.firstIndex(of: song) {
            player.play(songs: player.history, startAt: index)
        }
    }
}
