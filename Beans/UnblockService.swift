import Foundation

/// 灰色歌曲 / VIP 试听解锁（仅使用用户导入的第三方音源）
/// 按导入顺序依次尝试已开启的源：落雪 API 服务器（lx）→ 落雪 LX 脚本（lxscript）→ JSON 模板源（netease-id / keyword）
enum UnblockService {
    struct Resolved {
        let url: URL
        let source: String

        var sourceTitle: String { source }
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

    /// 入口：按用户导入顺序依次尝试已开启的源，返回第一个可用地址
    /// - Parameter strict: 严格模式（周杰伦等版权歌手）：要求 歌名+歌手+时长 三重匹配原唱，校验不过直接拒绝，绝不播放翻唱
    static func resolve(name: String, artists: String, durationMS: Int, neteaseID: Int, strict: Bool = false) async -> Resolved? {
        let keyword = ([name, artists].filter { !$0.isEmpty })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }

        let store = UnblockSourceStore.shared
        for source in store.customSources where source.enabled {
            if source.kind == "lx" {
                if let r = await lx(source: source, keyword: keyword) { return r }
            } else if source.kind == "lxscript", !source.script.isEmpty {
                if let r = await lxScript(source: source, keyword: keyword, name: name, artists: artists, neteaseID: neteaseID, durationMS: durationMS) { return r }
            } else if let r = await custom(source: source, name: name, artists: artists, neteaseID: neteaseID) { return r }
        }
        return nil
    }

    /// 音源自检：用固定测试歌曲（周杰伦-晴天，网易云 ID）验证音源能否取到播放地址，返回真实错误信息
    static func testSource(_ source: ThirdPartySource) async -> Result<String, Error> {
        do {
            switch source.kind {
            case "lxscript":
                let engine = LXScriptEngine(script: source.script)
                try await engine.start()
                let songInfo: [String: Any] = ["id": "2652820720", "name": "晴天", "singer": "周杰伦", "source": "wy"]
                let url = try await engine.resolveURL(source: "wy", songInfo: songInfo)
                return .success(url)
            case "lx":
                guard let r = await lx(source: source, keyword: "晴天 周杰伦") else {
                    throw NSError(domain: "Beans.UnblockService", code: 1, userInfo: [NSLocalizedDescriptionKey: "落雪 API 服务器未返回可用地址（检查服务器地址与网络）"])
                }
                return .success(r.url.absoluteString)
            case "netease-id":
                guard let r = await custom(source: source, name: "晴天", artists: "周杰伦", neteaseID: 2652820720) else {
                    throw NSError(domain: "Beans.UnblockService", code: 2, userInfo: [NSLocalizedDescriptionKey: "音源未返回可用地址（检查 template / urlPath / 网络）"])
                }
                return .success(r.url.absoluteString)
            default:
                guard let r = await custom(source: source, name: "晴天", artists: "周杰伦", neteaseID: 0) else {
                    throw NSError(domain: "Beans.UnblockService", code: 3, userInfo: [NSLocalizedDescriptionKey: "音源未返回可用地址（检查 template / urlPath / 网络）"])
                }
                return .success(r.url.absoluteString)
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 自定义源（用户导入的 JSON 模板源）

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

    // MARK: - 落雪 LX 脚本音源（JavaScriptCore 运行用户导入的 JS 音源，如 星海 / 全豆要）

    /// 引擎缓存：最多保留 3 个，避免每次播放都重新初始化脚本
    private static let lxEngineLock = NSLock()
    private static var lxEngines: [String: LXScriptEngine] = [:]
    private static var lxEngineUsed: [String: Date] = [:]

    private static func lxEngine(for source: ThirdPartySource) -> LXScriptEngine {
        lxEngineLock.lock()
        defer { lxEngineLock.unlock() }
        if let engine = lxEngines[source.id] {
            lxEngineUsed[source.id] = Date()
            return engine
        }
        if lxEngines.count >= 3, let oldest = lxEngineUsed.min(by: { $0.value < $1.value }) {
            lxEngines.removeValue(forKey: oldest.key)
            lxEngineUsed.removeValue(forKey: oldest.key)
        }
        let engine = LXScriptEngine(script: source.script)
        lxEngines[source.id] = engine
        lxEngineUsed[source.id] = Date()
        return engine
    }

    private static func lxScript(source: ThirdPartySource, keyword: String, name: String, artists: String, neteaseID: Int, durationMS: Int) async -> Resolved? {
        let engine = lxEngine(for: source)
        do {
            try await engine.start()
        } catch {
            BeansLogger.shared.log("LX脚本音源「\(source.name)」初始化失败：\(error.localizedDescription)", level: .error)
            return nil
        }
        // 策略 1：网易云歌曲直接用网易云 ID + wy 平台取流（全豆要 / 星海等脚本均支持）
        if neteaseID > 0 {
            let songInfo: [String: Any] = ["id": String(neteaseID), "name": name, "singer": artists, "source": "wy"]
            do {
                let url = try await engine.resolveURL(source: "wy", songInfo: songInfo)
                if let playURL = URL(string: url) {
                    return Resolved(url: playURL, source: source.name)
                }
                BeansLogger.shared.log("LX脚本音源「\(source.name)」wy 取流未返回有效地址", level: .debug)
            } catch {
                BeansLogger.shared.log("LX脚本音源「\(source.name)」wy 取流失败：\(error.localizedDescription)", level: .error)
            }
        }
        // 策略 2：按 歌名+歌手 搜索，命中最佳匹配后取流
        do {
            let candidates = try await engine.search(keyword: keyword)
            if let best = bestLXCandidate(candidates, name: name, artists: artists, durationMS: durationMS) {
                let songInfo: [String: Any] = ["id": best.id, "name": best.name, "singer": best.singer, "source": best.source]
                let url = try await engine.resolveURL(source: best.source, songInfo: songInfo)
                if let playURL = URL(string: url) {
                    return Resolved(url: playURL, source: source.name)
                }
            }
        } catch {
            BeansLogger.shared.log("LX脚本音源「\(source.name)」搜索取流失败：\(error.localizedDescription)", level: .debug)
        }
        return nil
    }

    /// 从 LX 脚本搜索候选里挑最佳匹配：歌名 / 歌手 / 时长 加权
    private static func bestLXCandidate(_ candidates: [LXScriptEngine.Candidate], name: String, artists: String, durationMS: Int) -> LXScriptEngine.Candidate? {
        let targetName = normalizeMatch(name)
        let targetArtist = normalizeMatch(artists)
        var best: LXScriptEngine.Candidate?
        var bestScore = -1
        for c in candidates {
            var score = 0
            let cn = normalizeMatch(c.name)
            let ca = normalizeMatch(c.singer)
            if cn == targetName { score += 100 }
            else if cn.contains(targetName) || targetName.contains(cn) { score += 60 }
            if !ca.isEmpty, !targetArtist.isEmpty, ca == targetArtist { score += 50 }
            else if !ca.isEmpty, !targetArtist.isEmpty, ca.contains(targetArtist) || targetArtist.contains(ca) { score += 25 }
            if let d = c.durationMS, durationMS > 0, abs(d - durationMS) <= 4000 { score += 20 }
            if score > bestScore { bestScore = score; best = c }
        }
        return best
    }

    private static func normalizeMatch(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "（[^（）]*）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\([^()]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
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
}