import Foundation
import CryptoKit

/// 灰色歌曲 / VIP 试听解锁（借鉴 Kumone 的 UnblockService）
/// 按序尝试 pyncmd → 酷我 → 酷狗，返回第一个可用的第三方播放地址。
/// 默认开启：由 PlayerManager 在网易云 URL 为空或仅试听片段时自动调用。
enum UnblockService {
    struct Resolved {
        let url: URL
        let source: String

        var sourceTitle: String {
            switch source {
            case "pyncmd": return "pyncmd 音源"
            case "kuwo": return "酷我音源"
            case "kugou": return "酷狗音源"
            default: return source
            }
        }
    }


    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 统一的 GET 请求（带移动端 UA，提升第三方接口可用性）
    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: request),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }

    /// 入口：返回第一个可用的第三方播放地址；全部失败返回 nil
    static func resolve(name: String, artists: String, durationMS: Int, neteaseID: Int) async -> Resolved? {
        let keyword = ([name, artists].filter { !$0.isEmpty })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }

        // pyncmd 只支持网易云 id；QQ 歌曲（neteaseID = 0）直接跳过
        if neteaseID > 0, let r = await pyncmd(neteaseID: neteaseID) { return r }
        if let r = await kuwo(keyword: keyword, durationMS: durationMS) { return r }
        if let r = await kugou(keyword: keyword, durationMS: durationMS) { return r }
        return nil
    }

    // MARK: - 音源 1：pyncmd（直接按网易云 id 取高音质地址）

    private static func pyncmd(neteaseID: Int) async -> Resolved? {
        var comps = URLComponents(string: "https://music-api.gdstudio.xyz/api.php")!
        comps.queryItems = [
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "id", value: String(neteaseID)),
            URLQueryItem(name: "br", value: "320"),
        ]
        guard let url = comps.url,
              let data = await get(url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var urlString = obj["url"] as? String, !urlString.isEmpty else { return nil }
        // 接口偶发返回明文 http，统一升级为 https 提高可用性
        if urlString.hasPrefix("http://") {
            urlString = "https://" + String(urlString.dropFirst("http://".count))
        }
        guard let playURL = URL(string: urlString) else { return nil }
        return Resolved(url: playURL, source: "pyncmd")
    }

    // MARK: - 音源 2：酷我（搜索 + 时长匹配 + 直链转换）

    private static func kuwo(keyword: String, durationMS: Int) async -> Resolved? {
        let target = Double(durationMS) / 1000.0
        var comps = URLComponents(string: "http://search.kuwo.cn/r.s")!
        comps.queryItems = [
            URLQueryItem(name: "correct", value: "1"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "stype", value: "comprehensive"),
            URLQueryItem(name: "encoding", value: "utf8"),
            URLQueryItem(name: "rformat", value: "json"),
            URLQueryItem(name: "mobi", value: "1"),
            URLQueryItem(name: "show_copyright_off", value: "1"),
            URLQueryItem(name: "searchapi", value: "6"),
            URLQueryItem(name: "all", value: keyword),
        ]
        guard let url = comps.url,
              let data = await get(url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [Any], content.indices.contains(1),
              let section = content[1] as? [String: Any],
              let musicpage = section["musicpage"] as? [String: Any],
              let list = musicpage["abslist"] as? [[String: Any]] else { return nil }

        for song in list.prefix(5) {
            // 酷我字段为大写（MUSICRID 已含 MUSIC_ 前缀），兼容小写
            var rid = song["rid"] as? String ?? song["MUSICRID"] as? String ?? ""
            if rid.isEmpty { rid = song["DC_TARGETID"] as? String ?? "" }
            guard !rid.isEmpty else { continue }
            if !rid.hasPrefix("MUSIC_") { rid = "MUSIC_\(rid)" }
            // 时长匹配 ±5 秒（酷我返回秒数或 mm:ss，缺省时放宽）
            if let dur = duration(of: song["duration"] ?? song["DURATION"]), abs(dur - target) > 5 { continue }
            guard let urlString = await kuwoConvertURL(rid: rid),
                  let playURL = URL(string: urlString) else { continue }
            return Resolved(url: playURL, source: "kuwo")
        }
        return nil
    }

    private static func kuwoConvertURL(rid: String) async -> String? {
        var comps = URLComponents(string: "http://antiserver.kuwo.cn/anti.s")!
        let ridParam = rid.hasPrefix("MUSIC_") ? rid : "MUSIC_\(rid)"
        comps.queryItems = [
            URLQueryItem(name: "type", value: "convert_url"),
            URLQueryItem(name: "format", value: "mp3"),
            URLQueryItem(name: "response", value: "url"),
            URLQueryItem(name: "rid", value: ridParam),
        ]
        guard let url = comps.url,
              let data = await get(url),
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("http") else { return nil }
        return text
    }

    // MARK: - 音源 3：酷狗（搜索 + 时长匹配 + 播放直链）

    private static func kugou(keyword: String, durationMS: Int) async -> Resolved? {
        let target = Double(durationMS) / 1000.0
        var comps = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/song")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "10"),
        ]
        guard let url = comps.url,
              let data = await get(url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let list = dataObj["info"] as? [[String: Any]] else { return nil }

        for song in list.prefix(5) {
            guard let hash = song["hash"] as? String, !hash.isEmpty else { continue }
            if let dur = duration(of: song["duration"]), abs(dur - target) > 5 { continue }
            let albumID: String
            if let s = song["album_id"] as? String { albumID = s }
            else if let i = song["album_id"] as? Int { albumID = String(i) }
            else { albumID = "" }

            let key = md5Hex("\(hash)kgcloudv2")
            var t = URLComponents(string: "http://trackercdn.kugou.com/i/v2/")!
            t.queryItems = [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "hash", value: hash),
                URLQueryItem(name: "appid", value: "1005"),
                URLQueryItem(name: "pid", value: "2"),
                URLQueryItem(name: "cmd", value: "25"),
                URLQueryItem(name: "behavior", value: "play"),
                URLQueryItem(name: "album_id", value: albumID),
            ]
            guard let trackURL = t.url,
                  let td = await get(trackURL),
                  let to = try? JSONSerialization.jsonObject(with: td) as? [String: Any],
                  let urls = to["url"] as? [Any],
                  let first = urls.first as? String,
                  let playURL = URL(string: first) else { continue }
            return Resolved(url: playURL, source: "kugou")
        }
        return nil
    }

    // MARK: - 工具

    /// 兼容酷我「mm:ss」与酷狗「秒数」两种时长格式
    private static func duration(of value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String {
            if let d = Double(s) { return d }
            let parts = s.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        return nil
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
