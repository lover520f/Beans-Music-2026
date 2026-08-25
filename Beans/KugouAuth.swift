import Foundation
import CryptoKit

/// 酷狗音乐账号（网页登录 / Cookie 导入）＋ 歌单同步
/// 逆向结论参考 Mineradio（github.com/XxHuberrr/Mineradio）与酷狗网页版登录态：
/// - 登录态来自酷狗网页版 Cookie（KuGoo 复合字段 / kg_mid / kg_dfid / userid / token）
/// - 歌单走 gateway.kugou.com H5 网关（x-router: cloudlist.service.kugou.com），H5 签名：
///   signature = md5(salt + 排序后 k=v 参数拼接 + 可选 body JSON + salt)，salt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"
final class KugouAuth: ObservableObject {
    static let shared = KugouAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""
    @Published private(set) var avatarURL: URL?
    /// 会员标识：nil 无 / "VIP" / "SVIP"（尽力从 Cookie 判断，失败不阻塞）
    @Published private(set) var vipBadge: String?

    private var cookies: [String: String] = [:]
    private let defaults = UserDefaults.standard
    private let cookieKey = "beans.kugou.cookie.v1"
    private let nickKey = "beans.kugou.nickname.v1"
    private let vipKey = "beans.kugou.vip.v1"
    private let session: URLSession

    /// 播放链路需要的凭证（歌单 / 播放地址接口）
    /// 网页登录的 Cookie 常把 KugooID / token 存在 KuGoo 复合字段里，这里统一解析兜底
    var userid: String {
        var raw = cookieValue("userid")
        if raw.isEmpty { raw = cookieValue("UserId") }
        if raw.isEmpty { raw = cookieValue("KugooID") }
        if raw.isEmpty { raw = cookieValue("kugouID") }
        if raw.isEmpty { raw = cookieValue("uid") }
        if raw.isEmpty {
            for key in ["KuGoo", "kugou", "Kugou"] {
                let compound = Self.parseKuGoo(cookieValue(key))
                if let v = compound["KugooID"] ?? compound["kugouID"] ?? compound["userid"] ?? compound["uid"], !v.isEmpty {
                    raw = v
                    break
                }
            }
        }
        return raw.replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
    }
    var token: String {
        var raw = cookieValue("token")
        if raw.isEmpty { raw = cookieValue("Token") }
        if raw.isEmpty { raw = cookieValue("t") }
        if raw.isEmpty { raw = cookieValue("T") }
        if raw.isEmpty {
            for key in ["KuGoo", "kugou", "Kugou"] {
                let compound = Self.parseKuGoo(cookieValue(key))
                if let v = compound["t"] ?? compound["token"] ?? compound["Token"], !v.isEmpty {
                    raw = v
                    break
                }
            }
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var mid: String {
        var value = cookieValue("kg_mid")
        if value.isEmpty { value = cookieValue("KG_MID") }
        if value.isEmpty { value = cookieValue("KUGOU_API_MID") }
        if value.isEmpty { value = cookieValue("mid") }
        return value.isEmpty ? Self.createMid() : value
    }
    var dfid: String {
        var value = cookieValue("kg_dfid")
        if value.isEmpty { value = cookieValue("KG_DFID") }
        if value.isEmpty { value = cookieValue("dfid") }
        if value.isEmpty { value = cookieValue("DFID") }
        return value.isEmpty ? "-" : value
    }

    /// 登录态是否可用于播放链路（userid + token 齐备）
    var playbackReady: Bool {
        let uid = userid.replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
        return !uid.isEmpty && uid != "0" && !token.isEmpty
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        if let saved = defaults.dictionary(forKey: cookieKey) as? [String: String], !saved.isEmpty {
            cookies = saved
            isLoggedIn = Self.hasValidLogin(saved)
            nickname = defaults.string(forKey: nickKey) ?? Self.fallbackNickname(saved)
            avatarURL = Self.avatarFrom(saved)
            vipBadge = defaults.string(forKey: vipKey) ?? Self.vipFrom(saved)
        }
    }

    // MARK: - 登录状态

    private func cookieValue(_ key: String) -> String {
        cookies[key] ?? ""
    }

    func logout() {
        cookies = [:]
        isLoggedIn = false
        nickname = ""
        avatarURL = nil
        vipBadge = nil
        defaults.removeObject(forKey: cookieKey)
        defaults.removeObject(forKey: nickKey)
        defaults.removeObject(forKey: vipKey)
    }

    // MARK: - 登录

    /// 导入酷狗网页登录 Cookie（网页登录自动读取 / 手动粘贴）
    func importCookies(_ dict: [String: String]) {
        guard !dict.isEmpty else { return }
        cookies = dict
        isLoggedIn = Self.hasValidLogin(dict)
        nickname = Self.fallbackNickname(dict)
        avatarURL = Self.avatarFrom(dict)
        vipBadge = Self.vipFrom(dict)
        defaults.set(cookies, forKey: cookieKey)
        defaults.set(nickname, forKey: nickKey)
        if let badge = vipBadge {
            defaults.set(badge, forKey: vipKey)
        } else {
            defaults.removeObject(forKey: vipKey)
        }
    }

    /// Cookie 是否包含有效登录态（KuGoo 复合字段或 userid+token）
    static func hasValidLogin(_ dict: [String: String]) -> Bool {
        let userid = (dict["userid"] ?? "").replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
        let token = dict["token"] ?? ""
        if !userid.isEmpty, userid != "0", !token.isEmpty { return true }
        for key in ["KuGoo", "kugou", "Kugou"] {
            if let raw = dict[key], !raw.isEmpty {
                let compound = parseKuGoo(raw)
                let uid = (compound["KugooID"] ?? compound["kugouID"] ?? compound["userid"] ?? "")
                    .replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
                if !uid.isEmpty { return true }
            }
        }
        return false
    }

    /// 网页登录关注的 Cookie 名（WKWebView 读取时按此过滤）
    static let webCookieNames: Set<String> = [
        "KuGoo", "kugou", "Kugou", "kg_mid", "KG_MID", "KUGOU_API_MID", "kg_dfid", "KG_DFID",
        "userid", "UserId", "token", "Token", "dfid", "DFID", "KugooID", "uid",
        "nickname", "NickName", "unick", "username", "UserName",
    ]

    /// 解析浏览器复制出来的完整 Cookie 字符串："a=b; c=d"
    static func parseCookieHeader(_ header: String) -> [String: String] {
        var dict: [String: String] = [:]
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                dict[key] = value
            }
        }
        return dict
    }

