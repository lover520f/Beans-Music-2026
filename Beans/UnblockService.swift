import Foundation
import CryptoKit

/// 灰色歌曲 / VIP 试听解锁（借鉴 Kumone 的 UnblockService）
/// 按序尝试 pyncmd → 酷我 → 咪咕 → 波点，返回第一个可用的第三方播放地址。
/// 默认开启：由 PlayerManager 在网易云 URL 为空或仅试听片段时自动调用。
enum UnblockService {
    struct Resolved {
        let url: URL
        let source: String

        var sourceTitle: String {
            switch source {
            case "pyncmd": return "pyncmd 音源"
            case "kuwo": return "酷我音源"
            case "migu": return "咪咕音源"
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
    /// - Parameter strict: 严格模式（周杰伦等版权歌手）：要求 歌名+歌手+时长 三重匹配原唱，校验不过直接拒绝，绝不播放翻唱
    static func resolve(name: String, artists: String, durationMS: Int, neteaseID: Int, strict: Bool = false) async -> Resolved? {
        let keyword = ([name, artists].filter { !$0.isEmpty })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }

        // 咪咕直连：官方正版 CDN 直链，仅命中内置清单（歌名+歌手+时长三重校验），严格模式优先使用
        if strict, let r = miguDirect(name: name, artists: artists, durationMS: durationMS) { return r }

        let store = UnblockSourceStore.shared
        // pyncmd 只支持网易云 id；QQ 歌曲（neteaseID = 0）直接跳过
        if neteaseID > 0, store.isEnabled("pyncmd"), let r = await pyncmd(neteaseID: neteaseID) { return r }
        if store.isEnabled("kuwo"), let r = await kuwo(keyword: keyword, durationMS: durationMS, artists: artists, strict: strict, songName: name) { return r }
        if store.isEnabled("bodian"), let r = await bodian(keyword: keyword, durationMS: durationMS, artists: artists, strict: strict, songName: name) { return r }
        // 用户导入的自定义源（按导入顺序；kind == "lx" 走落雪 API 服务器）
        for source in store.customSources {
            if source.kind == "lx" {
                if let r = await lx(source: source, keyword: keyword) { return r }
            } else if let r = await custom(source: source, name: name, artists: artists, neteaseID: neteaseID) { return r }
        }
        return nil
    }

    // MARK: - 音源 0：咪咕直连（周杰伦 3 首官方正版 CDN 直链，借鉴 MiguMusicApi 缓存歌单）
    /// 仅严格模式使用：歌名 + 歌手（周杰伦）+ 时长 ±3s 三重匹配，全部命中才返回官方直链
    private struct MiguDirectSong {
        let title: String
        let duration: Int      // 秒
        let url128: String
        let url320: String
        let flac: String
    }

    private static let miguDirectSongs: [MiguDirectSong] = [
        MiguDirectSong(title: "七里香", duration: 296,
                       url128: "https://freetyst.nf.migu.cn/public/product9th/product41/2020/08/1013/2009年06月26日博尔普斯/标清高清/MP3_128_16_Stero/60054701934133203.mp3",
                       url320: "https://freetyst.nf.migu.cn/public/product9th/product41/2020/08/1013/2009年06月26日博尔普斯/标清高清/MP3_320_16_Stero/60054701934133203.mp3",
                       flac: "https://freetyst.nf.migu.cn/public/ringmaker01/n17/2017/07/无损/2009年06月26日博尔普斯/flac/七里香-周杰伦.flac"),
        MiguDirectSong(title: "四面楚歌", duration: 247,
                       url128: "https://freetyst.nf.migu.cn/public/product5th/product35/2019/10/1018/2009年06月26日博尔普斯/标清高清/MP3_128_16_Stero/60054701951.mp3",
                       url320: "https://freetyst.nf.migu.cn/public/product5th/product35/2019/10/1018/2009年06月26日博尔普斯/标清高清/MP3_320_16_Stero/60054701951.mp3",
                       flac: "https://freetyst.nf.migu.cn/public/ringmaker01/n17/2017/07/无损/2009年06月26日博尔普斯/flac/四面楚歌-周杰伦.flac"),
        MiguDirectSong(title: "晴天", duration: 249,
                       url128: "https://freetyst.nf.migu.cn/public/product9th/product44/2021/07/1112/2019年10月30日16点52分紧急内容准入纵横世代25首/标清高清/MP3_128_16_Stero/60054704101123747.mp3",
                       url320: "https://freetyst.nf.migu.cn/public/product9th/product44/2021/07/1112/2019年10月30日16点52分紧急内容准入纵横世代25首/标清高清/MP3_320_16_Stero/60054704101123747.mp3",
                       flac: "https://freetyst.nf.migu.cn/public/product9th/product44/2021/07/1112/2019年10月30日16点52分紧急内容准入纵横世代25首/歌曲下载/flac/60054704101123747.flac"),
    ]

    /// 咪咕 CDN 直链 URL 含中文路径，先百分号编码再构造 URL（否则 URL(string:) 直接返回 nil）
    private static func miguURL(_ raw: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~:/?#[]@!    // MARK: - 音源 1：pyncmd（直接按网易云 id 取高音质地址）'()*+,;=%"))
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: encoded)
    }

