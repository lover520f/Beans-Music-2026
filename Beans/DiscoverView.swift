import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager

    @State private var topLists: [TopList] = []
    @State private var dailySongs: [Song] = []
    @State private var personalized: [Playlist] = []

    @State private var loading = true
    @State private var errorMessage: String?
    @State private var selectedTopList: TopList?
    @State private var selectedPlaylist: Playlist?
    @State private var showDailyList = false
    /// 首页数据源：网易云 / QQ音乐（与搜索页同一控件样式）
    @State private var source: SearchProvider = .netease
    @State private var qqTopLists: [QQTopInfo] = []
    @State private var selectedQQTopList: QQTopInfo?
    @State private var selectedQQPlaylist: Playlist?
    @State private var kugouTopLists: [KugouMusicAPI.KugouTopInfo] = []
    @State private var selectedKugouTopList: KugouMusicAPI.KugouTopInfo?

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 主页背景：壁纸/背景色永远在发现页生效（homeMode），同步开启时其他页面也生效
            GlassBackdrop(customColor: theme.customBackground, homeMode: true)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    providerPicker
                    if let errorMessage {
                        ErrorStateView(message: errorMessage) {
                            Task { await load() }
                        }
                    } else if loading {
                        LoadingStateView()
                    } else {
                        if !dailySongs.isEmpty {
                            dailySection.sectionEntrance(delay: 0)
                        }
                        if !topLists.isEmpty {
                            topListsSection.sectionEntrance(delay: 0.08)
                        }
                        if !personalized.isEmpty {
                            personalizedSection.sectionEntrance(delay: 0.16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 190)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .task(id: source) { await load() }
            .sheet(item: $selectedTopList) { topList in
                TopListDetailView(topList: topList)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedPlaylist) { playlist in
                PlaylistView(playlist: playlist)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedQQTopList) { info in
                QQTopListDetailView(topID: info.id, name: info.name)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedQQPlaylist) { playlist in
                QQPlaylistSongsSheet(playlist: playlist)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedKugouTopList) { info in
                KugouTopListDetailView(info: info)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showDailyList) {
                DailySongsSheet(songs: dailySongs)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
        }
    }

    /// 顶部问候区：大标题 + 刷新按钮
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(BeansFont.appFont(30, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Text(auth.user?.nickname ?? "发现好音乐")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansSecondary)
                }
                Spacer()
                GlassIconButton(systemName: "arrow.clockwise") {
                    BeansHaptics.tap()
                    Task { await load() }
                }
            }
        }
        .padding(.top, 8)
    }

    /// 平台选择（网易云 / QQ音乐，样式与搜索页一致）
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
                        BeansGlass(shape: Capsule())
        }
        .clipShape(Capsule())
        .beansCardShadow(radius: 6, y: 2)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }


    /// 每日推荐封面右下角播放状态：当前播放中显示动态指示器，暂停显示暂停，其余显示播放
    @ViewBuilder
    private func dailyPlayStateBadge(for song: Song) -> some View {
        let isCurrent = player.currentSong?.identityKey == song.identityKey
        ZStack {
            if isCurrent && player.isPlaying {
                NowPlayingIndicator()
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.45), in: Circle())
            } else {
                Image(systemName: isCurrent ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        .padding(7)
    }

    /// 网易云排行榜：只保留 热歌榜 / 飙升榜 / 新歌榜 / 原创榜 四个，热歌榜排第一
    private var filteredTopLists: [TopList] {
        let order = ["热歌榜", "飙升榜", "新歌榜", "原创榜"]
        var result: [TopList] = []
        for key in order {
            if let item = topLists.first(where: { $0.name.contains(key) }) {
                result.append(item)
            }
        }
        return result
    }

    // MARK: - 排行榜（竖排行列表）

    private var topListsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "排行榜")
            VStack(spacing: 0) {
                if source == .netease {
                    ForEach(Array(filteredTopLists.enumerated()), id: \.element.id) { index, topList in
                        rankRow(index: index, name: topList.name, subtitle: topList.updateFrequency, coverURL: topList.coverURL) {
                            BeansHaptics.tap()
                            selectedTopList = topList
                        }
                        Divider().overlay(Color.beansSecondary.opacity(0.12))
                    }
                } else if source == .qq {
                    ForEach(Array(qqTopLists.prefix(6).enumerated()), id: \.element.id) { index, info in
                        rankRow(index: index, name: info.name, subtitle: "QQ 峰尖榜", coverURL: info.coverURL) {
                            BeansHaptics.tap()
                            selectedQQTopList = info
                        }
                        Divider().overlay(Color.beansSecondary.opacity(0.12))
                    }
                } else {
                    ForEach(Array(kugouTopLists.prefix(6).enumerated()), id: \.element.id) { index, info in
                        rankRow(index: index, name: info.name, subtitle: "酷狗榜单", coverURL: info.coverURL) {
                            BeansHaptics.tap()
                            selectedKugouTopList = info
                        }
                        Divider().overlay(Color.beansSecondary.opacity(0.12))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .beansCardShadow(radius: 9, y: 3)
        }
    }

    private func rankRow(index: Int, name: String, subtitle: String, coverURL: URL?, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(BeansFont.appFont(16, .bold, .rounded))
                    .foregroundStyle(index < 3 ? Color.beansAmber : Color.beansSecondary)
                    .frame(width: 24)
                CoverImage(url: coverURL, size: 52, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansSecondary.opacity(0.6))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// QQ 峰尖榜占位渐变（保留备用）
    private func qqRankGradient(_ name: String) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.35, green: 0.55, blue: 0.95), Color(red: 0.20, green: 0.30, blue: 0.65)],
            [Color(red: 0.95, green: 0.42, blue: 0.36), Color(red: 0.70, green: 0.18, blue: 0.20)],
            [Color(red: 0.20, green: 0.78, blue: 0.62), Color(red: 0.08, green: 0.52, blue: 0.44)],
            [Color(red: 0.92, green: 0.62, blue: 0.25), Color(red: 0.72, green: 0.38, blue: 0.12)],
            [Color(red: 0.62, green: 0.45, blue: 0.90), Color(red: 0.40, green: 0.25, blue: 0.68)],
            [Color(red: 0.30, green: 0.70, blue: 0.85), Color(red: 0.16, green: 0.45, blue: 0.65)]
        ]
        let seed = abs(name.hashValue) % palettes.count
        return LinearGradient(colors: palettes[seed], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 每日推荐（横滑歌曲卡 + 播放）

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "每日推荐", trailing: "查看全部") {
                BeansHaptics.tap()
                showDailyList = true
            }
            // 横滑歌曲卡：每日推荐前 8 首
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(dailySongs.prefix(8).enumerated()), id: \.element.id) { index, song in
                        Button {
                            BeansHaptics.tap()
                            player.play(songs: dailySongs, startAt: index)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(url: song.coverURL, size: 108, cornerRadius: 16)
                                    .overlay(alignment: .topLeading) {
                                        if song.isVIP {
                                            Text("VIP")
                                                .font(BeansFont.appFont(9, .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                                                .padding(6)
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        dailyPlayStateBadge(for: song)
                                    }
                                Text(song.name)
                                    .font(BeansFont.appFont(12, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                    .frame(width: 108, alignment: .leading)
                                Text(song.artists.isEmpty ? song.album : song.artists)
                                    .font(BeansFont.appFont(10))
                                    .foregroundStyle(Color.beansSecondary)
                                    .lineLimit(1)
                                    .frame(width: 108, alignment: .leading)
                            }
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.94))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 歌单广场（双列网格）

    private var personalizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "歌单广场")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(personalized) { playlist in
                    Button {
                        if source == .qq {
                            selectedQQPlaylist = playlist
                        } else {
                            selectedPlaylist = playlist
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverImage(url: playlist.coverURL, size: 144, cornerRadius: 18)
                                .frame(maxWidth: .infinity)
                            Text(playlist.name)
                                .font(BeansFont.appFont(12, .medium))
                                .foregroundStyle(Color.beansLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.96))
                }
            }
        }
    }

    // MARK: - 动作

    private func load() async {
        loading = true
        errorMessage = nil
        if source == .qq {
            do {
                async let a = QQMusicAPI.shared.recommendSongs(limit: 30)
                async let b = QQMusicAPI.shared.topLists()
                async let c = QQMusicAPI.shared.recommendPlaylists(limit: 12)
                let (dr, tl, pp) = try await (a, b, c)
                dailySongs = dr
                qqTopLists = tl
                personalized = pp
                loading = false
            } catch {
                errorMessage = error.localizedDescription
                loading = false
            }
        } else if source == .kugou {
            do {
                async let a = KugouMusicAPI.shared.topListSongs(rankID: 8888, page: 1, limit: 30)
                async let b = KugouMusicAPI.shared.topLists()
                async let c = KugouMusicAPI.shared.playlists(page: 1, limit: 12)
                let (dr, tl, pp) = try await (a, b, c)
                dailySongs = dr
                kugouTopLists = tl
                personalized = pp
                loading = false
            } catch {
                errorMessage = error.localizedDescription
                loading = false
            }
        } else {
            async let a = NetEaseAPI.shared.topLists()
            async let b = NetEaseAPI.shared.dailyRecommend()
            async let c = NetEaseAPI.shared.playlistSquare(limit: 10)
            do {
                let (tl, dr, pp) = try await (a, b, c)
                topLists = tl
                dailySongs = dr
                personalized = pp
                loading = false
            } catch {
                errorMessage = error.localizedDescription
                loading = false
            }
        }
    }
}