    /// 从 Cookie 推断昵称：优先 KuGoo 复合字段中的 NickName
    static func fallbackNickname(_ dict: [String: String]) -> String {
        for key in ["KuGoo", "kugou", "Kugou"] {
            if let raw = dict[key], !raw.isEmpty {
                let compound = parseKuGoo(raw)
                let name = compound["NickName"] ?? compound["nickname"] ?? ""
                if !name.isEmpty { return name }
            }
        }
        if let name = dict["nickname"] ?? dict["NickName"], !name.isEmpty { return name }
        let clean = (dict["userid"] ?? "").replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
        return clean.isEmpty ? "酷狗音乐用户" : "酷狗音乐用户 \(clean)"
    }

    static func avatarFrom(_ dict: [String: String]) -> URL? {
        for key in ["KuGoo", "kugou", "Kugou"] {
            if let raw = dict[key], !raw.isEmpty {
                let compound = parseKuGoo(raw)
                let pic = compound["Pic"] ?? compound["pic"] ?? ""
                if !pic.isEmpty, let url = URL(string: pic) { return url }
            }
        }
        return nil
    }

    static func vipFrom(_ dict: [String: String]) -> String? {
        var compound: [String: String] = [:]
        for key in ["KuGoo", "kugou", "Kugou"] {
            if let raw = dict[key], !raw.isEmpty {
                compound = parseKuGoo(raw)
                break
            }
        }
        let svipKeys = ["isSVIP", "isSvip", "is_svip", "svip", "SVIPType", "svip_type", "svipLevel", "svip_level", "superVip", "super_vip", "luxuryVipType", "vip_luxury_type"]
        let vipKeys = ["isVIP", "isVip", "is_vip", "vip", "VIPType", "vip_type", "vipLevel", "vip_level", "member_type", "m_type", "p_type"]
        for key in svipKeys {
            if let value = compound[key] ?? dict[key], truthy(value) { return "SVIP" }
        }
        for key in vipKeys {
            if let value = compound[key] ?? dict[key], truthy(value) { return "VIP" }
        }
        return nil
    }