    private static func miguDirect(name: String, artists: String, durationMS: Int) -> Resolved? {
        guard artistMatches("周杰伦", artists) else { return nil }
        let target = Double(durationMS) / 1000.0
        for song in miguDirectSongs where songNameMatches(name, song.title) {
            guard abs(Double(song.duration) - target) <= 3 else { continue }
            let raw: String
            switch BeansAudioQuality.current {
            case .lossless, .hires: raw = song.flac
            case .exhigh, .higher: raw = song.url320
            case .standard: raw = song.url128
            }
            guard let playURL = miguURL(raw) else { continue }
            return Resolved(url: playURL, source: "migu")
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
    /// strict：歌名+歌手+时长三重匹配原唱，不满足直接拒绝（无回退）
    private static func kuwoSearchID(keyword: String, durationMS: Int, artists: String = "", strict: Bool = false, songName: String = "") async -> String? {
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
            if strict {
                // 严格模式：歌名 + 歌手 同时匹配才算原唱
                let songTitle = song["SONGNAME"] as? String ?? song["songname"] as? String ?? ""
                if songNameMatches(songName, songTitle) && artistMatches(artists, singer) { return rid }
                continue
            }
            if artistMatches(artists, singer) { return rid }
            if fallback == nil { fallback = rid }
        }
        return fallback
    }

    private static func kuwo(keyword: String, durationMS: Int, artists: String = "", strict: Bool = false, songName: String = "") async -> Resolved? {
        guard let rid = await kuwoSearchID(keyword: keyword, durationMS: durationMS, artists: artists, strict: strict, songName: songName) else { return nil }
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

    // MARK: - 音源 3：波点（借鉴 splayer-unlock-plugin：酷我搜索 + 波点签名取流）

    /// 随机设备号（对应插件 generateDeviceId，0 ~ 100000000000）
    private static let bodianDeviceID: String = String(Int.random(in: 0...100_000_000_000))

    private static func bodian(keyword: String, durationMS: Int, artists: String = "", strict: Bool = false, songName: String = "") async -> Resolved? {
        guard let songID = await kuwoSearchID(keyword: keyword, durationMS: durationMS, artists: artists, strict: strict, songName: songName) else { return nil }
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

    // MARK: - 落雪音乐源（lx-music-api-server 风格 HTTP API）
    /// 兼容落雪 API 服务器（如 lx-music-api-server）：先按关键词搜索拿到歌曲 id，
    /// 再请求播放地址。headers 里可配置 source（wy/kg/qq/mg/tx，默认 kg）与 br（默认 320）。
    private static func lx(source: ThirdPartySource, keyword: String) async -> Resolved? {
        guard source.kind == "lx", !source.template.isEmpty else { return nil }
        let base = source.template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base) else { return nil }
        let lxSource = source.headers["source"] ?? "kg"
        let br = source.headers["br"] ?? "320"
        // 1) 搜索：GET /music/search?source=&query=&page=1&limit=5
        var searchComps = URLComponents(url: baseURL.appendingPathComponent("music/search"), resolvingAgainstBaseURL: false)
        searchComps?.queryItems = [
            URLQueryItem(name: "source", value: lxSource),
            URLQueryItem(name: "query", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let searchURL = searchComps?.url, let data = await get(searchURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let list = dataObj["list"] as? [[String: Any]],
              let first = list.first,
              let id = first["id"] as? String ?? (first["id"] as? Int).map(String.init)
        else { return nil }
        // 2) 取播放地址：GET /music/url?source=&id=&br=
        var urlComps = URLComponents(url: baseURL.appendingPathComponent("music/url"), resolvingAgainstBaseURL: false)
        urlComps?.queryItems = [
            URLQueryItem(name: "source", value: lxSource),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "br", value: br)
        ]
        guard let urlURL = urlComps?.url, let data2 = await get(urlURL),
              let obj2 = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
              let d2 = obj2["data"] as? [String: Any],
              let urlStr = d2["url"] as? String, !urlStr.isEmpty,
              let playURL = URL(string: urlStr)
        else { return nil }
        return Resolved(url: playURL, source: "落雪 (\(lxSource))")
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

    /// 歌名匹配：忽略大小写、空格、括号内容（翻唱/Live 后缀等）；任一包含对方即视为匹配
    private static func songNameMatches(_ target: String, _ candidate: String) -> Bool {
        let norm: (String) -> String = { s in
            var t = s.lowercased()
            // 去掉英文括号内容（如 (Live)、(cover)）
            while let a = t.firstIndex(of: "("), let b = t.firstIndex(of: ")"), a < b {
                t.removeSubrange(a...b)
            }
            // 去掉中文括号内容
            while let a = t.firstIndex(of: "（"), let b = t.firstIndex(of: "）"), a < b {
                t.removeSubrange(a...b)
            }
            t = t.replacingOccurrences(of: " ", with: "")
            t = t.replacingOccurrences(of: "-", with: "")
            t = t.replacingOccurrences(of: "·", with: "")
            return t
        }
        let tn = norm(target)
        let cn = norm(candidate)
        guard !tn.isEmpty else { return true }
        guard !cn.isEmpty else { return false }
        return cn.contains(tn) || tn.contains(cn)
    }

    /// 歌手模糊匹配：忽略大小写、空格与分隔符；任一目标歌手命中即可
    /// 歌手中英文别名（第三方平台常返回英文名，如 周杰伦 → Jay Chou / 邓紫棋 → G.E.M.）
    private static func artistAliases(_ name: String) -> [String] {
        switch name {
        case "周杰伦": return ["周杰伦", "jay chou", "jaychou"]
        case "林俊杰": return ["林俊杰", "jj lin", "lin junjie"]
        case "陈奕迅": return ["陈奕迅", "eason chan", "chen yixun"]
        case "邓紫棋": return ["邓紫棋", "g.e.m", "gem", "g.e.m."]
        case "许嵩": return ["许嵩", "vae"]
        case "薛之谦": return ["薛之谦", "joker xue"]
        case "王力宏": return ["王力宏", "lee hom"]
        case "李荣浩": return ["李荣浩", "ronghao li"]
        case "五月天": return ["五月天", "mayday"]
        case "孙燕姿": return ["孙燕姿", "sun yanzi", "stefanie sun"]
        case "张杰": return ["张杰", "jason zhang"]
        case "华晨宇": return ["华晨宇", "hua chenyu"]
        case "陶喆": return ["陶喆", "david tao"]
        case "蔡依林": return ["蔡依林", "jolin"]
        default: return [name]
        }
    }

    /// 歌手模糊匹配：忽略大小写、空格与分隔符；支持中英文别名；任一目标歌手命中即可
    private static func artistMatches(_ target: String, _ candidate: String) -> Bool {
        let norm: (String) -> String = { s in
            s.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "·", with: "")
                .replacingOccurrences(of: "&", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
        }
        let tn = norm(target)
        let cn = norm(candidate)
        guard !tn.isEmpty else { return true }
        guard !cn.isEmpty else { return false }
        if cn.contains(tn) || tn.contains(cn) { return true }
        // 中英文别名（周杰伦 → Jay Chou）
        for alias in artistAliases(target).map(norm) where !alias.isEmpty {
            if cn.contains(alias) { return true }
        }
        for alias in artistAliases(candidate).map(norm) where !alias.isEmpty {
            if tn.contains(alias) { return true }
        }
        // 多歌手（A / B、A·B、A、B）：任一命中即视为匹配
        let separators = CharacterSet(charactersIn: "/·&,、")
        for part in tn.components(separatedBy: separators) where !part.isEmpty {
            if cn.contains(part) { return true }
        }
        for part in cn.components(separatedBy: separators) where !part.isEmpty {
            if tn.contains(part) { return true }
        }
        return false
    }

    /// 兼容酷我「mm:ss」与秒数两种时长格式
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
