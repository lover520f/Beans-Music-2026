import SwiftUI

// MARK: - 刷抖音模式（竖向翻页推荐流：上滑 / 下滑切歌，单击播放 / 暂停）

struct DouyinModeSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// 待浏览歌曲队列（默认传入当前播放队列 / 每日推荐）
    let songs: [Song]

    @State private var page = 0
    @State private var autoLoaded = false

    private var currentSong: Song {
        songs.indices.contains(page) ? songs[page] : songs.first ?? Song(id: 0, name: "", artists: "", album: "", coverURL: nil, duration: 0)
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 背景：当前歌曲封面毛玻璃 + 暗色渐变（跟随封面，不参与 SwiftUI 布局）
            CoverBlurBackground(url: currentSong.coverURL, scheme: colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if songs.isEmpty {
                EmptyStateView(icon: "rectangle.stack", text: "暂无歌曲可浏览\n请先在播放列表或每日推荐中打开")
            } else {
                TabView(selection: $page) {
                    ForEach(Array(songs.enumerated()), id: \.element.identityKey) { index, song in
                        DouyinPageView(song: song, isCurrent: player.currentSong?.identityKey == song.identityKey)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            // 顶部栏：关闭 + 标题
            VStack {
                HStack {
                    Button {
                        BeansHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Text("刷抖音")
                        .font(BeansFont.appFont(16, .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                // 底部提示
                Text("上滑 / 下滑切换歌曲")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 12)
            }
            .allowsHitTesting(false)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if !autoLoaded, !songs.isEmpty {
                autoLoaded = true
                player.play(songs: songs, startAt: page)
            }
        }
        .onChange(of: page) { _, newPage in
            guard songs.indices.contains(newPage) else { return }
            player.play(songs: songs, startAt: newPage)
        }
    }
}

/// 抖音单页：大封面 + 歌名 + 播放 / 暂停
struct DouyinPageView: View {
    @EnvironmentObject private var player: PlayerManager
    let song: Song
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 22) {
                Spacer()
                CoverImage(url: song.coverURL, size: 300, cornerRadius: 28)
                    .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
                VStack(spacing: 8) {
                    Text(song.name)
                        .font(BeansFont.appFont(22, .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(song.artists)
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 32)
                Button {
                    BeansHaptics.tap()
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying && isCurrent ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
}
