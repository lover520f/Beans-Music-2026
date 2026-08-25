import ActivityKit
import AVFoundation
import MediaPlayer
import SwiftUI

enum PlayMode: String, CaseIterable, Identifiable {
    case sequential
    case repeatOne
    case shuffle

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sequential: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }
}

final class PlayerManager: NSObject, ObservableObject {
    @Published var queue: [Song] = []
    @Published var currentIndex = 0
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var loadFailed = false
    /// 切歌代次：防止旧歌的 URL 解析任务覆盖新歌（快速切歌时）
    private var loadGeneration = 0
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var playMode: PlayMode = .sequential
    @Published var rate: Double = 1.0
    @Published var sleepTimerEndsAt: Date?
    @Published var sleepTimerRemaining: Int = 0
    @Published var history: [Song] = []
    @Published var playCounts: [String: Int] = [:]

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var sessionConfigured = false
    private var playOrder: [Int] = []
    private var orderPosition = 0
    private var sleepTimer: Timer?
    private var lastCountedSongID: String?
    private var wasPlayingBeforeInterruption = false
    private var liveActivity: Any?
    private var lastLiveActivitySync: Date?

    private let historyKey = "beans.history"
    private let countsKey = "beans.playcounts"
    private let liveActivityKey = "beans.liveActivity"
    private let audioMixKey = "beans.audio.mixothers.v1"
    private let defaults = UserDefaults.standard

    var currentSong: Song? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    override init() {
        super.init()
        loadHistory()
        loadPlayCounts()
        observeInterruptions()
        setupRemoteCommands()
    }

    // MARK: - 播放控制

    func play(songs: [Song], startAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs
        buildPlayOrder()
        jumpToOrderPosition(min(max(index, 0), songs.count - 1))
    }

    func playSong(_ song: Song, in context: [Song]) {
        play(songs: context, startAt: context.firstIndex(of: song) ?? 0)
    }

