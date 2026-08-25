import Foundation

/// 汽水音乐账号（扫码登录 / sessionid 导入）＋ 歌单同步
/// 逆向结论参考 qishui-api（github.com/guowenye/qishui-api）：
/// - 扫码：api.qishui.com passport 接口 get_qrcode 生成二维码 → check_qrconnect 轮询，
///   用「抖音 App」扫码确认后下发 sessionid（Set-Cookie）
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
    private let defaults = UserDefaults.standard
    private let sessionKey = "beans.soda.sessionid.v1"
    private let nickKey = "beans.soda.nickname.v1"
    private let vipKey = "beans.soda.vip.v1"
    private let session: URLSession
    /// 生成二维码时下发的 Cookie，轮询扫码状态时需原样带回
    private var qrCookieHeader = ""

    private let aid = "386088"
    private let iid = "27960026095955"
    private let versionCode = "30020100"

    /// 播放链路 Cookie（sessionid）
    var cookieHeader: String {
        sessionID.isEmpty ? "" : "sessionid=\(sessionID);"
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        if let saved = defaults.string(forKey: sessionKey), !saved.isEmpty {
            sessionID = saved
            isLoggedIn = true
            nickname = defaults.string(forKey: nickKey) ?? ""
            vipBadge = defaults.string(forKey: vipKey)
            Task { await fetchProfile() }
        }
    }

    // MARK: - 登录状态

    func logout() {
        sessionID = ""
        isLoggedIn = false
        nickname = ""
        avatarURL = nil
        vipBadge = nil
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: nickKey)
        defaults.removeObject(forKey: vipKey)
    }

    /// 导入 sessionid（网页登录或手动粘贴）
    func importSessionID(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        sessionID = cleaned
        isLoggedIn = true
        defaults.set(sessionID, forKey: sessionKey)
        Task { await fetchProfile() }
    }

    // MARK: - 扫码登录

    enum ScanState: Equatable {
        case waiting
        case scanned
        case success
        case expired
        case error(String)
    }

    /// 生成二维码：返回 token 与二维码图片数据（图片为 URL 时自动下载）
    func fetchQRCode() async throws -> (token: String, imageData: Data?) {
        qrCookieHeader = ""
        var comps = URLComponents(string: "https://api.qishui.com/passport/web/get_qrcode/")!
        comps.queryItems = [
            URLQueryItem(name: "passport_jssdk_version", value: "2.4.13"),
            URLQueryItem(name: "passport_jssdk_type", value: "normal"),
            URLQueryItem(name: "is_from_ttaccountsdk", value: "1"),
            URLQueryItem(name: "aid", value: aid),
            URLQueryItem(name: "next", value: "https://api.qishui.com"),
            URLQueryItem(name: "need_logo", value: "false"),
            URLQueryItem(name: "need_short_url", value: "false"),
            URLQueryItem(name: "is_new_login", value: "1"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            qrCookieHeader = Self.cookieHeader(from: http)
        }
        guard let json = Self.parseJSON(data) else {
            throw NetEaseError.decoding("汽水音乐二维码生成失败")
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        guard let token = payload["token"] as? String, !token.isEmpty else {
            throw NetEaseError.unknown("汽水音乐二维码生成失败，请检查网络后重试")
        }
        let qrcode = payload["qrcode"] as? String ?? ""
        var imageData: Data?
        if qrcode.hasPrefix("data:") {
            if let comma = qrcode.firstIndex(of: ",") {
                let b64 = String(qrcode[qrcode.index(after: comma)...])
                imageData = Data(base64Encoded: b64)
            }
        } else if let url = URL(string: qrcode) {
            if let (d, _) = try? await session.data(from: url) {
                imageData = d
            }
        }
        return (token, imageData)
    }

    /// 单次轮询扫码状态（调用方以 2~3 秒间隔重复调用）；成功后自动保存登录态
    func poll(token: String) async throws -> ScanState {
        var comps = URLComponents(string: "https://api.qishui.com/passport/web/check_qrconnect/")!
        comps.queryItems = [
            URLQueryItem(name: "passport_jssdk_version", value: "2.4.13"),
            URLQueryItem(name: "passport_jssdk_type", value: "normal"),
            URLQueryItem(name: "is_from_ttaccountsdk", value: "1"),
            URLQueryItem(name: "aid", value: aid),
            URLQueryItem(name: "iid", value: iid),
        ]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        if !qrCookieHeader.isEmpty {
            request.setValue(qrCookieHeader, forHTTPHeaderField: "Cookie")
        }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "need_logo", value: "false"),
            URLQueryItem(name: "need_short_url", value: "false"),
            URLQueryItem(name: "is_frontier", value: "true"),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "is_new_login", value: "1"),
            URLQueryItem(name: "next", value: "https://api.qishui.com"),
        ]
        request.httpBody = form.query?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetEaseError.network }
        let newSession = Self.sessionID(from: http)
        if !newSession.isEmpty {
            sessionID = newSession
            isLoggedIn = true
            defaults.set(sessionID, forKey: sessionKey)
            Task { await fetchProfile() }
            return .success
        }
        guard let json = Self.parseJSON(data) else { return .waiting }
        let payload = (json["data"] as? [String: Any]) ?? json
        let status = String(describing: payload["status"] ?? "")
        let errorCode = Self.int(payload["error_code"]) ?? 0
        if errorCode != 0 && !status.isEmpty && status != "1" && status != "2" && status != "3" {
            return .expired
        }
        switch status {
        case "2": return .scanned
        case "3": return .waiting // 已确认但尚未取到 sessionid，继续轮询
        default: return .waiting
        }
    }

    // MARK: - 账号与歌单

    /// 刷新账号资料（昵称 / VIP）
    func fetchProfile() async {
        guard isLoggedIn else { return }
        guard let json = try? await getPc("/luna/pc/me", query: ["aid": aid]) else { return }
        let info = (json["my_info"] as? [String: Any]) ?? (json["user"] as? [String: Any]) ?? json
        let nick = Self.string(info["nickname"]) ?? Self.string(info["name"]) ?? ""
        if !nick.isEmpty {
            nickname = nick
            defaults.set(nick, forKey: nickKey)
        }
        if let isVIP = info["is_vip"] as? Bool, isVIP {
            vipBadge = "VIP"
            defaults.set("VIP", forKey: vipKey)
        }
        let avatar = Self.string(info["medium_avatar_url"]) ?? Self.string(info["avatar_url"]) ?? ""
        if !avatar.isEmpty {
            avatarURL = URL(string: avatar)
        }
    }

    /// 我的歌单
    func fetchPlaylists() async throws -> [Playlist] {
        guard isLoggedIn else { throw NetEaseError.unknown("请先登录汽水音乐") }
        let json = try await getPc("/luna/pc/me/playlist", query: [
            "aid": aid,
            "iid": iid,
            "version_code": versionCode,
        ])
        let playlists = json["playlists"] as? [[String: Any]] ?? []
        return playlists.compactMap { item -> Playlist? in
            let id = Self.string(item["id"]) ?? ""
            guard !id.isEmpty else { return nil }
            let name = Self.string(item["title"]) ?? Self.string(item["name"]) ?? ""
            let cover = Self.string(item["url_cover"]) ?? Self.string(item["cover"]) ?? Self.string(item["cover_url"]) ?? ""
            let count = Self.int(item["count_tracks"]) ?? Self.int(item["track_count"]) ?? Self.int(item["song_count"]) ?? 0
            return Playlist(id: Int(id) ?? BeansHash.stable(id), name: name, coverURL: URL(string: cover), trackCount: count, source: .soda, rawID: id)
        }
    }

    /// 歌单歌曲列表
    func fetchPlaylistTracks(playlistID: String) async throws -> [Song] {
        guard isLoggedIn else { throw NetEaseError.unknown("请先登录汽水音乐") }
        let json = try await postLuna("/luna/playlist/detail", payload: ["playlist_id": playlistID, "count": 50])
        let resources = json["media_resources"] as? [[String: Any]] ?? []
        return resources.compactMap { item -> Song? in
            let entity = item["entity"] as? [String: Any] ?? item
            let track = (entity["track_wrapper"] as? [String: Any])?["track"] as? [String: Any]
                ?? entity["track"] as? [String: Any]
                ?? entity
            let id = Self.string(track["id"]) ?? ""
            guard !id.isEmpty else { return nil }
            let name = Self.string(track["name"]) ?? ""
            let albumDict = track["album"] as? [String: Any]
            let album = Self.string(albumDict?["name"]) ?? ""
            let cover = Self.pickURL(albumDict?["url_cover"]) ?? Self.pickURL(albumDict?["cover_url"])
            let artists = (track["artists"] as? [[String: Any]])?.compactMap { Self.string($0["name"]) }.joined(separator: " / ") ?? ""
            let durationMS = Self.double(track["duration"]) ?? Self.double(track["duration_ms"]) ?? 0
            return Song(soda: Int(id) ?? BeansHash.stable(id), name: name, artists: artists, album: album, coverURL: URL(string: cover), duration: durationMS / 1000, trackID: id)
        }
    }

    // MARK: - 请求

    private func getPc(_ path: String, query: [String: String]) async throws -> [String: Any] {
        var comps = URLComponents(string: "https://api.qishui.com\(path)")!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
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

    private func postLuna(_ path: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://beta-luna.douyin.com\(path)"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw NetEaseError.unknown("请求参数错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("LunaPC/3.0.0(290101097)", forHTTPHeaderField: "User-Agent")
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

    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"

    private static func parseJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - 工具

    /// 从 Set-Cookie 提取 Cookie 串（供扫码轮询带回）
    private static func cookieHeader(from http: HTTPURLResponse) -> String {
        let joined = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        var parts: [String] = []
        for part in joined.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = trimmed.firstIndex(of: ";") {
                parts.append(String(trimmed[..<idx]))
            } else if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: "; ")
    }

    /// 从 Set-Cookie 提取 sessionid（登录成功标志）
    private static func sessionID(from http: HTTPURLResponse) -> String {
        let joined = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        for part in joined.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("sessionid=") {
                let value = trimmed.dropFirst("sessionid=".count)
                return String(value.split(separator: ";").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

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
