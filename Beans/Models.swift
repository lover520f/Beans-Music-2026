import Foundation

/// 歌曲来源（网易云 / QQ音乐）
enum SongSource: String, Codable {
    case netease
    case qq
}

struct Song: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let artists: String
    let album: String
    let coverURL: URL?
    let duration: TimeInterval
    /// 歌曲来源（网易云 / QQ音乐）
    let source: SongSource
    /// QQ 音乐 songmid（source == .qq 时用于获取播放地址与歌词）
    let qqMid: String?
    /// 付费/VIP 标记（网易云：0 免费、1 VIP、4 付费单曲；QQ 音乐：0 免费、非 0 付费）
    let fee: Int

    var formattedDuration: String {
        let total = max(0, Int(duration))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 跨平台唯一标识（避免网易云与 QQ 音乐歌曲 id 撞车）
    var identityKey: String {
        source == .qq ? "qq-\(id)" : "netease-\(id)"
    }

    /// 是否为 VIP / 付费歌曲（用于列表与播放器角标）
    var isVIP: Bool {
        fee != 0
    }

    init(id: Int, name: String, artists: String, album: String, coverURL: URL?, duration: TimeInterval, source: SongSource = .netease, qqMid: String? = nil, fee: Int = 0) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.coverURL = coverURL
        self.duration = duration
        self.source = source
        self.qqMid = qqMid
        self.fee = fee
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        let artistsArray = json["artists"] as? [[String: Any]] ?? (json["ar"] as? [[String: Any]]) ?? []
        artists = artistsArray.compactMap { $0["name"] as? String }.joined(separator: " / ")
        if let albumDict = json["album"] as? [String: Any] {
            album = albumDict["name"] as? String ?? ""
            let pic = albumDict["picUrl"] as? String ?? (albumDict["blurPicUrl"] as? String ?? "")
            coverURL = pic.isEmpty ? nil : URL(string: pic)
        } else if let al = json["al"] as? [String: Any] {
            album = al["name"] as? String ?? ""
            let pic = al["picUrl"] as? String ?? ""
            coverURL = pic.isEmpty ? nil : URL(string: pic)
        } else {
            album = ""
            coverURL = nil
        }
        let ms = json["duration"] as? Int ?? (json["dt"] as? Int) ?? 0
        duration = Double(ms) / 1000.0
        source = .netease
        qqMid = nil
        fee = json["fee"] as? Int ?? 0
    }

    private enum CodingKeys: String, CodingKey { case id, name, artists, album, coverURL, duration, source, qqMid, fee }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        artists = try c.decodeIfPresent(String.self, forKey: .artists) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        coverURL = try c.decodeIfPresent(URL.self, forKey: .coverURL)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        source = try c.decodeIfPresent(SongSource.self, forKey: .source) ?? .netease
        qqMid = try c.decodeIfPresent(String.self, forKey: .qqMid)
        fee = try c.decodeIfPresent(Int.self, forKey: .fee) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(artists, forKey: .artists)
        try c.encode(album, forKey: .album)
        try c.encodeIfPresent(coverURL, forKey: .coverURL)
        try c.encode(duration, forKey: .duration)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(qqMid, forKey: .qqMid)
        try c.encode(fee, forKey: .fee)
    }
}

/// 歌手搜索结果（网易云 / QQ音乐通用）
struct Artist: Identifiable, Hashable {
    let id: String
    let name: String
    let coverURL: URL?
    let source: SongSource
}

/// 专辑搜索结果（网易云 / QQ音乐通用）
struct Album: Identifiable, Hashable {
    let id: String
    let name: String
    let artistName: String
    let coverURL: URL?
    let source: SongSource
    var trackCount: Int?
}

struct Playlist: Identifiable, Hashable {
    let id: Int
    let name: String
    let coverURL: URL?
    let trackCount: Int
    let creatorName: String

