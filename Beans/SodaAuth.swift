import Foundation

/// 汽水音乐账号（网页登录 / sessionid 导入）＋ 歌单同步
/// 逆向结论参考 qishui-api（github.com/guowenye/qishui-api）：
/// - 登录：应用内打开汽水音乐网页版完成登录，读取 qishui.com 域登录态 Cookie（sessionid）
/// - 账号：api.qishui.com/luna/pc/me；我的歌单：/luna/pc/me/playlist；
///   歌单歌曲：beta-luna.douyin.com/luna/playlist/detail
final class SodaAuth: ObservableObject {
    static let shared = SodaAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""
    @Published private(set) var avatarURL: URL?
    /// 会员标识：nil 无 / "VIP"（尽力从账号信息判断，失败不阻塞）
    @Published private(set) var vipBadge: String?

    private var sessionID = ""
    /// 网页登录成功后保存的整段登录 Cookie（sessionid 等），播放链路原样带回
    private var cookieHeaderValue = ""
    private let defaults = UserDefaults.standard
    private let sessionKey = "beans.soda.sessionid.v1"
    private let cookieKey = "beans.soda.cookie.v1"
    private let nickKey = "beans.soda.nickname.v1"
    private let vipKey = "beans.soda.vip.v1"
    private let session: URLSession

    /// 网页登录后从 /luna/pc/me 获取的 user_id（歌单接口需要）
    private var userId = ""
    private let userIdKey = "beans.soda.userid.v1"

    /// 网页登录关注的 Cookie 名（WKWebView / 粘贴整段 Cookie 时按此过滤）
    static let webCookieNames: Set<String> = [
        "sessionid", "sessionid_ss", "sid_guard", "sid_tt", "sid_ucp_v1",
        "uid_tt", "uid_tt_ss", "uid_ucp_v1", "passport_csrf_token",
        "passport_csrf_token_default", "msToken", "odin_tt", "ttwid", "s_v_web_id",
    ]

    /// 播放链路 Cookie（整段登录 Cookie；仅导入 sessionid 时退化为 sessionid=...）
    var cookieHeader: String {
        if !cookieHeaderValue.isEmpty { return cookieHeaderValue }
        return sessionID.isEmpty ? "" : "sessionid=\(sessionID);"
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        if let saved = defaults.string(forKey: sessionKey), !saved.isEmpty {
            sessionID = saved
            cookieHeaderValue = defaults.string(forKey: cookieKey) ?? ""
            isLoggedIn = true
            nickname = defaults.string(forKey: nickKey) ?? ""
            vipBadge = defaults.string(forKey: vipKey)
            Task { await fetchProfile() }
        }
    }

    // MARK: - 登录状态