    private static func truthy(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let num = Int(text), num > 0 { return true }
        return ["1", "true", "yes", "vip", "svip", "premium", "member", "active", "valid"].contains(text)
    }

    /// 解析 KuGoo 复合字段："NickName=%u5f20&KugooID=123&Pic=..."
    static func parseKuGoo(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = text.removingPercentEncoding { text = decoded }
        for part in text.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = String(kv[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = decodeKugouText(String(kv[1]).trimmingCharacters(in: .whitespacesAndNewlines))
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    /// 解码酷狗 %uXXXX / %XX 编码文本
    static func decodeKugouText(_ text: String) -> String {
        var result = text
        if result.contains("%u") {
            let pattern = "%u([0-9a-fA-F]{4})"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = result as NSString
                var out = ""
                var last = 0
                for match in regex.matches(in: result, options: [], range: NSRange(location: 0, length: ns.length)) {
                    if match.range.location > last {
                        out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                    }
                    let hex = ns.substring(with: match.range(at: 1))
                    if let scalar = UInt32(hex, radix: 16), let unicode = UnicodeScalar(scalar) {
                        out += String(Character(unicode))
                    }
                    last = match.range.location + match.range.length
                }
                if last < ns.length { out += ns.substring(from: last) }
                if !out.isEmpty { result = out }
            }
        }
        if result.contains("%") {
            if let decoded = result.removingPercentEncoding { result = decoded }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 基础请求

    private func getJSON(_ urlString: String, headers: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NetEaseError.network }
        guard let json = parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    private func postJSON(_ urlString: String, bodyText: String?, headers: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let bodyText {
            request.httpBody = bodyText.data(using: .utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NetEaseError.network }
        guard let json = parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private func parseJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - H5 网关（歌单）

    private func h5Params(extra: [String: Any] = [:]) -> [String: Any] {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        var params: [String: Any] = [
            "srcappid": "2919",
            "clientver": "20000",
            "clienttime": now,
            "mid": mid,
            "uuid": now,
            "dfid": dfid,
            "appid": 1014,
            "token": token,
            "userid": Int(userid) ?? 0,
        ]
        for (key, value) in extra { params[key] = value }
        return params
    }

    private static func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func h5Signature(params: [String: Any], bodyText: String?) -> String {
        let salt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"
        let parts = params.keys.sorted().map { "\($0)=\(params[$0]!)" }
        var joined = parts.joined()
        if let bodyText { joined += bodyText }
        return Self.md5(salt + joined + salt)
    }

    private func gatewayURL(path: String, params: [String: Any]) -> String {
        var comps = URLComponents(string: "https://gateway.kugou.com\(path)")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        return comps.url!.absoluteString
    }

    private func gatewayHeaders() -> [String: String] {
        [
            "x-router": "cloudlist.service.kugou.com",
            "Cookie": buildCookieHeader(),
        ]
    }

    private func buildCookieHeader() -> String {
        var merged = cookies
        if merged["kg_mid"] == nil, !mid.isEmpty { merged["kg_mid"] = mid }
        if merged["kg_dfid"] == nil { merged["kg_dfid"] = dfid }
        return merged.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private static func createMid() -> String {
        let raw = "\(Date().timeIntervalSince1970)\(Int.random(in: 0...99999))"
        return md5(raw)
    }

    /// 我的歌单（登录后从酷狗云歌单同步）
    func fetchPlaylists() async throws -> [Playlist] {
        guard playbackReady else {
            throw NetEaseError.unknown("酷狗登录态不完整：请重新在网页登录，或在电脑浏览器复制完整 Cookie 粘贴导入")
        }
        let body = "{\"userid\":\(userid),\"token\":\"\(Self.jsonEscape(token))\",\"total_ver\":979,\"type\":2,\"page\":1,\"pagesize\":50}"
        var params = h5Params(extra: ["plat": 1])
        params["signature"] = h5Signature(params: params, bodyText: body)
        let json = try await postJSON(gatewayURL(path: "/v7/get_all_list", params: params), bodyText: body, headers: gatewayHeaders())
        if let status = json["status"] as? Int, status == 0 {
            let msg = json["error"] as? String ?? json["msg"] as? String ?? ""
            throw NetEaseError.unknown(msg.isEmpty ? "酷狗歌单加载失败，请稍后重试" : msg)
        }
        guard let rawData = json["data"] as? [String: Any] else { return [] }
        // 兼容嵌套 data.data 与 info 分组（collect 收藏 / love 我喜欢 / self 自建 / list 歌单）
        let data = (rawData["data"] as? [String: Any]) ?? rawData
        var lists: [[String: Any]] = []
        if let info = data["info"] as? [[String: Any]] {
            lists = info
        } else {
            let inner = data["info"] as? [String: Any] ?? data
            for key in ["collect", "love", "self", "list"] {
                if let group = inner[key] as? [[String: Any]] { lists += group }
            }
            if let list = data["list"] as? [[String: Any]] { lists += list }
        }
        return lists.compactMap { mapPlaylist($0) }
    }

    /// 歌单歌曲列表（分页拉取）
    func fetchPlaylistTracks(listID: String) async throws -> [Song] {
        guard playbackReady else {
            throw NetEaseError.unknown("酷狗登录态不完整：请重新登录后再打开歌单")
        }
        let rawID = Self.parseKugouListID(listID)
        guard !rawID.isEmpty else { throw NetEaseError.unknown("歌单 ID 无效") }
        var all: [Song] = []
        var page = 1
        let pagesize = 50
        while true {
            let body = "{\"listid\":\(rawID),\"userid\":\(userid),\"area_code\":1,\"show_relate_goods\":0,\"pagesize\":\(pagesize),\"allplatform\":1,\"show_cover\":1,\"type\":0,\"token\":\"\(Self.jsonEscape(token))\",\"page\":\(page)}"
            var params = h5Params(extra: ["plat": 1])
            params["signature"] = h5Signature(params: params, bodyText: body)
            let json = try await postJSON(gatewayURL(path: "/v4/get_list_all_file", params: params), bodyText: body, headers: gatewayHeaders())
            if let status = json["status"] as? Int, status == 0 {
                let msg = json["error"] as? String ?? json["msg"] as? String ?? ""
                throw NetEaseError.unknown(msg.isEmpty ? "酷狗歌单歌曲加载失败" : msg)
            }
            let data = json["data"] as? [String: Any] ?? [:]
            let chunk = data["info"] as? [[String: Any]] ?? data["songs"] as? [[String: Any]] ?? []
            let tracks = chunk.compactMap { mapPlaylistTrack($0) }
            all += tracks
            let total = data["count"] as? Int ?? 0
            if tracks.isEmpty || (total > 0 && all.count >= total) || tracks.count < pagesize { break }
            page += 1
            if page > 500 { break }
        }
        return all
    }

    // MARK: - 播放地址

    /// 酷狗播放地址：优先网页接口（带登录态），失败回退移动接口（免费歌曲）；VIP 无权限返回 nil
    func songURL(hash: String, albumID: String?, albumAudioID: String?) async throws -> String? {
        guard !hash.isEmpty else { return nil }
        if playbackReady {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "r", value: "play/getdata"),
                URLQueryItem(name: "hash", value: hash),
                URLQueryItem(name: "album_id", value: albumID ?? "0"),
                URLQueryItem(name: "appid", value: "1014"),
                URLQueryItem(name: "platid", value: "4"),
                URLQueryItem(name: "mid", value: mid),
                URLQueryItem(name: "dfid", value: dfid),
                URLQueryItem(name: "userid", value: userid),
                URLQueryItem(name: "token", value: token),
            ]
            if let albumAudioID, !albumAudioID.isEmpty {
                items.append(URLQueryItem(name: "album_audio_id", value: albumAudioID))
            }
            var comps = URLComponents(string: "https://wwwapi.kugou.com/yy/index.php")!
            comps.queryItems = items
            let json = try? await getJSON(comps.url!.absoluteString, headers: ["Cookie": buildCookieHeader()])
            if let json, let status = json["status"] as? Int, status == 1,
               let data = json["data"] as? [String: Any],
               let url = Self.string(data["play_url"]) ?? Self.string(data["play_backup_url"]), !url.isEmpty {
                return url.replacingOccurrences(of: "\\/", with: "/")
            }
        }
        // 移动接口：免费歌曲无需登录
        let key = Self.md5(hash + "kgcloud")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "cmd", value: "playInfo"),
            URLQueryItem(name: "hash", value: hash),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "album_id", value: albumID ?? "0"),
            URLQueryItem(name: "pid", value: "1"),
            URLQueryItem(name: "forceDown", value: "0"),
            URLQueryItem(name: "vip", value: playbackReady ? "1" : "65530"),
        ]
        if playbackReady {
            items.append(URLQueryItem(name: "userid", value: userid))
            items.append(URLQueryItem(name: "token", value: token))
        }
        var comps = URLComponents(string: "http://m.kugou.com/app/i/getSongInfo.php")!
        comps.queryItems = items
        let json = try? await getJSON(comps.url!.absoluteString, headers: ["Cookie": buildCookieHeader()])
        if let json, let status = json["status"] as? Int, status == 1,
           let url = Self.string(json["url"]) ?? Self.string(json["backup_url"]), !url.isEmpty {
            return url
        }
        return nil
    }

    // MARK: - 映射

    private func mapPlaylist(_ item: [String: Any]) -> Playlist? {
        let rawID = Self.string(item["global_collection_id"])
            ?? Self.string(item["specialid"])
            ?? Self.string(item["listid"])
            ?? Self.string(item["list_id"])
            ?? Self.string(item["id"])
            ?? ""
        guard !rawID.isEmpty else { return nil }
        let name = Self.cleanHTML(Self.string(item["name"])
            ?? Self.string(item["listname"])
            ?? Self.string(item["specialname"])
            ?? Self.string(item["title"]) ?? "酷狗歌单")
        let cover = Self.string(item["pic"])
            ?? Self.string(item["img"])
            ?? Self.string(item["imgurl"])
            ?? Self.string(item["sizable_cover"])
            ?? Self.string(item["create_user_pic"])
            ?? (item["trans_param"] as? [String: Any]).flatMap { Self.string($0["union_cover"]) }
            ?? ""
        let count = Self.int(item["count"])
            ?? Self.int(item["m_count"])
            ?? Self.int(item["song_count"])
            ?? Self.int(item["total"])
            ?? Self.int(item["list_count"]) ?? 0
        let creator = Self.cleanHTML(Self.string(item["nickname"])
            ?? Self.string(item["username"])
            ?? Self.string(item["user_name"])
            ?? Self.string(item["list_create_username"]) ?? "")
        let listID = Self.string(item["list_create_listid"])
            ?? Self.string(item["listid"])
            ?? Self.parseKugouListID(rawID)
        let numericID = Int(rawID) ?? BeansHash.stable(rawID)
        return Playlist(id: numericID, name: name, coverURL: Self.coverURL(cover, 240), trackCount: count, source: .kugou, rawID: listID.isEmpty ? rawID : listID, creatorName: creator)
    }

    private func mapPlaylistTrack(_ item: [String: Any]) -> Song? {
        let hash = Self.string(item["hash"]) ?? Self.string(item["FileHash"]) ?? ""
        guard !hash.isEmpty else { return nil }
        let singers = item["singerinfo"] as? [[String: Any]] ?? item["Singers"] as? [[String: Any]] ?? []
        let artistLabel = singers.compactMap { Self.string($0["name"]) ?? Self.string($0["SingerName"]) }.joined(separator: " / ")
        let albumInfo = item["albuminfo"] as? [String: Any]
        let albumID = Self.string(albumInfo?["id"]) ?? Self.string(item["album_id"]) ?? Self.string(item["AlbumID"]) ?? ""
        let mixSongID = Self.string(item["mixsongid"]) ?? Self.string(item["MixSongID"]) ?? Self.string(item["album_audio_id"]) ?? ""
        let albumAudioRaw = Self.string(item["EMixSongID"]) ?? Self.string(item["AlbumAudioID"]) ?? Self.string(item["album_audio_id"]) ?? ""
        let albumAudioID: String
        if mixSongID.allSatisfy({ $0.isNumber }) {
            albumAudioID = mixSongID
        } else if !albumAudioRaw.isEmpty {
            albumAudioID = albumAudioRaw
        } else {
            albumAudioID = mixSongID
        }
        let name = Self.cleanHTML(Self.string(item["name"]) ?? Self.string(item["SongName"]) ?? Self.string(item["filename"]) ?? "")
        let album = Self.cleanHTML(Self.string(item["album_name"]) ?? Self.string(albumInfo?["name"]) ?? Self.string(item["AlbumName"]) ?? "")
        let cover = Self.string(item["cover"]) ?? Self.string(item["img"]) ?? Self.string(item["Image"])
            ?? Self.string(item["album_img"]) ?? Self.string(albumInfo?["img"]) ?? Self.string(albumInfo?["cover"]) ?? ""
        let durationSec = Self.double(item["duration"])
            ?? (Self.double(item["timelen"]).map { $0 / 1000 })
            ?? Self.double(item["Duration"]) ?? 0
        let privilege = Self.int(item["media_privilege"]) ?? Self.int(item["privilege"]) ?? Self.int(item["Privilege"]) ?? 0
        let fee = privilege >= 10 ? 1 : 0
        let id = Int(albumAudioID) ?? BeansHash.stable(hash)
        return Song(kugou: id, name: name, artists: artistLabel, album: album, coverURL: Self.coverURL(cover, 240), duration: durationSec, hash: hash, albumID: albumID.isEmpty ? nil : albumID, albumAudioID: albumAudioID.isEmpty ? nil : albumAudioID, fee: fee)
    }

    // MARK: - 工具

    static func parseKugouListID(_ id: String) -> String {
        let raw = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        if raw.allSatisfy({ $0.isNumber }) { return raw }
        if raw.hasPrefix("collection_") {
            let parts = raw.split(separator: "_")
            if parts.count >= 5, parts[3].allSatisfy({ $0.isNumber }) { return String(parts[3]) }
        }
        return raw
    }

    static func coverURL(_ raw: String, _ size: Int) -> URL? {
        let url = raw.replacingOccurrences(of: "{size}", with: "\(size)")
        return url.isEmpty ? nil : URL(string: url)
    }

    static func cleanHTML(_ text: String) -> String {
        let noTags = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeKugouText(noTags)
    }

    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        return "\(value)"
    }

    static func int(_ value: Any?) -> Int? {
        if let num = value as? Int { return num }
        if let num = value as? Int64 { return Int(num) }
        if let num = value as? NSNumber { return num.intValue }
        if let text = value as? String, let num = Int(text) { return num }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let num = value as? Double { return num }
        if let num = value as? NSNumber { return num.doubleValue }
        if let text = value as? String, let num = Double(text) { return num }
        return nil
    }

    static func jsonEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