    init(id: Int, name: String, coverURL: URL?, trackCount: Int = 0) {
        self.id = id
        self.name = name
        self.coverURL = coverURL
        self.trackCount = trackCount
        self.creatorName = ""
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        trackCount = json["trackCount"] as? Int ?? 0
        let pic = json["coverImgUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        creatorName = (json["creator"] as? [String: Any])?["nickname"] as? String ?? ""
    }

    init?(personalizedJSON json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        trackCount = 0
        let pic = json["picUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        creatorName = ""
    }
}

struct TopList: Identifiable, Hashable {
    let id: Int
    let name: String
    let coverURL: URL?
    let updateFrequency: String

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        let pic = json["coverImgUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        updateFrequency = json["updateFrequency"] as? String ?? ""
    }
}

/// QQ 峰尖榜总览项
struct QQTopInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let subTitle: String
    let topSongNames: [String]
    let coverURL: URL?
}

struct LyricLine: Identifiable, Hashable {
    let id: UUID
    let time: Double
    let text: String

    init(time: Double, text: String) {
        self.id = UUID()
        self.time = time
        self.text = text
    }
}

enum LyricParser {
    static func parse(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for line in raw.components(separatedBy: .newlines) {
            parseTimes(in: line).forEach { time in
                let text = line.replacingOccurrences(of: #"\[\d{2}:\d{2}(\.\d{1,3})?\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func parseTimes(in line: String) -> [Double] {
        var times: [Double] = []
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex..., in: line)
        regex?.enumerateMatches(in: line, options: [], range: range) { match, _, _ in
            guard let match else { return }
            guard let minuteRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line) else { return }
            let minutes = Double(line[minuteRange]) ?? 0
            let seconds = Double(line[secondRange]) ?? 0
            var fraction = 0.0
            if match.numberOfRanges > 3, let fracRange = Range(match.range(at: 3), in: line) {
                let raw = String(line[fracRange])
                fraction = (Double(raw) ?? 0) / pow(10, Double(max(raw.count, 1)))
            }
            times.append(minutes * 60 + seconds + fraction)
        }
        return times
    }
}

struct NetEaseUser: Identifiable, Hashable, Codable {
    let uid: Int
    let nickname: String
    let avatarURL: URL?

    var id: Int { uid }

    init?(json: [String: Any]) {
        guard let id = json["userId"] as? Int ?? (json["id"] as? Int) else { return nil }
        uid = id
        nickname = json["nickname"] as? String ?? ""
        let pic = json["avatarUrl"] as? String ?? ""
        avatarURL = pic.isEmpty ? nil : URL(string: pic)
    }
}
/// 听歌排行条目（网易云听歌记录）
struct PlayRecordItem: Identifiable, Hashable {
    let song: Song
    let playCount: Int
    var id: Int { song.id }
}

/// 听歌排行结果（列表 + 真实总数，避免被接口单次上限截断）
struct PlayRecordResult {
    let items: [PlayRecordItem]
    let totalCount: Int
}

// MARK: - 歌曲评论

struct SongComment: Identifiable, Hashable {
    let id: Int
    let content: String
    let nickname: String
    let avatarURL: URL?
    let time: Date
    let likedCount: Int
    let isHot: Bool

    init(id: Int, content: String, nickname: String, avatarURL: URL?, time: Date, likedCount: Int, isHot: Bool = false) {
        self.id = id
        self.content = content
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.time = time
        self.likedCount = likedCount
        self.isHot = isHot
    }

    init?(json: [String: Any], isHot: Bool = false) {
        guard let id = json["commentId"] as? Int else { return nil }
        self.id = id
        content = json["content"] as? String ?? ""
        let user = json["user"] as? [String: Any]
        nickname = user?["nickname"] as? String ?? ""
        let avatar = user?["avatarUrl"] as? String ?? ""
        avatarURL = avatar.isEmpty ? nil : URL(string: avatar)
        let ms = json["time"] as? Int ?? 0
        time = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        likedCount = json["likedCount"] as? Int ?? 0
        self.isHot = isHot
    }
}