    func logout() {
        sessionID = ""
        cookieHeaderValue = ""
        isLoggedIn = false
        nickname = ""
        avatarURL = nil
        vipBadge = nil
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: cookieKey)
        defaults.removeObject(forKey: nickKey)
        defaults.removeObject(forKey: vipKey)
    }

    /// 导入 sessionid（网页登录或手动粘贴）
    func importSessionID(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        sessionID = cleaned
        cookieHeaderValue = ""
        isLoggedIn = true
        defaults.set(sessionID, forKey: sessionKey)
        defaults.removeObject(forKey: cookieKey)
        Task { await fetchProfile() }
    }

    /// 导入整段登录 Cookie（网页登录成功 / 手动粘贴整段 Cookie 时调用）
    func importCookieHeader(_ raw: String) {
        importSessionCookie(raw)
    }

    /// 登录成功后保存整段 session_cookie（含 sessionid 与其它登录态 Cookie）
    private func importSessionCookie(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        cookieHeaderValue = cleaned.hasSuffix(";") ? cleaned : cleaned + ";"
        if let part = cleaned.split(separator: ";").first(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("sessionid=") }) {
            let value = String(part.split(separator: "=", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { sessionID = value }
        }
        isLoggedIn = true
        defaults.set(cookieHeaderValue, forKey: cookieKey)
        if !sessionID.isEmpty { defaults.set(sessionID, forKey: sessionKey) }
        Task { await fetchProfile() }
    }


    // MARK: - 账号与歌单

    /// 登录后验证：刷新账号资料并拉取歌单，返回错误信息（nil 表示成功）
    func verifyLogin() async -> String? {
        guard isLoggedIn else { return "登录态无效，请重新登录" }
        await fetchProfile()
        do {
            _ = try await fetchPlaylists()
            return nil
        } catch {
            return error.localizedDescription
        }
    }


    func fetchProfile() async {
        guard isLoggedIn else { return }
        guard let json = try? await getPc("/luna/pc/me") else { return }
        let data = (json["data"] as? [String: Any]) ?? json
        let info = (data["my_info"] as? [String: Any])
            ?? (data["myInfo"] as? [String: Any])
            ?? (data["user"] as? [String: Any])
            ?? data
        let nick = Self.string(info["nickname"])
            ?? Self.string(info["display_name"])
            ?? Self.string(info["name"])
            ?? Self.string(data["nickname"]) ?? ""
        if !nick.isEmpty {
            nickname = nick
            defaults.set(nick, forKey: nickKey)
        }
        if Self.bool(info["is_vip"]) == true || Self.bool(info["isVip"]) == true {
            vipBadge = "VIP"
            defaults.set("VIP", forKey: vipKey)
        }
        let avatar = Self.string(info["medium_avatar_url"])
            ?? Self.string(info["avatar_url"])
            ?? Self.string(data["medium_avatar_url"])
            ?? Self.string(data["avatar_url"]) ?? ""
        if !avatar.isEmpty {
            avatarURL = URL(string: avatar)
        }
        // 保存 user_id（歌单接口需要）
        if let uid = Self.string(info["id"])
            ?? Self.string(info["user_id"])
            ?? Self.string(info["userId"])
            ?? Self.string(info["uid"])
            ?? Self.string(info["sec_uid"])
            ?? Self.string(data["user_id"])
            ?? Self.string(data["userId"])
            ?? Self.string(data["uid"])
            ?? Self.string(data["id"]), !uid.isEmpty {
            userId = uid
            defaults.set(uid, forKey: userIdKey)
        }
    }

    // MARK: - 抖音护照扫码登录（参考 qishui-api auth_qrcode / check_qrconnect）

    /// 扫码登录二维码信息
    struct SodaQRInfo {
        let token: String
        let imageData: Data
    }

    /// 扫码登录轮询状态
    enum SodaQRStatus: Equatable {
        case waiting
        case scanned
        case success
        case expired
        case error(String)
    }

    private var loginQRCookie = ""

    /// 获取抖音护照扫码登录二维码（GET /passport/web/get_qrcode/），返回二维码 PNG 数据
    func fetchLoginQR() async throws -> SodaQRInfo {
        let urlString = "https://api.qishui.com/passport/web/get_qrcode/?passport_jssdk_version=2.4.13&passport_jssdk_type=normal&is_from_ttaccountsdk=1&aid=386088&next=https%3A%2F%2Fapi.qishui.com&need_logo=false&need_short_url=false&is_new_login=1"
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("二维码地址无效") }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://api.qishui.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = Self.parseJSON(data) else { throw NetEaseError.network }
        loginQRCookie = Self.csrfCookie(from: http, url: url)
        let obj = (json["data"] as? [String: Any]) ?? json
        guard let token = Self.string(obj["token"]), !token.isEmpty,
              let qr = Self.string(obj["qrcode"]), qr.hasPrefix("data:image"),
              let comma = qr.firstIndex(of: ","),
              let imageData = Data(base64Encoded: String(qr[qr.index(after: comma)...])) else {
            throw NetEaseError.unknown("获取汽水登录二维码失败，请重试")
        }
        return SodaQRInfo(token: token, imageData: imageData)
    }

    /// 轮询扫码状态（POST /passport/web/check_qrconnect/），成功后自动导入 sessionid
    func pollLoginQR(token: String) async -> SodaQRStatus {
        var comps = URLComponents(string: "https://api.qishui.com/passport/web/check_qrconnect/")!
        comps.queryItems = [
            URLQueryItem(name: "passport_jssdk_version", value: "2.4.13"),
            URLQueryItem(name: "passport_jssdk_type", value: "normal"),
            URLQueryItem(name: "is_from_ttaccountsdk", value: "1"),
            URLQueryItem(name: "aid", value: "386088"),
            URLQueryItem(name: "iid", value: "27960026095955"),
        ]
        let body = "need_logo=false&need_short_url=false&is_frontier=true&token=\(token)&is_new_login=1&next=https%3A%2F%2Fapi.qishui.com"
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if !loginQRCookie.isEmpty { request.setValue(loginQRCookie, forHTTPHeaderField: "Cookie") }
        request.httpBody = body.data(using: .utf8)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = Self.parseJSON(data) else { return .error("登录接口异常，请重试") }
            // 成功时 Set-Cookie 携带 sessionid，整段导入登录态
            let cookie = Self.sessionCookie(from: http, url: comps.url!)
            if Self.extractSessionID(from: cookie) != nil {
                importSessionCookie(cookie)
                return .success
            }
            let obj = (json["data"] as? [String: Any]) ?? json
            let status = Self.string(obj["status"]) ?? ""
            switch status {
            case "confirm": return .scanned
            case "success": return .error("登录成功但未获取到会话，请重新登录")
            case "expired": return .expired
            default: return .waiting
            }
        } catch {
            return .error("网络异常，请重试")
        }
    }

    /// 从响应中提取 passport_csrf_token 作为轮询 Cookie
    private static func csrfCookie(from response: HTTPURLResponse, url: URL) -> String {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:], for: url)
        for cookie in cookies where cookie.name == "passport_csrf_token" || cookie.name == "passport_csrf_token_default" {
            return "\(cookie.name)=\(cookie.value)"
        }
        return ""
    }

    /// 从响应中提取登录后的整段 Cookie（含 sessionid）
    private static func sessionCookie(from response: HTTPURLResponse, url: URL) -> String {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:], for: url)
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }


    /// 从整段 Cookie 中提取 sessionid（无则返回 nil）
    private static func extractSessionID(from cookie: String) -> String? {
        let parts = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts where part.lowercased().hasPrefix("sessionid=") {
            let value = part.dropFirst("sessionid=".count)
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }
    /// 我的歌单
    /// 我的歌单（我创建的 + 收藏的，网页版接口）
    func fetchPlaylists() async throws -> [Playlist] {
        guard isLoggedIn else { throw NetEaseError.unknown("请先登录汽水音乐") }
        if userId.isEmpty, let saved = defaults.string(forKey: userIdKey), !saved.isEmpty {
            userId = saved
        }
        var seen = Set<String>()
        var result: [Playlist] = []
        // 1) 我创建的歌单
        if !userId.isEmpty,
           let json = try? await getPc("/luna/pc/me/playlist", extra: ["cursor": "", "count": "50"]) {
            for item in Self.extractPlaylistCards(json) {
                appendPlaylist(item, seen: &seen, into: &result)
            }
        }
        // 2) 收藏的歌单
        if let json = try? await getPc("/luna/pc/me/collection/mixed", extra: ["cursor": "", "count": "50"]) {
            for item in Self.extractPlaylistCards(json) {
                appendPlaylist(item, seen: &seen, into: &result)
            }
        }
        return result
    }

    private func appendPlaylist(_ item: [String: Any], seen: inout Set<String>, into result: inout [Playlist]) {
        guard let id = Self.string(item["id"]), !id.isEmpty else { return }
        let name = Self.string(item["name"]) ?? Self.string(item["title"]) ?? ""
        guard !name.isEmpty else { return }
        if seen.contains(id) { return }
        seen.insert(id)
        let cover = Self.string(item["cover"]) ?? Self.string(item["cover_url"]) ?? Self.string(item["url_cover"]) ?? ""
        let count = Self.int(item["trackCount"]) ?? Self.int(item["count_tracks"]) ?? Self.int(item["track_count"]) ?? Self.int(item["count"]) ?? 0
        result.append(Playlist(id: Int(id) ?? BeansHash.stable(id), name: name, coverURL: cover.isEmpty ? nil : URL(string: cover), trackCount: count, source: .soda, rawID: id))
    }

    /// 歌单歌曲列表（Luna App 接口 beta-luna.douyin.com/luna/playlist/detail，游标分页）
    func fetchPlaylistTracks(playlistID: String) async throws -> [Song] {
        guard isLoggedIn else { throw NetEaseError.unknown("请先登录汽水音乐") }
        var all: [[String: Any]] = []
        var cursor = ""
        var hasMore = true
        var page = 0
        while hasMore && page < 20 {
            page += 1
            var payload: [String: Any] = ["playlist_id": playlistID, "count": 100]
            if !cursor.isEmpty { payload["cursor"] = cursor }
            let json = try await postLuna("/luna/playlist/detail", payload: payload)
            let data = (json["data"] as? [String: Any]) ?? json
            let items = Self.extractMediaList(json)
            all += items
            let nextCursor = Self.string(data["next_cursor"]) ?? Self.string(data["nextCursor"]) ?? ""
            let hasMoreFlag = Self.bool(data["has_more"]) ?? Self.bool(data["hasMore"]) ?? false
            cursor = nextCursor
            hasMore = hasMoreFlag && !nextCursor.isEmpty && !items.isEmpty
        }
        return all.compactMap { mapMediaToSong($0) }
    }

    private func mapMediaToSong(_ item: [String: Any]) -> Song? {
        let entity = (item["entity"] as? [String: Any]) ?? item
        let track = ((entity["track_wrapper"] as? [String: Any])?["track"] as? [String: Any])
            ?? (entity["track"] as? [String: Any])
            ?? entity
        let id = Self.string(track["id"]) ?? ""
        guard !id.isEmpty else { return nil }
        let name = Self.string(track["name"]) ?? ""
        let albumDict = track["album"] as? [String: Any]
        let album = Self.string(albumDict?["name"]) ?? ""
        let cover = Self.pickURL(albumDict?["url_cover"])
            ?? Self.pickURL(albumDict?["cover_url"])
            ?? Self.pickURL(track["cover_url"])
            ?? Self.pickURL(track["url_cover"])
        let artists = (track["artists"] as? [[String: Any]])?.compactMap { Self.string($0["name"]) }.joined(separator: " / ")
            ?? (track["author"] as? [[String: Any]])?.compactMap { Self.string($0["name"]) }.joined(separator: " / ")
            ?? (track["singer"] as? String) ?? ""
        let durationMS = Self.double(track["duration"]) ?? Self.double(track["duration_ms"]) ?? 0
        return Song(soda: Int(id) ?? BeansHash.stable(id), name: name, artists: artists, album: album, coverURL: URL(string: cover), duration: durationMS / 1000, trackID: id)
    }

    // MARK: - 请求

    /// PC 版通用参数（参考 Mineradio qishuiPcAppParams）
    private func pcParams(_ extra: [String: String]?) -> [String: String] {
        let deviceId = String(Int(Date().timeIntervalSince1970 * 1000))
        var params: [String: String] = [
            "aid": "386088",
            "app_name": "luna_pc",
            "region": "cn",
            "geo_region": "cn",
            "os_region": "cn",
            "sim_region": "",
            "device_id": deviceId,
            "cdid": "",
            "iid": deviceId,
            "version_name": "3.3.0",
            "version_code": "30030000",
            "channel": "official",
            "build_mode": "master",
            "network_carrier": "",
            "ac": "wifi",
            "tz_name": "Asia/Shanghai",
            "resolution": "",
            "device_platform": "windows",
            "device_type": "Windows",
            "os_version": "Windows 11",
            "fp": deviceId,
        ]
        if let extra { params.merge(extra) { _, new in new } }
        return params
    }

    /// Luna App 接口 POST（歌单详情等，参考 qishui-api postLuna；UA 为 Luna/19.1.0 Android）
    private func postLuna(_ path: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://beta-luna.douyin.com\(path)"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw NetEaseError.unknown("请求参数错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Luna/19.1.0 Android", forHTTPHeaderField: "User-Agent")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NetEaseError.network }
        guard let json = Self.parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    private func getPc(_ path: String, extra: [String: String]? = nil) async throws -> [String: Any] {
        var comps = URLComponents(string: "https://api.qishui.com\(path)")!
        comps.queryItems = pcParams(extra).compactMap { pair in
            guard !pair.value.isEmpty else { return nil }
            return URLQueryItem(name: pair.key, value: pair.value)
        }
        var request = URLRequest(url: comps.url!)
        request.setValue("LunaPC/3.3.0(359450208)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.qishui.com/", forHTTPHeaderField: "Referer")
        request.setValue("foreground", forHTTPHeaderField: "x-luna-background-type")
        request.setValue("0", forHTTPHeaderField: "x-luna-is-background-req")
        request.setValue("1", forHTTPHeaderField: "x-luna-is-local-user")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NetEaseError.network }
        guard let json = Self.parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }



    private static func parseJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - 歌单 / 歌曲提取（参考 Mineradio qishui-api）

    /// 从接口响应中递归提取歌单卡片（统一输出 id/name/cover/trackCount）
    private static func extractPlaylistCards(_ payload: [String: Any]) -> [[String: Any]] {
        let data = (payload["data"] as? [String: Any]) ?? payload
        var out: [[String: Any]] = []
        var seen = Set<String>()
        func visit(_ node: Any?, _ depth: Int) {
            if node == nil || depth > 6 { return }
            if let array = node as? [Any] {
                for item in array { visit(item, depth + 1) }
                return
            }
            guard let dict = node as? [String: Any] else { return }
            var candidates: [[String: Any]] = []
            for key in ["playlist", "playlist_info", "collection", "collect_playlist", "fav_playlist", "resource"] {
                if let sub = dict[key] as? [String: Any] { candidates.append(sub) }
            }
            candidates.append(dict)
            for item in candidates {
                let id = playlistID(from: item)
                let name = playlistName(from: item)
                guard !id.isEmpty, !name.isEmpty else { continue }
                let key = "\(id)|\(name)"
                if seen.contains(key) { continue }
                seen.insert(key)
                let count = Self.int(item["count_tracks"]) ?? Self.int(item["track_count"])
                    ?? Self.int(item["media_count"]) ?? Self.int(item["count"]) ?? Self.int(item["total"]) ?? 0
                out.append([
                    "id": id,
                    "name": name,
                    "cover": playlistCover(from: item),
                    "trackCount": count,
                ])
            }
            for (_, value) in dict.prefix(80) { visit(value, depth + 1) }
        }
        visit(data, 0)
        return out
    }

    private static func playlistID(from item: [String: Any]) -> String {
        Self.string(item["playlist_id"]) ?? Self.string(item["playlistId"])
            ?? Self.string(item["collection_id"]) ?? Self.string(item["collectionId"])
            ?? Self.string(item["id"]) ?? Self.string(item["item_id"])
            ?? Self.string(item["resource_id"]) ?? Self.string(item["object_id"])
            ?? Self.string(item["server_id"]) ?? ""
    }

    private static func playlistName(from item: [String: Any]) -> String {
        Self.string(item["title"]) ?? Self.string(item["public_title"]) ?? Self.string(item["publicTitle"])
            ?? Self.string(item["name"]) ?? Self.string(item["display_title"])
            ?? Self.string(item["display_name"]) ?? Self.string(item["playlist_name"])
            ?? Self.string(item["collection_name"]) ?? ""
    }

    private static func playlistCover(from item: [String: Any]) -> String {
        for key in ["cover_url", "cover", "cover_uri", "image", "image_url", "url_cover", "icon", "avatar"] {
            if let text = Self.string(item[key]), !text.isEmpty { return text }
        }
        return ""
    }

    /// 从接口响应中提取歌曲资源列表（优先常见字段，递归兜底）
    private static func extractMediaList(_ payload: [String: Any]) -> [[String: Any]] {
        let data = (payload["data"] as? [String: Any]) ?? payload
        let keys = ["media_resources", "media_list", "related_media", "medias", "media",
                    "tracks", "track_list", "songs", "items", "list", "result",
                    "song_list", "recommend_media_list"]
        for key in keys {
            if let array = data[key] as? [[String: Any]] { return array }
        }
        var candidates: [[String: Any]] = []
        var bestCount = 0
        func walk(_ node: Any?, _ depth: Int) {
            if node == nil || depth > 4 { return }
            if let array = node as? [Any] {
                let mediaLike = array.compactMap { item -> [String: Any]? in
                    guard let dict = item as? [String: Any] else { return nil }
                    let hit = dict["media"] != nil || dict["track_entity"] != nil || dict["entity"] != nil
                        || dict["base_info"] != nil || dict["id"] != nil || dict["media_id"] != nil
                    return hit ? dict : nil
                }
                if mediaLike.count > bestCount {
                    bestCount = mediaLike.count
                    candidates = mediaLike
                }
                for item in array { walk(item, depth + 1) }
            } else if let dict = node as? [String: Any] {
                for (_, value) in dict.prefix(80) { walk(value, depth + 1) }
            }
        }
        walk(data, 0)
        return candidates
    }


    // MARK: - 工具

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        return "\(value)"
    }

    private static func int(_ value: Any?) -> Int? {
        if let num = value as? Int { return num }
        if let num = value as? Int64 { return Int(num) }
        if let num = value as? NSNumber { return num.intValue }
        if let text = value as? String, let num = Int(text) { return num }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let num = value as? Double { return num }
        if let num = value as? NSNumber { return num.doubleValue }
        if let text = value as? String, let num = Double(text) { return num }

        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let num = value as? NSNumber { return num.boolValue }
        if let text = value as? String {
            let lowered = text.lowercased()
            if lowered == "true" || text == "1" { return true }
            if lowered == "false" || text == "0" { return false }
        }
        return nil
    }


    private static func pickURL(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let text = value as? String { return text }
        if let dict = value as? [String: Any] {
            if let urls = dict["urls"] as? [String], let first = urls.first {
                return first + (dict["uri"] as? String ?? "")
            }
            return dict["url"] as? String ?? dict["uri"] as? String ?? dict["template"] as? String ?? ""
        }
        return ""
    }
}
