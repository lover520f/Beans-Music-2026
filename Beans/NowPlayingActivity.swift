import Foundation
import ActivityKit

/// 正在播放的灵动岛 / 实时活动共享数据（App 与 Widget Extension 共用）
@available(iOS 16.1, *)
struct NowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var songName: String
        var artist: String
        var coverURL: String?
        var isPlaying: Bool
        var progress: Double
        var duration: Double
    }

    var title: String = "正在播放"
}
