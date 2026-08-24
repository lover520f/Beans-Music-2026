import Foundation

/// 用户自定义的第三方解锁源（JSON 导入）
/// kind：netease-id（按网易云 ID 查询）或 keyword（按 歌名+歌手 关键词查询）
/// template：请求 URL 模板，支持占位符 {id} {name} {keyword} {artist}
/// urlPath：响应 JSON 中播放地址的字段路径（支持点分，如 url / data.url / data.audioUrl）
/// headers：可选的附加请求头
struct ThirdPartySource: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var kind: String = "keyword"
    var template: String
    var urlPath: String = "url"
    var headers: [String: String] = [:]
    /// 落雪 LX 脚本音源（kind == "lxscript"）的完整 JS 源码
    var script: String = ""

    enum CodingKeys: String, CodingKey { case id, name, kind, template, urlPath, headers, script }

    init(id: String = UUID().uuidString, name: String, kind: String = "keyword", template: String, urlPath: String = "url", headers: [String: String] = [:], script: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.template = template
        self.urlPath = urlPath
        self.headers = headers
        self.script = script
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名音源"
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "keyword"
        template = try c.decodeIfPresent(String.self, forKey: .template) ?? ""
        urlPath = try c.decodeIfPresent(String.self, forKey: .urlPath) ?? "url"
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
    }
}

/// 第三方解锁源管理：内置源开关 + 用户导入的自定义源（UserDefaults 持久化）
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()

    /// 内置源开关（默认全开）
    @Published var builtinEnabled: [String: Bool] {
        didSet { defaults.set(builtinEnabled, forKey: builtinKey) }
    }
    /// 用户导入的自定义源
    @Published var customSources: [ThirdPartySource] {
        didSet { save() }
    }

    /// 内置源顺序：pyncmd → kuwo → bodian
    static let builtinOrder = ["pyncmd", "kuwo", "bodian"]

    private let defaults = UserDefaults.standard
    private let builtinKey = "beans.unblock.builtin.v2"
    private let customKey = "beans.unblock.custom"

    private init() {
        let saved = defaults.dictionary(forKey: builtinKey) as? [String: Bool] ?? [:]
        var merged: [String: Bool] = [:]
        for key in Self.builtinOrder { merged[key] = saved[key] ?? false }
        for (k, v) in saved { merged[k] = v }
        builtinEnabled = merged
        if let data = defaults.data(forKey: customKey),
           let list = try? JSONDecoder().decode([ThirdPartySource].self, from: data) {
            customSources = list
        } else {
            customSources = []
        }
    }

    func isEnabled(_ id: String) -> Bool {
        builtinEnabled[id] ?? false
    }

    func setBuiltin(_ id: String, enabled: Bool) {
        builtinEnabled[id] = enabled
    }

    func add(_ source: ThirdPartySource) {
        customSources.append(source)
    }

    func remove(_ source: ThirdPartySource) {
        customSources.removeAll { $0.id == source.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customSources) {
            defaults.set(data, forKey: customKey)
        }
    }
}