    /// 插队播放：把歌曲放到当前歌曲之后并立即播放
    func playNext(_ song: Song) {
        guard !queue.isEmpty else {
            play(songs: [song], startAt: 0)
            return
        }
        let insertAt = currentIndex + 1
        queue.insert(song, at: min(insertAt, queue.count))
        buildPlayOrder()
        jumpToOrderPosition(min(insertAt, queue.count - 1))
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: Float(rate))
            isPlaying = true
        }
        updateNowPlaying()
    }

    func next(manual: Bool = true) {
        guard !queue.isEmpty else { return }
        if playMode == .repeatOne && manual {
            restartCurrent()
            return
        }
        advance()
        loadCurrent()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // 直接切换到上一首（不再做“播放超过 3 秒先重头播放”的判断）
        if playMode == .shuffle {
            orderPosition = (orderPosition - 1 + playOrder.count) % playOrder.count
            currentIndex = playOrder[orderPosition]
        } else {
            currentIndex = (currentIndex - 1 + queue.count) % queue.count
        }
        loadCurrent()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, max(duration, 0)))
        progress = clamped
        // 用 seek 完成回调同步真实进度：避免暂停状态下拖动进度后，歌词定位与实际播放位置不一致
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard let self, finished else { return }
            let actual = self.player?.currentTime().seconds ?? clamped
            if abs(actual - self.progress) > 0.25 {
                self.progress = actual
            }
        }
        updateNowPlaying()
    }

    func seekBy(_ delta: Double) {
        seek(to: progress + delta)
    }

    func togglePlayMode() {
        switch playMode {
        case .sequential: playMode = .repeatOne
        case .repeatOne: playMode = .shuffle
        case .shuffle: playMode = .sequential
        }
        buildPlayOrder()
    }

    func setRate(_ newRate: Double) {
        rate = newRate
        if isPlaying {
            player?.playImmediately(atRate: Float(newRate))
        }
        updateNowPlaying()
    }

    func playQueueIndex(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        jumpToOrderPosition(index)
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), queue.count > 1 else { return }
        let removedID = queue[index].id
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, queue.count - 1)
            loadCurrent()
        }
        buildPlayOrder(avoiding: removedID)
    }

    func retryCurrent() {
        loadFailed = false
        loadCurrent()
    }

    /// 删除单条播放历史（含持久化）
    func removeHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard history.indices.contains(index) else { continue }
            history.remove(at: index)
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    /// 清空播放历史（含持久化）
    func clearHistory() {
        history.removeAll()
        defaults.removeObject(forKey: historyKey)
    }

    /// 清空队列，仅保留当前歌曲
    func clearQueue() {
        guard !queue.isEmpty else { return }
        if let current = currentSong {
            queue = [current]
            currentIndex = 0
        } else {
            queue = []
            currentIndex = 0
        }
        buildPlayOrder()
    }

    // MARK: - 睡眠定时

    func startSleepTimer(minutes: Int) {
        stopSleepTimer()
        sleepTimerEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = minutes * 60
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let end = self.sleepTimerEndsAt else { return }
            let remain = Int(end.timeIntervalSinceNow)
            self.sleepTimerRemaining = max(0, remain)
            if remain <= 0 {
                self.stopSleepTimer()
                self.pausePlayback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    func stopSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
        sleepTimerRemaining = 0
    }

    var sleepTimerFormatted: String? {
        guard sleepTimerRemaining > 0 else { return nil }
        return String(format: "%d:%02d", sleepTimerRemaining / 60, sleepTimerRemaining % 60)
    }

    private func pausePlayback() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    // MARK: - 播放顺序

    private func buildPlayOrder(avoiding removedID: Int? = nil) {
        switch playMode {
        case .shuffle:
            var indices = Array(queue.indices).filter { $0 != removedID }
            indices.shuffle()
            playOrder = indices
            orderPosition = 0
        default:
            playOrder = Array(queue.indices)
            orderPosition = currentIndex
        }
    }

    private func advance() {
        switch playMode {
        case .shuffle:
            guard !playOrder.isEmpty else { return }
            orderPosition = (orderPosition + 1) % playOrder.count
            currentIndex = playOrder[orderPosition]
        default:
            currentIndex = (currentIndex + 1) % queue.count
            orderPosition = currentIndex
        }
    }

    private func jumpToOrderPosition(_ index: Int) {
        currentIndex = index
        if playMode == .shuffle {
            orderPosition = 0
            if let pos = playOrder.firstIndex(of: index) {
                orderPosition = pos
            }
        } else {
            orderPosition = index
        }
        loadCurrent()
    }

    // MARK: - 播放

    private func restartCurrent() {
        seek(to: 0)
        player?.playImmediately(atRate: Float(rate))
        isPlaying = true
        updateNowPlaying()
    }

    private func loadCurrent() {
        guard let song = currentSong else { return }
        loadGeneration += 1
        let generation = loadGeneration
        // 切歌立即暂停旧音频，避免新歌加载期间旧歌继续播放造成“切歌卡住”感
        player?.pause()
        duration = song.duration
        progress = 0
        isPlaying = false
        isBuffering = true
        loadFailed = false
        pushHistory(song)
        Task {
            var urlString: String?
            var resolvedThirdParty: UnblockService.Resolved?
            // 版权受限歌手（周杰伦）：允许第三方音源，但启用严格模式（歌名+歌手+时长三重匹配原唱，校验不过拒绝，绝不播放翻唱）
            // 免费听歌（灰色歌曲解锁）总开关：默认关闭，需在「我的 → 设置」手动开启
            let enableUnblock = defaults.object(forKey: "beans.enableUnblock") as? Bool ?? false
            let strictUnlock = shouldLockOfficialOnly(song)
            let quality = BeansAudioQuality.current
            if song.source == .qq, let mid = song.qqMid {
                // 优先 QQ 官方直链：登录了 VIP/SVIP 账号时 vkey 返回完整音轨；
                // 未登录/无会员时 VIP 歌曲官方 vkey 不返回地址。
                // 只有开启「免费听歌」（灰色歌曲解锁）时，官方直链失败才允许兜底
                // （网易云同名歌曲 → 第三方解锁）。未开启时绝不静默替换为其他平台的音频。
                urlString = try? await QQMusicAPI.shared.songURL(songmid: mid)
                if urlString == nil, enableUnblock {
                    (urlString, resolvedThirdParty) = await qqFallback(song: song, quality: quality, enableUnblock: enableUnblock, strict: strictUnlock)
                }
            } else if song.source == .kugou, let hash = song.kugouHash {
                // 酷狗：优先官方接口（登录后可拿完整音轨），失败且开启免费听歌时走网易云同名/第三方兜底
                urlString = try? await KugouAuth.shared.songURL(hash: hash, albumID: song.kugouAlbumID, albumAudioID: song.kugouAlbumAudioID)
                if urlString == nil, enableUnblock {
                    (urlString, resolvedThirdParty) = await kugouFallback(song: song, quality: quality, enableUnblock: enableUnblock, strict: strictUnlock)
                }
            } else if song.source == .soda {
                // 汽水音乐音源需解密，暂不支持播放
                urlString = nil
            } else {
                (urlString, resolvedThirdParty) = await neteaseResolve(song: song, quality: quality, enableUnblock: enableUnblock, strict: strictUnlock)
            }
            if let resolved = resolvedThirdParty {
                // 第三方音源只用于播放，不打扰用户（无需提示用了哪个音源）
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.setupPlayer(url: resolved.url)
                }
                return
            }
            guard let urlString, let url = URL(string: urlString) else {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.isBuffering = false
                    self.loadFailed = true
                    if song.source == .qq && song.isVIP && !enableUnblock {
                        BeansLogger.shared.log("播放失败：\(song.name) - QQ VIP 歌曲未开启免费听歌", level: .error)
                        ToastCenter.shared.show("《\(song.name)》为 QQ VIP 歌曲，请先在 我的 → 设置 → 播放设置 开启「免费听歌」")
                    } else if song.source == .kugou {
                        BeansLogger.shared.log("播放失败：\(song.name) - 酷狗无可用音源", level: .error)
                        ToastCenter.shared.show("《\(song.name)》酷狗音源不可用或需会员，请尝试其他平台")
                    } else if song.source == .soda {
                        BeansLogger.shared.log("播放失败：\(song.name) - 汽水音乐暂不支持播放", level: .error)
                        ToastCenter.shared.show("汽水音乐歌曲暂不支持播放，请使用网易云或 QQ 音乐")
                    } else if self.shouldLockOfficialOnly(song) {
                        let hasSource = UnblockSourceStore.shared.customSources.contains { $0.enabled }
                        if enableUnblock, !hasSource {
                            BeansLogger.shared.log("播放失败：\(song.name) - 未找到原唱音源（未导入或未开启第三方音源）", level: .error)
                            ToastCenter.shared.show("《\(song.name)》未找到原唱音源：请先在 设置 → 第三方音源 导入并开启音源（如星海、全豆要 JS）")
                        } else {
                            BeansLogger.shared.log("播放失败：\(song.name) - 未找到原唱音源（官方受限），拒绝翻唱版本", level: .error)
                            ToastCenter.shared.show("《\(song.name)》未找到原唱音源（官方受限），已停止播放，拒绝翻唱版本")
                        }
                    } else {
                        BeansLogger.shared.log("播放失败：\(song.name) - 无法解析播放地址", level: .error)
                    }
                }
                return
            }
            await MainActor.run {
                guard generation == self.loadGeneration else { return }
                self.setupPlayer(url: url)
            }
        }
    }

    /// 网易云播放地址解析：按设置音质取 URL，VIP/灰色歌曲交给第三方解锁（借鉴 Kumone）
    private func neteaseResolve(song: Song, quality: BeansAudioQuality, enableUnblock: Bool, strict: Bool = false) async -> (String?, UnblockService.Resolved?) {
        var urlString: String?
        var resolved: UnblockService.Resolved?
        let infos = try? await NetEaseAPI.shared.songURLInfo(ids: [song.id], level: quality.level)
        var info = infos?[song.id]
        if (info?.url == nil || info?.freeTrial == true), quality != .standard {
            // 高音质拿不到时自动回落到标准音质
            let fallback = try? await NetEaseAPI.shared.songURLInfo(ids: [song.id], level: "standard")
            info = fallback?[song.id]
        }
        // 试听片段 / 无 URL 一律不直接播放，交给第三方解锁，避免"只能试听"
        if let u = info?.url, info?.freeTrial != true {
            urlString = u
        }
        if urlString == nil, enableUnblock {
            resolved = await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                durationMS: Int(song.duration * 1000),
                neteaseID: song.id,
                strict: strict
            )
        }
        return (urlString, resolved)
    }

    /// QQ 歌曲兜底：先在网易云按 歌名+歌手 匹配同名歌曲，免费完整 URL 直接播，VIP/无 URL 交给第三方解锁
    private func qqFallback(song: Song, quality: BeansAudioQuality, enableUnblock: Bool, strict: Bool = false) async -> (String?, UnblockService.Resolved?) {
        var urlString: String?
        var resolved: UnblockService.Resolved?
        if let matched = await matchNetEaseSong(name: song.name, artists: song.artists, durationMS: Int(song.duration * 1000), strict: strict) {
            let infos = try? await NetEaseAPI.shared.songURLInfo(ids: [matched.id], level: quality.level)
            var info = infos?[matched.id]
            if (info?.url == nil || info?.freeTrial == true), quality != .standard {
                let fallback = try? await NetEaseAPI.shared.songURLInfo(ids: [matched.id], level: "standard")
                info = fallback?[matched.id]
            }
            // 免费完整 URL 直接用；试听片段 / 无 URL 交给第三方解锁
            if let u = info?.url, info?.freeTrial != true {
                urlString = u
            } else if enableUnblock {
                resolved = await UnblockService.resolve(
                    name: matched.name,
                    artists: matched.artists,
                    durationMS: Int(matched.duration * 1000),
                    neteaseID: matched.id,
                    strict: strict
                )
            }
        }
        if urlString == nil, resolved == nil, enableUnblock {
            resolved = await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                durationMS: Int(song.duration * 1000),
                neteaseID: 0,
                strict: strict
            )
        }
        return (urlString, resolved)
    }

    /// 酷狗歌曲兜底：开启免费听歌时，先按 歌名+歌手 匹配网易云同名歌曲，再交给第三方解锁
    private func kugouFallback(song: Song, quality: BeansAudioQuality, enableUnblock: Bool, strict: Bool = false) async -> (String?, UnblockService.Resolved?) {
        if let matched = await matchNetEaseSong(name: song.name, artists: song.artists, durationMS: Int(song.duration * 1000), strict: strict) {
            let result = await neteaseResolve(song: matched, quality: quality, enableUnblock: enableUnblock, strict: strict)
            if result.0 != nil || result.1 != nil { return result }
        }
        if enableUnblock {
            let resolved = await UnblockService.resolve(name: song.name, artists: song.artists, durationMS: Int(song.duration * 1000), neteaseID: 0, strict: strict)
            return (nil, resolved)
        }
        return (nil, nil)
    }

    /// 版权受限歌手名单：这些歌手的歌曲必须严格校验原唱（第三方搜索会误匹配翻唱，如周杰伦）
    /// 兼容第三方返回的英文歌手名（Jay Chou），统一按别名判断，避免漏判导致播放翻唱
    private func shouldLockOfficialOnly(_ song: Song) -> Bool {
        let artists = song.artists.lowercased()
        return artists.contains("周杰伦") || artists.contains("jay chou") || artists.contains("jaychou")
    }

    /// 在网易云按 歌名+歌手 匹配同名歌曲（QQ vkey 失败时的免费播放兜底）
    private func matchNetEaseSong(name: String, artists: String, durationMS: Int, strict: Bool = false) async -> Song? {
        let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
        guard !keyword.isEmpty,
              let results = try? await NetEaseAPI.shared.search(keyword: keyword, limit: 8),
              !results.isEmpty else { return nil }
        let target = Double(durationMS) / 1000.0
        let artistTokens = artists.lowercased().split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "&" }).map(String.init)
        // 优先：歌手匹配 + 时长接近（兼容 Jay Chou 别名）
        if let hit = results.first(where: { song in
            let durOK = abs(song.duration - target) < 12
            let songArtists = song.artists.lowercased()
            let artistOK = artistTokens.contains { !$0.isEmpty && songArtists.contains($0) }
                || (songArtists.contains("周杰伦") && artists.lowercased().contains("jay chou"))
            return durOK && artistOK
        }) { return hit }
        // 严格模式（周杰伦等版权歌手）：找不到原唱直接放弃，绝不返回翻唱
        if strict { return nil }
        // 其次：仅时长接近
        if let hit = results.min(by: { abs($0.duration - target) < abs($1.duration - target) }),
           abs(hit.duration - target) < 20 {
            return hit
        }
        // 没有任何歌名/歌手/时长关联的命中直接放弃，绝不盲匹配，避免播到与原版无关的音频
        return nil
    }


    private func setupPlayer(url: URL) {
        configureAudioSession()
        removeCurrentObservers()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.rate = Float(rate)
        self.player = player
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        isBuffering = false
        loadFailed = false
        // 修复：播放次数原先在 loadCurrent 里预计数，URL 加载失败/手动重试也会 +1，
        // 导致统计异常；改为真正开始播放时计数，且同一首歌同一会话只计一次。
        if let song = currentSong, lastCountedSongID != song.identityKey {
            bumpPlayCount(song)
            lastCountedSongID = song.identityKey
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let player = self.player else { return }
            self.progress = player.currentTime().seconds
            if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
                self.duration = itemDuration.seconds
                if self.lastLiveActivitySync == nil || Date().timeIntervalSince(self.lastLiveActivitySync!) >= 15 {
                    self.lastLiveActivitySync = Date()
                    self.syncLiveActivity()
                }
            }
            if let item = player.currentItem {
                let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if waiting != self.isBuffering {
                    self.isBuffering = waiting
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.playMode == .repeatOne {
                self.restartCurrent()
            } else {
                self.advance()
                self.loadCurrent()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.loadFailed = true
            self?.isBuffering = false
        }
        updateNowPlaying()
    }

    private func removeCurrentObservers() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
    }

    private func configureAudioSession() {
        guard !sessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            let mixWithOthers = defaults.object(forKey: audioMixKey) as? Bool ?? true
            if mixWithOthers {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
            sessionConfigured = true
        } catch {}
    }

    // MARK: - 来电/中断处理

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            player?.pause()
            isPlaying = false
        case .ended:
            if wasPlayingBeforeInterruption {
                player?.playImmediately(atRate: Float(rate))
                isPlaying = true
            }
        @unknown default:
            break
        }
    }

    // MARK: - 播放历史与统计

    private func pushHistory(_ song: Song) {
        history.removeAll { $0.identityKey == song.identityKey }
        history.insert(song, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([Song].self, from: data) else { return }
        history = saved
    }

    private func bumpPlayCount(_ song: Song) {
        playCounts[song.identityKey, default: 0] += 1
        if let data = try? JSONEncoder().encode(playCounts) {
            defaults.set(data, forKey: countsKey)
        }
    }

    private func loadPlayCounts() {
        guard let data = defaults.data(forKey: countsKey),
              let saved = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        playCounts = saved
    }

    /// 听歌排行：按播放次数排序的前几首
    var topPlayed: [(song: Song, count: Int)] {
        var result: [(song: Song, count: Int)] = []
        for (key, count) in playCounts {
            if let song = history.first(where: { $0.identityKey == key }) {
                result.append((song, count))
            }
        }
        return result.sorted { $0.count > $1.count }.prefix(8).map { $0 }
    }

    // MARK: - 锁屏/控制中心

    private func updateNowPlaying() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artists,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: max(duration, song.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let artworkURL = song.coverURL {
            Task {
                if let data = try? Data(contentsOf: artworkURL), let image = UIImage(data: data) {
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                }
            }
        }
        syncLiveActivity()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player?.playImmediately(atRate: Float(self?.rate ?? 1.0))
            self?.isPlaying = true
            self?.updateNowPlaying()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            self?.updateNowPlaying()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - 音频混合 / 灵动岛

    /// 与其他 App 音频混合播放（不打断其他音频，默认开启）
    var mixesWithOthers: Bool {
        get { defaults.object(forKey: audioMixKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: audioMixKey)
            sessionConfigured = false
            configureAudioSession()
        }
    }

    /// 灵动岛实时活动开关（默认开启，iOS 16.1+ 生效）
    var liveActivityEnabled: Bool {
        get { defaults.object(forKey: liveActivityKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: liveActivityKey)
            if newValue { syncLiveActivity() } else { endLiveActivity() }
        }
    }

    /// 播放状态变化时同步灵动岛（切歌 / 播放 / 暂停）
    func syncLiveActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard liveActivityEnabled, let song = currentSong else {
            endLiveActivity()
            return
        }
        let state = NowPlayingAttributes.ContentState(
            songName: song.name,
            artist: song.artists,
            coverURL: song.coverURL?.absoluteString,
            isPlaying: isPlaying,
            progress: progress,
            duration: max(duration, song.duration)
        )
        if let activity = liveActivity as? Activity<NowPlayingAttributes> {
            Task {
                await activity.update(using: state)
            }
        } else {
            do {
                let activity = try Activity<NowPlayingAttributes>.request(
                    attributes: NowPlayingAttributes(),
                    contentState: state,
                    pushType: nil
                )
                liveActivity = activity
            } catch {
                BeansLogger.shared.log("灵动岛启动失败：\(error)", level: .error)
            }
        }
    }

    /// 结束灵动岛实时活动
    func endLiveActivity() {
        guard #available(iOS 16.1, *) else { return }
        if let activity = liveActivity as? Activity<NowPlayingAttributes> {
            let state = activity.contentState
            Task {
                await activity.end(using: state, dismissalPolicy: .immediate)
            }
        }
        liveActivity = nil
    }
}
