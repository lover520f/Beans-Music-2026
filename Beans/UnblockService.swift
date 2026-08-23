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

    /// 入口：按 内置源开关顺序 + 用户导入的自定义源 依次尝试，返回第一个可用地址
    static func resolve(name: String, artists: String, durationMS: Int, neteaseID: Int) async -> Resolved? {
        let keyword = ([name, artists].filter { !$0.isEmpty })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }

        let store = UnblockSourceStore.shared
        // pyncmd 只支持网易云 id；QQ 歌曲（neteaseID = 0）直接跳过
        if neteaseID > 0, store.isEnabled("pyncmd"), let r = await pyncmd(neteaseID: neteaseID) { return r }
        if store.isEnabled("kuwo"), let r = await kuwo(keyword: keyword, durationMS: durationMS, artists: artists) { return r }
        if store.isEnabled("kugou"), let r = await kugou(keyword: keyword, durationMS: durationMS, artists: artists) { return r }
        if store.isEnabled("bodian"), let r = await bodian(keyword: keyword, durationMS: durationMS, artists: artists) { return r }
        // 用户导入的自定义源（按导入顺序）
        for source in store.customSources {
            if let r = await custom(source: source, name: name, artists: artists, neteaseID: neteaseID) { return r }
        }
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

    /// 酷我搜索：按 歌名+歌手 匹配，返回 rid（不含 MUSIC_ 前缀）
    /// 歌手字段优先校验，避免第三方音源匹配到翻唱（歌名对但人声不对）；无歌手匹配时回退第一条时长匹配项
    private static func kuwoSearchID(keyword: String, durationMS: Int, artists: String = "") async -> String? {
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

        var fallback: String?
        for song in list.prefix(10) {
            // 酷我字段为大写（MUSICRID 已含 MUSIC_ 前缀），兼容小写
            var rid = song["rid"] as? String ?? song["MUSICRID"] as? String ?? ""
            if rid.isEmpty { rid = song["DC_TARGETID"] as? String ?? "" }
            guard !rid.isEmpty else { continue }
            if rid.hasPrefix("MUSIC_") { rid = String(rid.dropFirst("MUSIC_".count)) }
            // 时长匹配 ±5 秒（酷我返回秒数或 mm:ss，缺省时放宽）
            if let dur = duration(of: song["duration"] ?? song["DURATION"]), abs(dur - target) > 5 { continue }
            // 歌手校验：优先原唱（酷我字段大写 ARTIST，兼容小写）
            let singer = song["ARTIST"] as? String ?? song["artist"] as? String ?? ""
            if artistMatches(artists, singer) { return rid }
            if fallback == nil { fallback = rid }
        }
        return fallback
    }

    private static func kuwo(keyword: String, durationMS: Int, artists: String = "") async -> Resolved? {
        guard let rid = await kuwoSearchID(keyword: keyword, durationMS: durationMS, artists: artists) else { return nil }
        // Try 1：antiserver 直链（无需加密，稳定取整曲 MP3）
        if let urlString = await kuwoConvertURL(rid: rid), let playURL = URL(string: urlString) {
            return Resolved(url: playURL, source: "kuwo")
        }
        // Try 2：www.kuwo.cn/url 网页接口（支持码率，借鉴 splayer 解锁插件）
        var comps = URLComponents(string: "http://www.kuwo.cn/url")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "mp3"),
            URLQueryItem(name: "response", value: "url"),
            URLQueryItem(name: "type", value: "convert_url3"),
            URLQueryItem(name: "br", value: "320kmp3"),
            URLQueryItem(name: "rid", value: rid),
        ]
        if let url = comps.url {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("http://www.kuwo.cn/", forHTTPHeaderField: "Referer")
            if let (data, resp) = try? await session.data(for: request),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               text.hasPrefix("http"),
               let playURL = URL(string: text) {
                return Resolved(url: playURL, source: "kuwo")
            }
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

    private static func kugou(keyword: String, durationMS: Int, artists: String = "") async -> Resolved? {
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

        var fallbackHash: String?
        var fallbackAlbumID: String?
        for song in list.prefix(10) {
            guard let hash = song["hash"] as? String, !hash.isEmpty else { continue }
            if let dur = duration(of: song["duration"]), abs(dur - target) > 5 { continue }
            let albumID: String
            if let s = song["album_id"] as? String { albumID = s }
            else if let i = song["album_id"] as? Int { albumID = String(i) }
            else { albumID = "" }

            // 歌手校验：优先原唱（酷狗 singername），避免翻唱误匹配
            let singer = song["singername"] as? String ?? ""
            if fallbackHash == nil { fallbackHash = hash; fallbackAlbumID = albumID }
            if !artistMatches(artists, singer) { continue }

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
        // 无歌手匹配时回退第一个时长匹配项，保证可播放
        if let hash = fallbackHash {
            let key = md5Hex("\(hash)kgcloudv2")
            var ft = URLComponents(string: "http://trackercdn.kugou.com/i/v2/")!
            ft.queryItems = [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "hash", value: hash),
                URLQueryItem(name: "appid", value: "1005"),
                URLQueryItem(name: "pid", value: "2"),
                URLQueryItem(name: "cmd", value: "25"),
                URLQueryItem(name: "behavior", value: "play"),
                URLQueryItem(name: "album_id", value: fallbackAlbumID ?? ""),
            ]
            if let trackURL = ft.url,
               let td = await get(trackURL),
               let to = try? JSONSerialization.jsonObject(with: td) as? [String: Any],
               let urls = to["url"] as? [Any],
               let first = urls.first as? String,
               let playURL = URL(string: first) {
                return Resolved(url: playURL, source: "kugou")
            }
        }
        return nil
    }

    // MARK: - 音源 4：波点（借鉴 splayer-unlock-plugin：酷我搜索 + 波点签名取流）

    /// 随机设备号（对应插件 generateDeviceId，0 ~ 100000000000）
    private static let bodianDeviceID: String = String(Int.random(in: 0...100_000_000_000))

    private static func bodian(keyword: String, durationMS: Int, artists: String = "") async -> Resolved? {
        guard let songID = await kuwoSearchID(keyword: keyword, durationMS: durationMS, artists: artists) else { return nil }
        let path = "/api/play/music/v2/audioUrl"
        for br in ["320kmp3", "192kmp3", "128kmp3"] {
            var str = "http://bd-api.kuwo.cn\(path)?br=\(br)&musicId=\(songID)"
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            str += "&timestamp=\(timestamp)"
            // 签名：kuwotest + (查询串去掉非字母数字排序后拼接) + path，整体 MD5
            let qIndex = str.firstIndex(of: "?")!
            let queryPart = str[str.index(after: qIndex)...]
            let filtered = queryPart.filter { $0.isLetter || $0.isNumber }.sorted().map(String.init).joined()
            let sign = md5Hex("kuwotest\(filtered)\(path)")
            guard let url = URL(string: "\(str)&sign=\(sign)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Dart/2.19 (dart:io)", forHTTPHeaderField: "User-Agent")
            request.setValue("ar", forHTTPHeaderField: "plat")
            request.setValue("aliopen", forHTTPHeaderField: "channel")
            request.setValue(bodianDeviceID, forHTTPHeaderField: "devid")
            request.setValue("3.9.0", forHTTPHeaderField: "ver")
            request.setValue("bd-api.kuwo.cn", forHTTPHeaderField: "host")
            request.setValue("1.0.1.114", forHTTPHeaderField: "X-Forwarded-For")
            guard let (data, resp) = try? await session.data(for: request),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = obj["data"] as? [String: Any],
                  let urlString = dataObj["audioUrl"] as? String,
                  let playURL = URL(string: urlString) else { continue }
            return Resolved(url: playURL, source: "bodian")
        }
        return nil
    }

    // MARK: - 自定义源（用户导入的第三方解锁源）

    private static func custom(source: ThirdPartySource, name: String, artists: String, neteaseID: Int) async -> Resolved? {
        guard !source.template.isEmpty else { return nil }
        var urlString = source.template
        urlString = urlString.replacingOccurrences(of: "{id}", with: String(neteaseID))
        urlString = urlString.replacingOccurrences(of: "{name}", with: urlEncoded(name))
        let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        urlString = urlString.replacingOccurrences(of: "{keyword}", with: urlEncoded(keyword))
        urlString = urlString.replacingOccurrences(of: "{artist}", with: urlEncoded(artists))
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        for (key, value) in source.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard let (data, resp) = try? await session.data(for: request),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = valueAtPath(obj, source.urlPath),
              let urlString = value as? String, !urlString.isEmpty,
              let playURL = URL(string: urlString) else { return nil }
        return Resolved(url: playURL, source: source.name)
    }

    /// 点分路径取值：url / data.url / data.audioUrl ...
    private static func valueAtPath(_ obj: Any, _ path: String) -> Any? {
        var current: Any = obj
        for key in path.split(separator: ".") {
            guard let dict = current as? [String: Any], let next = dict[String(key)] else { return nil }
            current = next
        }
        return current
    }

    private static func urlEncoded(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

    // MARK: - 工具

    /// 歌手模糊匹配：忽略大小写、空格与分隔符；任一目标歌手命中即可
    private static func artistMatches(_ target: String, _ candidate: String) -> Bool {
        let norm: (String) -> String = { s in
            s.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "·", with: "")
                .replacingOccurrences(of: "&", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
        }
        let t = norm(target)
        let c = norm(candidate)
        guard !t.isEmpty else { return true }
        guard !c.isEmpty else { return false }
        if c.contains(t) || t.contains(c) { return true }
        // 多歌手（A / B、A·B、A、B）：任一命中即视为匹配
        let separators = CharacterSet(charactersIn: "/·&,、")
        for part in t.components(separatedBy: separators) where !part.isEmpty {
            if c.contains(part) { return true }
        }
        for part in c.components(separatedBy: separators) where !part.isEmpty {
            if t.contains(part) { return true }
        }
        return false
    }

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
