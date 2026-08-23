import Foundation
import CryptoKit

/// 酷狗音乐接口（搜索 / 播放直链 / 歌词 / 热搜 / 评论 / 排行榜 / 歌单）
/// 逆向自 wp_MusicApi（https://github.com/GitHub-ZC/wp_MusicApi）酷狗模块，仅供学习交流。
/// 说明：
/// - 酷狗没有公开扫码授权接口，登录只能走网页登录 / Cookie 导入（见 KugouMusicAuth）。
/// - 播放直链：VIP 歌曲接口返回"需要付费"，由 PlayerManager 走网易云同名匹配 / 第三方解锁兜底。
final class KugouMusicAPI {
    static let shared = KugouMusicAPI()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    // MARK: - 基础请求

    private func get(_ urlString: String, referer: String = "https://www.kugou.com/", cookie: String = "") async throws -> Data {
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NetEaseError.network }
        return data
    }

    /// http 明文的 POST（酷狗排行接口走 kmr.service.kugou.com，仅支持明文）
    private func postPlain(_ urlString: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NetEaseError.network }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetEaseError.decoding("酷狗排行解析失败")
        }
        return obj
    }

    private func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 解码酷狗 HTML 转义实体（&amp; &lt; 等）
    private func decodeName(_ raw: String?) -> String {
        guard let raw else { return "" }
        var s = raw
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#039;": "'"]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    /// 封面地址：酷狗封面模板含 {size} 占位符，统一替换为 400
    private func cover(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw.replacingOccurrences(of: "{size}", with: "400"))
    }

    /// 稳定的歌曲数字 id（用 hash 前 8 位十六进制，避免跨启动哈希漂移）
    private func stableID(hash: String) -> Int {
        Int(hash.prefix(8), radix: 16) ?? abs(hash.hashValue)
    }

    // MARK: - 搜索

    /// 单曲搜索（mobilecdn 接口，无需签名，与解锁音源同源）
    func searchSongs(keyword: String, limit: Int = 40) async throws -> [Song] {
        var comps = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/song")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: String(limit)),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "https://m.kugou.com/")
        guard let obj = json(data),
              let d = obj["data"] as? [String: Any],
              let list = d["info"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗搜索解析失败")
        }
        var songs: [Song] = []
        var seen = Set<String>()
        for item in list {
            guard let hash = item["hash"] as? String, !hash.isEmpty else { continue }
            if seen.contains(hash) { continue }
            seen.insert(hash)
            if let song = searchSong(from: item) { songs.append(song) }
        }
        return songs
    }

    private func searchSong(from item: [String: Any]) -> Song? {
        guard let hash = item["hash"] as? String, !hash.isEmpty else { return nil }
        let name = decodeName(item["songname"] as? String ?? "")
        let artists = decodeName(item["singername"] as? String ?? "")
        let album = decodeName(item["album_name"] as? String ?? "")
        let albumID: String
        if let s = item["album_id"] as? String { albumID = s }
        else if let i = item["album_id"] as? Int { albumID = String(i) }
        else { albumID = "" }
        let duration = Double(item["duration"] as? Int ?? 0)
        let payType = item["pay_type"] as? Int ?? 0
        let privilege = item["privilege"] as? [String: Any]
        let fee = (privilege?["pay_type"] as? Int) ?? payType
        var img = item["imgUrl"] as? String ?? ""
        if img.isEmpty, let c = item["cover"] as? String { img = c }
        return Song(
            id: stableID(hash: hash),
            name: name.isEmpty ? (item["filename"] as? String ?? "") : name,
            artists: artists,
            album: album,
            coverURL: cover(img),
            duration: duration,
            source: .kugou,
            qqMid: nil,
            fee: fee,
            kugouHash: hash,
            kugouAlbumID: albumID.isEmpty ? nil : albumID
        )
    }

    /// 歌手搜索（mobilecdn search/singer，data 直接是数组）
    func searchArtists(keyword: String) async throws -> [Artist] {
        var comps = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/singer")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "20"),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "https://m.kugou.com/")
        guard let obj = json(data), let list = obj["data"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗歌手解析失败")
        }
        return list.compactMap { item in
            guard let id = item["singerid"] as? Int ?? Int(item["singerid"] as? String ?? "") else { return nil }
            return Artist(id: "kg-\(id)", name: decodeName(item["singername"] as? String ?? ""), coverURL: nil, source: .kugou)
        }
    }

    /// 专辑搜索（mobilecdn search/album）
    func searchAlbums(keyword: String) async throws -> [Album] {
        var comps = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/album")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "20"),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "https://m.kugou.com/")
        guard let obj = json(data),
              let d = obj["data"] as? [String: Any],
              let list = d["info"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗专辑解析失败")
        }
        return list.compactMap { item in
            guard let id = item["albumid"] as? Int ?? Int(item["albumid"] as? String ?? "") else { return nil }
            return Album(
                id: "kg-\(id)",
                name: decodeName(item["albumname"] as? String ?? ""),
                artistName: decodeName(item["singername"] as? String ?? ""),
                coverURL: cover(item["imgurl"] as? String),
                source: .kugou,
                trackCount: item["songcount"] as? Int
            )
        }
    }

    /// 热搜
    func hotSearch() async throws -> [String] {
        var comps = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/hot")!
        comps.queryItems = [URLQueryItem(name: "format", value: "json")]
        let data = try await get(comps.url!.absoluteString, referer: "https://m.kugou.com/")
        guard let obj = json(data),
              let d = obj["data"] as? [String: Any],
              let list = d["info"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗热搜解析失败")
        }
        return list.compactMap { $0["keyword"] as? String }
    }

    // MARK: - 播放 / 歌词

    /// 播放直链：免费歌曲直接返回 URL；VIP / 无版权返回 nil（交给兜底）
    func playURL(hash: String) async throws -> String? {
        var comps = URLComponents(string: "http://m.kugou.com/app/i/getSongInfo.php")!
        comps.queryItems = [
            URLQueryItem(name: "cmd", value: "playInfo"),
            URLQueryItem(name: "hash", value: hash),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "http://m.kugou.com/")
        guard let obj = json(data) else { throw NetEaseError.decoding("酷狗播放地址解析失败") }
        guard let status = obj["status"] as? Int, status == 1 else { return nil }
        let url = (obj["url"] as? String) ?? (obj["play_url"] as? String) ?? ""
        return url.isEmpty ? nil : url
    }

    /// 歌词（LRC 文本；krc.php 直接返回纯文本，无需解码 KRC）
    func lyric(hash: String, durationMS: Int = 0) async throws -> String? {
        var comps = URLComponents(string: "http://m.kugou.com/app/i/krc.php")!
        let ms = durationMS > 0 ? durationMS : 240_000
        comps.queryItems = [
            URLQueryItem(name: "cmd", value: "100"),
            URLQueryItem(name: "hash", value: hash),
            URLQueryItem(name: "timelength", value: String(ms)),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "http://m.kugou.com/")
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // 去掉 BOM 与酷狗头部元信息行（[id:$..] [ar:] [ti:] [by:] [hash:] [al:] [sign:] [qq:] [total:] [offset:]）
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("[id:$") || line.hasPrefix("[ar:") || line.hasPrefix("[ti:")
                || line.hasPrefix("[by:") || line.hasPrefix("[hash:") || line.hasPrefix("[al:")
                || line.hasPrefix("[sign:") || line.hasPrefix("[qq:") || line.hasPrefix("[total:")
                || line.hasPrefix("[offset:") || line.hasPrefix("[language:") { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 评论

    struct KugouCommentPage {
        let comments: [SongComment]
        let total: Int
    }

    /// 歌曲评论（最新评论；酷狗单页最多 40 条，默认取 20）
    func comments(hash: String, page: Int, limit: Int = 20) async throws -> KugouCommentPage {
        guard !hash.isEmpty else { throw NetEaseError.unknown("缺少歌曲 hash") }
        let capped = min(max(limit, 1), 40)
        let k = Int(Date().timeIntervalSince1970)
        let md5Str = "OIlwieks28dk2k092lksi2UIkpappid=1005clienttime=\(k)clienttoken=clientver=10869code=fc4be23b4e972707f36b8a828a93ba8adfid=1tSE9K4VW4ZW0299bn0Gu1bNextdata=\(hash)kugouid=0mid=143773497225871101952332916871990469790p=\(page)pagesize=\(capped)schash=\(hash)uuid=4f3e2278033606d95d92efddc0744d9cver=10OIlwieks28dk2k092lksi2UIkp"
        let signature = md5Hex(md5Str)
        var comps = URLComponents(string: "http://m.comment.service.kugou.com:80/r/v1/rank/newest")!
        comps.queryItems = [
            URLQueryItem(name: "dfid", value: "1tSE9K4VW4ZW0299bn0Gu1bN"),
            URLQueryItem(name: "mid", value: "143773497225871101952332916871990469790"),
            URLQueryItem(name: "signature", value: signature),
            URLQueryItem(name: "clienttime", value: String(k)),
            URLQueryItem(name: "uuid", value: "4f3e2278033606d95d92efddc0744d9c"),
            URLQueryItem(name: "extdata", value: hash),
            URLQueryItem(name: "appid", value: "1005"),
            URLQueryItem(name: "code", value: "fc4be23b4e972707f36b8a828a93ba8a"),
            URLQueryItem(name: "schash", value: hash),
            URLQueryItem(name: "clientver", value: "10869"),
            URLQueryItem(name: "p", value: String(page)),
            URLQueryItem(name: "clienttoken", value: ""),
            URLQueryItem(name: "pagesize", value: String(capped)),
            URLQueryItem(name: "ver", value: "10"),
            URLQueryItem(name: "kugouid", value: "0"),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "https://www.kugou.com/", cookie: KugouMusicAuth.shared.cookieHeader)
        guard let obj = json(data), let list = obj["list"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗评论解析失败")
        }
        let comments = list.compactMap { comment(from: $0) }
        let total = (obj["count"] as? Int) ?? (obj["combine_count"] as? Int) ?? comments.count
        return KugouCommentPage(comments: comments, total: total)
    }

    private func comment(from item: [String: Any]) -> SongComment? {
        guard let id = item["id"] as? Int ?? (item["pid"] as? Int) else { return nil }
        let content = item["content"] as? String ?? ""
        let nickname = (item["user_name"] as? String) ?? (item["puser"] as? String) ?? ""
        let avatar = item["user_pic"] as? String ?? ""
        let liked = (item["like"] as? [String: Any])?["likenum"] as? Int ?? 0
        let ts = item["addtimestamp"] as? Int ?? 0
        return SongComment(
            id: id,
            content: content,
            nickname: nickname,
            avatarURL: avatar.isEmpty ? nil : URL(string: avatar),
            time: Date(timeIntervalSince1970: Double(ts)),
            likedCount: liked
        )
    }

    // MARK: - 排行榜

    struct KugouTopInfo: Identifiable, Hashable {
        let id: Int
        let name: String
        let coverURL: URL?
    }

    /// 排行榜分类（ocean/v6/rank/list，固定签名）
    func topLists() async throws -> [KugouTopInfo] {
        let url = "https://gateway.kugou.com/ocean/v6/rank/list?srcappid=2919&dfid=10xLht0e9p5G2Gfkup4IHVuV&mid=212826578698488017179831213621749832494&signature=52321c148cf00a55c64f8534e5e6929f&clienttime=1661880203&uuid=4f3e2278033606d95d92efddc0744d9c&area_code=1&apiver=14&plat=1&withsong=1&showtype=2&clientver=11289&parentid=0&version=11289&cctv=1"
        let data = try await get(url)
        guard let obj = json(data),
              let d = obj["data"] as? [String: Any],
              let list = d["info"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗排行榜解析失败")
        }
        return list.compactMap { item in
            guard let id = item["rankid"] as? Int else { return nil }
            let name = item["rankname"] as? String ?? ""
            let img = (item["album_img_9"] as? String) ?? (item["banner_9"] as? String) ?? ""
            return KugouTopInfo(id: id, name: name, coverURL: cover(img))
        }
    }

    /// 排行榜歌曲（kmr.service.kugou.com rank_audio，固定 key，明文 HTTP）
    func topListSongs(rankID: Int, page: Int = 1, limit: Int = 20) async throws -> [Song] {
        let body: [String: Any] = [
            "appid": 1001,
            "clientver": "10053",
            "mid": "70a02aad1ce4648e7dca77f2afa7b182",
            "clienttime": 1661650645,
            "key": "f1813b8c45644335d20b5054e255f8c5",
            "area_code": "1",
            "show_video": 1,
            "page": page,
            "pagesize": limit,
            "rank_id": String(rankID),
            "rank_cid": String(rankID),
            "zone": "tx6_gz_kmr",
        ]
        let obj = try await postPlain("http://kmr.service.kugou.com/container/v2/rank_audio", body: body)
        guard let list = obj["data"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗排行歌曲解析失败")
        }
        return list.compactMap { rankSong(from: $0) }
    }

    private func rankSong(from item: [String: Any]) -> Song? {
        let filename = item["filename"] as? String ?? ""
        let parts = filename.split(separator: " - ", maxSplits: 1).map(String.init)
        let name = parts.count > 1 ? parts[1] : filename
        let artists = parts.count > 1 ? parts[0] : ""
        let hash = (item["hash"] as? String) ?? (item["hash_128"] as? String) ?? ""
        guard !hash.isEmpty else { return nil }
        let albumID = item["album_id"] as? Int ?? 0
        let duration = Double(item["timelength_128"] as? Int ?? 0) / 1000.0
        let payType = (item["pay_type_128"] as? Int) ?? (item["pay_type"] as? Int) ?? 0
        return Song(
            id: stableID(hash: hash),
            name: decodeName(name),
            artists: decodeName(artists),
            album: "",
            coverURL: nil,
            duration: duration,
            source: .kugou,
            qqMid: nil,
            fee: payType,
            kugouHash: hash,
            kugouAlbumID: albumID == 0 ? nil : String(albumID)
        )
    }

    // MARK: - 歌单

    /// 歌单广场（m.kugou.com plist，无需登录）
    func playlists(page: Int = 1, limit: Int = 20) async throws -> [Playlist] {
        var comps = URLComponents(string: "https://m.kugou.com/plist/index")!
        comps.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "json", value: "true"),
        ]
        let data = try await get(comps.url!.absoluteString, referer: "https://m.kugou.com/")
        guard let obj = json(data),
              let plist = obj["plist"] as? [String: Any],
              let list = plist["list"] as? [String: Any],
              let info = list["info"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗歌单解析失败")
        }
        return info.prefix(limit).compactMap { item in
            guard let pid = item["specialid"] as? Int ?? Int(item["specialid"] as? String ?? "") else { return nil }
            let name = decodeName(item["specialname"] as? String ?? "")
            let count = item["songcount"] as? Int ?? 0
            return Playlist(id: pid, name: name, coverURL: cover(item["imgurl"] as? String), trackCount: count, source: .kugou)
        }
    }

    /// 歌单内歌曲（爬取酷狗歌单页 global.data，仅供学习交流）
    func playlistSongs(pid: Int) async throws -> [Song] {
        let url = "http://www2.kugou.kugou.com/yueku/v9/special/single/\(pid)-6-1084.html"
        let data = try await get(url, referer: "http://www2.kugou.kugou.com/")
        guard let text = String(data: data, encoding: .utf8) else {
            throw NetEaseError.decoding("酷狗歌单页解析失败")
        }
        let pattern = #"global\.data = (\[.+?\]);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            throw NetEaseError.decoding("酷狗歌单无数据")
        }
        let jsonText = String(text[range])
        guard let raw = jsonText.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗歌单数据解析失败")
        }
        var songs: [Song] = []
        var seen = Set<String>()
        for item in list {
            guard let hash = (item["hash"] as? String) ?? (item["hash_128"] as? String), !hash.isEmpty else { continue }
            if seen.contains(hash) { continue }
            seen.insert(hash)
            let name = decodeName(item["songname"] as? String ?? "")
            let artists = decodeName(item["singername"] as? String ?? "")
            let albumID = item["album_id"] as? Int ?? 0
            let duration = Double(item["duration"] as? Int ?? 0) / 1000.0
            let vip = item["vip"] as? Int ?? 0
            let coverURL = cover((item["cover"] as? String) ?? (item["imgUrl"] as? String))
            songs.append(Song(
                id: stableID(hash: hash),
                name: name,
                artists: artists,
                album: "",
                coverURL: coverURL,
                duration: duration,
                source: .kugou,
                qqMid: nil,
                fee: vip,
                kugouHash: hash,
                kugouAlbumID: albumID == 0 ? nil : String(albumID)
            ))
        }
        return songs
    }
}
