import Foundation
import CryptoKit

/// 酷狗音乐登录态管理（网页登录 + Cookie 导入）
/// 酷狗没有公开扫码授权接口（wp_MusicApi 的酷狗模块也只有 Cookie 导入），
/// 因此采用与 QQ 音乐一致的方案：应用内 WKWebView 网页登录，或粘贴浏览器 Cookie。
/// 登录后播放直链请求携带 kugou.com 域 Cookie（mid / kg_mid / dfid 等），
/// VIP 歌曲由应用内第三方音源（网易云同名匹配 + 解锁）兜底免费播放。
final class KugouMusicAuth: ObservableObject {
    static let shared = KugouMusicAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""
    /// 酷狗会员标识：nil 无 / "VIP" / "SVIP"（从 Cookie 尽力解析，失败不阻塞）
    @Published private(set) var vipBadge: String?

    private var cookies: [String: String] = [:]

    private let defaults = UserDefaults.standard
    private let cookieKey = "beans.kugou.cookie.v1"
    private let nickKey = "beans.kugou.nickname.v1"
    private let midKey = "beans.kugou.mid.v1"
    private let vipKey = "beans.kugou.vip.v1"

    private init() {
        if let saved = defaults.dictionary(forKey: cookieKey) as? [String: String], !saved.isEmpty {
            cookies = saved
            isLoggedIn = true
            nickname = defaults.string(forKey: nickKey) ?? ""
            vipBadge = defaults.string(forKey: vipKey)
        }
    }

    // MARK: - 登录状态

    /// 设备 mid：酷狗接口必填；优先 cookie 里的 mid/kg_mid，否则取本机生成的 md5(uuid)
    var mid: String {
        if let m = cookies["mid"], !m.isEmpty { return m }
        if let m = cookies["kg_mid"], !m.isEmpty { return m }
        if let saved = defaults.string(forKey: midKey), !saved.isEmpty { return saved }
        let generated = Self.generateMID()
        defaults.set(generated, forKey: midKey)
        return generated
    }

    /// 发给 kugou.com 接口的 Cookie 串
    var cookieHeader: String {
        let order = ["mid", "kg_mid", "dfid", "kg_dfid", "username", "userid", "KugouID", "token", "vip_type", "vip", "VIP", "userhash"]
        return order.compactMap { key in
            guard let value = cookies[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "; ")
    }

    func logout() {
        cookies = [:]
        isLoggedIn = false
        nickname = ""
        vipBadge = nil
        defaults.removeObject(forKey: cookieKey)
        defaults.removeObject(forKey: nickKey)
        defaults.removeObject(forKey: vipKey)
    }

    // MARK: - Cookie 导入

    func importCookies(_ dict: [String: String], nickname: String?) {
        guard !dict.isEmpty else { return }
        cookies = dict
        isLoggedIn = true
        self.nickname = nickname ?? Self.fallbackNickname(dict)
        defaults.set(cookies, forKey: cookieKey)
        defaults.set(self.nickname, forKey: nickKey)
        let badge = Self.vipBadge(from: dict)
        vipBadge = badge
        if let badge { defaults.set(badge, forKey: vipKey) } else { defaults.removeObject(forKey: vipKey) }
    }

    /// 是否包含账号登录态（网页自动检测只用这个，避免设备 Cookie 误判登录）
    func hasAccountLogin(_ dict: [String: String]) -> Bool {
        if let uid = dict["userid"], !uid.isEmpty, uid != "0" { return true }
        if let kuid = dict["KugouID"], !kuid.isEmpty, kuid != "0" { return true }
        if let username = dict["username"], !username.isEmpty { return true }
        return false
    }

    /// Cookie 是否有效：有账号字段视为已登录；只有设备标识也允许导入（保证能正常播放）
    func hasValidLogin(_ dict: [String: String]) -> Bool {
        if let uid = dict["userid"], !uid.isEmpty, uid != "0" { return true }
        if let kuid = dict["KugouID"], !kuid.isEmpty, kuid != "0" { return true }
        if let username = dict["username"], !username.isEmpty { return true }
        let deviceKeys = ["mid", "kg_mid", "dfid"]
        return deviceKeys.contains { key in
            guard let value = dict[key] else { return false }
            return !value.isEmpty
        }
    }

    /// 网页登录关注的 Cookie 名（WKWebView 读取时按此过滤）
    static let webCookieNames: Set<String> = [
        "mid", "kg_mid", "dfid", "kg_dfid", "username", "userid", "KugouID",
        "vip_type", "vip", "VIP", "token", "userhash", "openid", "kg_mid_new",
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

    /// 昵称兜底：优先 username，其次 userid，最后固定文案
    static func fallbackNickname(_ dict: [String: String]) -> String {
        if let name = dict["username"], !name.isEmpty { return name }
        if let uid = dict["userid"], !uid.isEmpty, uid != "0" { return "酷狗用户 \(uid)" }
        return "酷狗音乐用户"
    }

    /// 从 Cookie 解析会员标识（vip_type：1 VIP，2 豪华，3 终身；vip=1 也视为 VIP）
    static func vipBadge(from dict: [String: String]) -> String? {
        let raw = dict["vip_type"] ?? dict["VIP"] ?? dict["vip"] ?? ""
        switch raw.lowercased() {
        case "2", "3", "4", "true": return "SVIP"
        case "1": return "VIP"
        default: return nil
        }
    }

    /// 生成酷狗 mid：md5(uuid)
    static func generateMID() -> String {
        let digest = Insecure.MD5.hash(data: Data(UUID().uuidString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