// MARK: - 酷狗榜单详情

struct KugouTopListDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore

    let info: KugouMusicAPI.KugouTopInfo
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        Section {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: tracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .navigationTitle(info.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await KugouMusicAPI.shared.topListSongs(rankID: info.id, page: 1, limit: 50)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - QQ 峰尖榜详情

struct QQTopListDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore

    let topID: Int
    let name: String
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        Section {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: tracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await QQMusicAPI.shared.topListSongs(topid: topID)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - QQ 歌单内歌曲

struct QQPlaylistSongsSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore

    let playlist: Playlist
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        Section {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: tracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await QQMusicAPI.shared.playlistSongs(listID: playlist.id)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - 每日推荐全部歌曲

struct DailySongsSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore

    let songs: [Song]

    var body: some View {
        let _ = theme.accent
        NavigationStack {
            Group {
                if songs.isEmpty {
                    EmptyStateView(icon: "sparkles", text: "今日推荐加载中，下拉刷新试试")
                } else {
                    List {
                    Section {
                        HStack(spacing: 12) {
                            GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                BeansHaptics.tap()
                                player.play(songs: songs, startAt: 0)
                            }
                            GlassButton(title: "随机播放", systemName: "shuffle") {
                                BeansHaptics.tap()
                                player.play(songs: songs, startAt: Int.random(in: 0..<songs.count))
                            }
                        }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 8)
                    }
                    Section {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongCell(song: song, glassRow: true) {
                                BeansHaptics.tap()
                                player.play(songs: songs, startAt: index)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                }
            }
            .navigationTitle("今日推荐")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
// MARK: - 排行榜详情

struct TopListDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore

    let topList: TopList
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        header
                        Section {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: tracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .navigationTitle(topList.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            CoverImage(url: topList.coverURL, size: 88, cornerRadius: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text(topList.name)
                    .font(BeansFont.appFont(18, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text(topList.updateFrequency)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)
                Text("\(tracks.count) 首")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await NetEaseAPI.shared.playlistTracks(id: topList.id)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}


