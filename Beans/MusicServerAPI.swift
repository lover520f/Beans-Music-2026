import Foundation

/// Beans Music 服务器（musicdl 音源）接入
/// 用户在电脑上启动 BeansMusicServer（python server.py）后，
/// 在「我的 → 设置 → 音乐服务器」填入 http://电脑IP:8765，
/// 搜索歌曲时自动把服务器解析出的可播放结果展示在结果顶部。
final class MusicServerAPI {
    static let shared = MusicServerAPI()

    private let defaults = UserDefaults.standard
    private let serverKey = "beans.musicServer.url.v1"
    private let session: URLSession

    /// 服务器地址（如 http://192.168.1.100:8765），空 = 未配置
    var serverURL: String? {
        get {
            let raw = defaults.string(forKey: serverKey) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            let raw = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(raw, forKey: serverKey)
        }
    }

    var isConfigured: Bool { serverURL != nil }

    /// 默认请求的服务器音源（QQ / 网易云 / 酷狗 / 咪咕）
    static let defaultSources = "qq,netease,kugou,migu"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 360
        session = URLSession(configuration: config)
    }

    /// 服务器搜索（返回带可播放直链/代理地址的歌曲）
    func search(keyword: String, limit: Int = 5) async throws -> [Song] {
        guard let base = serverURL, !base.isEmpty else { return [] }
        var comps = URLComponents(string: base)
        comps?.path = "/api/search"
        comps?.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "sources", value: Self.defaultSources),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard let url = comps?.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("BeansMusic/1.5.5", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NetEaseError.network
        }
        guard let songsJSON = json["songs"] as? [[String: Any]] else { return [] }
        return songsJSON.compactMap { Self.song(from: $0, base: base) }
    }

    /// 服务器连通性测试（GET /api/health）
    func ping() async -> String? {
        guard let base = serverURL, !base.isEmpty else { return "请先填写服务器地址" }
        guard let url = URL(string: base + "/api/health") else { return "服务器地址格式错误" }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["status"] as? String == "ok" else {
                return "服务器响应异常，请确认已启动 server.py"
            }
            let sources = (json["sources"] as? [String]) ?? []
            return "✓ 连接正常（音源：" + sources.joined(separator: " / ") + "）"
        } catch {
            return "无法连接服务器：" + error.localizedDescription
        }
    }

    /// 服务器返回的单曲解析
    private static func song(from json: [String: Any], base: String) -> Song? {
        guard let name = json["name"] as? String, !name.isEmpty else { return nil }
        let rawID = json["id"] as? String ?? ""
        // id 为字符串，映射为稳定 Int（服务器 id 与平台 id 一致，跨平台用 source 区分）
        var hash: UInt64 = 0
        for scalar in rawID.unicodeScalars {
            hash = hash &* 31 &+ UInt64(scalar.value)
        }
        let id = Int(hash & 0x7FFFFFFF)
        let artists = json["artists"] as? String ?? ""
        let album = json["album"] as? String ?? ""
        var cover: URL?
        if let coverString = json["cover"] as? String, !coverString.isEmpty {
            cover = URL(string: coverString)
        }
        let duration = TimeInterval(json["duration"] as? Int ?? 0)
        // 优先走服务器代理流（稳定、不受直链过期影响）
        let stream = json["stream"] as? String ?? ""
        let direct = json["url"] as? String ?? ""
        let playURL: String
        if !stream.isEmpty {
            if stream.hasPrefix("http") {
                playURL = stream
            } else {
                playURL = base + stream
            }
        } else {
            playURL = direct
        }
        guard !playURL.isEmpty else { return nil }
        return Song(
            server: id,
            name: name,
            artists: artists,
            album: album,
            coverURL: cover,
            duration: duration,
            url: playURL,
            fee: json["fee"] as? Int ?? 0
        )
    }
}
