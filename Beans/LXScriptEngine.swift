import Foundation
import JavaScriptCore

/// 落雪音乐 LX 脚本音源运行时（JavaScriptCore 执行用户导入的 JS 音源）
/// 支持新一代协议（globalThis.lx 的 on / send / request，如 星海、全豆要 等聚合音源），
/// 也兼容旧一代协议（module.exports 导出 musicSearch / musicUrl 函数）。
/// 所有 JS 求值都在专用串行队列上执行，跨线程只传递已转成 Swift 的值。
final class LXScriptEngine {

    /// 搜索候选歌曲
    struct Candidate {
        var source: String
        var name: String
        var singer: String
        var album: String
        var img: String
        var id: String      // songmid / hash / id
        var durationMS: Int?
    }

    enum LXScriptError: LocalizedError {
        case notReady
        case invokeFailed
        case timeout
        case scriptError(String)
        var errorDescription: String? {
            switch self {
            case .notReady: return "音源脚本尚未就绪"
            case .invokeFailed: return "音源脚本调用失败"
            case .timeout: return "音源脚本响应超时"
            case .scriptError(let msg): return msg
            }
        }
    }

    private let scriptText: String
    private let jsQueue = DispatchQueue(label: "beans.lxscript.js")
    private var context: JSContext?
    private var didStart = false
    private var requestHandler: JSValue?
    private var oldStyleSearch: JSValue?
    private var oldStyleURL: JSValue?
    private var initedSources: [String: Any]?
    private var initedError: String?
    private var disposed = false
    private var timerCounter = 0
    private var timers: [Int: DispatchWorkItem] = [:]
    private let session: URLSession

    init(script: String) {
        scriptText = script
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    deinit {
        disposed = true
        for (_, item) in timers { item.cancel() }
        timers.removeAll()
        context = nil
    }

    // MARK: - 启动（等待脚本 inited 事件，超时 40s）

    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            jsQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: LXScriptError.notReady); return
                }
                if self.didStart {
                    cont.resume(returning: ())
                    return
                }
                self.didStart = true
                self.setupContext()
                self.context?.exceptionHandler = { [weak self] _, exc in
                    guard let self else { return }
                    let msg = exc?.toString() ?? "未知 JS 异常"
                    BeansLogger.shared.log("LX脚本 JS 异常：\(msg)", level: .debug)
                    if self.initedError == nil { self.initedError = msg }
                }
                _ = self.context?.evaluateScript(self.scriptText)
                if let exc = self.context?.exception {
                    self.initedError = exc.toString()
                    cont.resume(throwing: LXScriptError.scriptError(exc.toString() ?? "脚本异常"))
                    return
                }
                // 检测旧一代协议：module.exports 导出函数
                if let moduleVal = self.context?.objectForKeyedSubscript("module"),
                   let exports = moduleVal.objectForKeyedSubscript("exports") {
                    let searchFn = exports.objectForKeyedSubscript("musicSearch")
                    let urlFn = exports.objectForKeyedSubscript("musicUrl")
                    if !(searchFn?.isUndefined ?? true) { self.oldStyleSearch = searchFn }
                    if !(urlFn?.isUndefined ?? true) { self.oldStyleURL = urlFn }
                }
                let inv = StartInvocation(cont: cont)
                let watchdog = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.initedSources != nil {
                        inv.finish(.success(()))
                    } else if let err = self.initedError {
                        self.didStart = false
                        inv.finish(.failure(LXScriptError.scriptError(err)))
                    } else {
                        self.didStart = false
                        inv.finish(.failure(LXScriptError.timeout))
                    }
                }
                self.jsQueue.asyncAfter(deadline: .now() + 40, execute: watchdog)
                self.pollInited(inv: inv, watchdog: watchdog)
            }
        }
    }

    private final class StartInvocation {
        var finished = false
        let cont: CheckedContinuation<Void, Error>
        init(cont: CheckedContinuation<Void, Error>) { self.cont = cont }
        func finish(_ result: Result<Void, Error>) {
            guard !finished else { return }
            finished = true
            cont.resume(with: result)
        }
    }

    private func pollInited(inv: StartInvocation, watchdog: DispatchWorkItem) {
        guard !inv.finished else { return }
        if initedSources != nil {
            watchdog.cancel()
            inv.finish(.success(()))
            return
        }
        if let err = initedError {
            watchdog.cancel()
            didStart = false
            inv.finish(.failure(LXScriptError.scriptError(err)))
            return
        }
        jsQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pollInited(inv: inv, watchdog: watchdog)
        }
    }

    // MARK: - 注入宿主环境

    private func setupContext() {
        guard context == nil else { return }
        let ctx = JSContext()!
        context = ctx

        // console
        let logBlock: @convention(block) (JSValue) -> Void = { [weak self] args in
            let items = args.toArray().map { "\($0)" }.joined(separator: " ")
            BeansLogger.shared.log("LX脚本: \(items)", level: .debug)
        }
        ctx.setObject(logBlock, forKeyedSubscript: "__lx_log" as NSString)

        // request(url, options, callback) -> cancelFn
        let requestBlock: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] urlValue, optionsValue, callback in
            guard let self, let ctx = self.context else { return JSValue(undefinedIn: JSContext()) }
            let urlString = urlValue.toString() ?? ""
            let method = (optionsValue.objectForKeyedSubscript("method")?.toString() ?? "GET").uppercased()
            var headers: [String: String] = [:]
            if let h = optionsValue.objectForKeyedSubscript("headers")?.toObject() as? [String: Any] {
                for (k, v) in h { headers[k] = "\(v)" }
            }
            let bodyText = optionsValue.objectForKeyedSubscript("body")?.toString()
            var taskRef: URLSessionTask?
            let cancelBlock: @convention(block) () -> Void = { _ = taskRef?.cancel() }
            let cancelFn = JSValue(object: cancelBlock, in: ctx) ?? JSValue(undefinedIn: ctx)

            guard let url = URL(string: urlString) else {
                callback.call(withArguments: [JSValue(object: ["message": "无效的请求地址 \(urlString)"], in: ctx), JSValue(undefinedIn: ctx)])
                return cancelFn
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            if let bodyText, !bodyText.isEmpty { request.httpBody = bodyText.data(using: .utf8) }

            let task = self.session.dataTask(with: request) { data, response, error in
                self.jsQueue.async { [weak self] in
                    guard let self, let ctx = self.context else { return }
                    if let error {
                        let errValue = JSValue(object: ["message": error.localizedDescription], in: ctx)
                        callback.call(withArguments: [errValue, JSValue(undefinedIn: ctx)])
                        return
                    }
                    let respObj = JSValue(newObjectIn: ctx)
                    if let http = response as? HTTPURLResponse {
                        respObj.setObject(http.statusCode, forKeyedSubscript: "statusCode")
                        let headersObj = JSValue(newObjectIn: ctx)
                        for (k, v) in http.allHeaderFields {
                            headersObj.setObject(String(describing: v), forKeyedSubscript: "\(k)" as NSString)
                        }
                        respObj.setObject(headersObj, forKeyedSubscript: "headers")
                    }
                    let bodyText2 = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    respObj.setObject(bodyText2, forKeyedSubscript: "body")
                    callback.call(withArguments: [JSValue(nullIn: ctx), respObj])
                }
            }
            taskRef = task
            task.resume()
            return cancelFn
        }
        ctx.setObject(requestBlock, forKeyedSubscript: "__lx_request" as NSString)

        // on(event, handler)
        let onBlock: @convention(block) (JSValue, JSValue) -> Void = { [weak self] eventValue, handlerValue in
            guard let self else { return }
            if eventValue.toString() == "request" { self.requestHandler = handlerValue }
        }
        ctx.setObject(onBlock, forKeyedSubscript: "__lx_on" as NSString)

        // send(event, data)
        let sendBlock: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] eventValue, dataValue, _ in
            guard let self else { return }
            let event = eventValue.toString()
            if event == "inited" {
                let obj = dataValue.toObject() as? [String: Any]
                self.initedSources = obj?["sources"] as? [String: Any]
            } else if event != "updateAlert" {
                BeansLogger.shared.log("LX脚本事件 \(eventValue.toString() ?? "")", level: .debug)
            }
        }
        ctx.setObject(sendBlock, forKeyedSubscript: "__lx_send" as NSString)

        // setTimeout / clearTimeout / setInterval / clearInterval
        let setTimeoutBlock: @convention(block) (JSValue, Double) -> JSValue = { [weak self] fn, ms in
            guard let self, let ctx = self.context else { return JSValue(undefinedIn: JSContext()) }
            self.timerCounter += 1
            let tid = self.timerCounter
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.timers[tid] = nil
                if !fn.isUndefined { _ = fn.call(withArguments: []) }
                if let exc = self.context?.exception { self.context?.exception = nil }
            }
            self.timers[tid] = item
            self.jsQueue.asyncAfter(deadline: .now() + max(0, ms / 1000), execute: item)
            return JSValue(int32: Int32(tid), in: ctx)
        }
        ctx.setObject(setTimeoutBlock, forKeyedSubscript: "setTimeout" as NSString)

        let clearTimeoutBlock: @convention(block) (JSValue) -> Void = { [weak self] idValue in
            guard let self else { return }
            let tid = Int(idValue.toInt32())
            self.timers[tid]?.cancel()
            self.timers[tid] = nil
        }
        ctx.setObject(clearTimeoutBlock, forKeyedSubscript: "clearTimeout" as NSString)

        let setIntervalBlock: @convention(block) (JSValue, Double) -> JSValue = { [weak self] fn, ms in
            guard let self, let ctx = self.context else { return JSValue(undefinedIn: JSContext()) }
            self.timerCounter += 1
            let tid = self.timerCounter
            let interval = max(0.05, ms / 1000)
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.disposed else { return }
                if !fn.isUndefined { _ = fn.call(withArguments: []) }
                if let exc = self.context?.exception { self.context?.exception = nil }
                if !self.disposed {
                    self.jsQueue.asyncAfter(deadline: .now() + interval, execute: item)
                }
            }
            self.timers[tid] = item
            self.jsQueue.asyncAfter(deadline: .now() + interval, execute: item)
            return JSValue(int32: Int32(tid), in: ctx)
        }
        ctx.setObject(setIntervalBlock, forKeyedSubscript: "setInterval" as NSString)

        let clearIntervalBlock: @convention(block) (JSValue) -> Void = { [weak self] idValue in
            guard let self else { return }
            let tid = Int(idValue.toInt32())
            self.timers[tid]?.cancel()
            self.timers[tid] = nil
        }
        ctx.setObject(clearIntervalBlock, forKeyedSubscript: "clearInterval" as NSString)

        // 宿主环境 JS 注入
        ctx.evaluateScript("""
        if (typeof console === 'undefined' || !console) {
          var console = {
            log: function(){ __lx_log(Array.prototype.slice.call(arguments)); },
            info: function(){ __lx_log(Array.prototype.slice.call(arguments)); },
            warn: function(){ __lx_log(Array.prototype.slice.call(arguments)); },
            error: function(){ __lx_log(Array.prototype.slice.call(arguments)); },
            debug: function(){ __lx_log(Array.prototype.slice.call(arguments)); }
          };
        }
        var __lx = {
          EVENT_NAMES: { inited: 'inited', request: 'request', updateAlert: 'updateAlert', log: 'log' },
          request: __lx_request,
          on: __lx_on,
          send: __lx_send
        };
        globalThis.lx = __lx;
        globalThis.httpFetch = function(url, options) {
          return new Promise(function(resolve, reject) {
            var cancel = __lx_request(url, options || {}, function(err, resp) {
              if (err) { reject(new Error(String(err))); }
              else { resolve(resp); }
            });
          });
        };
        var __be_await = function(value, onOk, onErr) {
          if (value && typeof value.then === 'function') {
            value.then(onOk, onErr);
          } else {
            onOk(value);
          }
        };
        """)
    }

    // MARK: - 调用脚本处理器（Promise 桥接）

    private func invoke(action: String, source: String, info: [String: Any], timeout: TimeInterval = 45) async throws -> Any {
        guard let handler = jsQueue.sync(execute: { requestHandler }) else { throw LXScriptError.notReady }
        // 新一代协议载荷结构：{ action, source, info }，info 内才是 musicInfo / 搜索词等
        let payload: [String: Any] = ["action": action, "source": source, "info": info]
        return try await callJS(handler, args: [payload], timeout: timeout)
    }

    private func callJS(_ fn: JSValue, args: [Any], timeout: TimeInterval) async throws -> Any {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any, Error>) in
            jsQueue.async { [weak self] in
                guard let self, let ctx = self.context else {
                    cont.resume(throwing: LXScriptError.notReady); return
                }
                let argValues = args.map { JSValue(object: $0, in: ctx) }
                guard let promise = fn.call(withArguments: argValues) else {
                    cont.resume(throwing: LXScriptError.invokeFailed); return
                }
                if let exc = ctx.exception {
                    let msg = exc.toString() ?? "脚本异常"
                    ctx.exception = nil
                    cont.resume(throwing: LXScriptError.scriptError(msg))
                    return
                }
                let inv = Invocation(cont: cont)
                let watchdog = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    inv.finish(.failure(LXScriptError.timeout))
                }
                self.jsQueue.asyncAfter(deadline: .now() + timeout, execute: watchdog)

                let resolveBlock: @convention(block) (JSValue) -> Void = { v in
                    watchdog.cancel()
                    inv.finish(.success(v.toObject() ?? NSNull()))
                }
                let rejectBlock: @convention(block) (JSValue) -> Void = { v in
                    watchdog.cancel()
                    inv.finish(.failure(LXScriptError.scriptError(v.toString() ?? "脚本调用失败")))
                }
                guard let resolveFn = JSValue(object: resolveBlock as @convention(block) (JSValue) -> Void, in: ctx),
                      let rejectFn = JSValue(object: rejectBlock as @convention(block) (JSValue) -> Void, in: ctx),
                      let awaitFn = ctx.objectForKeyedSubscript("__be_await") else {
                    inv.finish(.failure(LXScriptError.invokeFailed))
                    return
                }
                awaitFn.call(withArguments: [promise, resolveFn, rejectFn])
            }
        }
    }

    private final class Invocation {
        var finished = false
        let cont: CheckedContinuation<Any, Error>
        init(cont: CheckedContinuation<Any, Error>) { self.cont = cont }
        func finish(_ result: Result<Any, Error>) {
            guard !finished else { return }
            finished = true
            cont.resume(with: result)
        }
    }

    // MARK: - 对外接口：搜索 / 取流

    /// 搜索歌曲（遍历支持搜索的源，返回候选列表）
    func search(keyword: String, limit: Int = 20) async throws -> [Candidate] {
        // 旧一代协议优先走 musicSearch
        if let old = jsQueue.sync(execute: { oldStyleSearch }) {
            let info: [String: Any] = ["name": keyword, "singer": "", "source": "wy", "limit": limit]
            if let raw = try? await callJS(old, args: [info], timeout: 45) {
                return Self.parseSongList(raw, defaultSource: "wy")
            }
        }
        guard let sources = initedSources else { throw LXScriptError.notReady }
        var results: [Candidate] = []
        for (sourceID, cfgAny) in sources {
            guard let cfg = cfgAny as? [String: Any] else { continue }
            let actions = (cfg["actions"] as? [String]) ?? []
            let searchAction: String
            if actions.contains("musicSearch") { searchAction = "musicSearch" }
            else if actions.contains("search") { searchAction = "search" }
            else { continue }
            let info: [String: Any] = ["key": keyword, "keyword": keyword, "name": keyword, "limit": limit]
            guard let raw = try? await invoke(action: searchAction, source: sourceID, info: info) else { continue }
            results.append(contentsOf: Self.parseSongList(raw, defaultSource: sourceID))
        }
        return results
    }

    /// 按源取流：songInfo 至少包含 id / name / singer，返回播放地址
    func resolveURL(source: String, songInfo: [String: Any], quality: String = "320k") async throws -> String {
        // 旧一代协议优先走 musicUrl
        if let old = jsQueue.sync(execute: { oldStyleURL }) {
            let info: [String: Any] = [
                "songId": songInfo["id"] ?? "",
                "name": songInfo["name"] ?? "",
                "singer": songInfo["singer"] ?? "",
                "source": songInfo["source"] ?? source,
                "quality": quality,
            ]
            if let raw = try? await callJS(old, args: [info], timeout: 45) {
                if let url = Self.extractURL(raw) { return url }
            }
        }
        let info: [String: Any] = ["musicInfo": songInfo, "type": quality]
        let raw = try await invoke(action: "musicUrl", source: source, info: info)
        if let url = Self.extractURL(raw) { return url }
        throw LXScriptError.scriptError("音源未返回有效的播放地址")
    }

    // MARK: - 结果解析

    private static func parseSongList(_ raw: Any, defaultSource: String) -> [Candidate] {
        var list: [Any] = []
        if let arr = raw as? [Any] {
            list = arr
        } else if let dict = raw as? [String: Any] {
            if let l = dict["list"] as? [Any] { list = l }
            else if let l = dict["songs"] as? [Any] { list = l }
            else if let l = dict["data"] as? [Any] { list = l }
        }
        return list.compactMap { item -> Candidate? in
            guard let d = item as? [String: Any] else { return nil }
            let name = (d["name"] as? String) ?? (d["title"] as? String) ?? ""
            let singer = (d["singer"] as? String) ?? (d["author"] as? String) ?? (d["artist"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            let id = firstString(d, keys: ["songmid", "songId", "hash", "id", "rid", "mid", "strMediaMid", "mediaId"]) ?? ""
            let album = (d["album"] as? String) ?? (d["albumname"] as? String) ?? ""
            let img = (d["img"] as? String) ?? (d["cover"] as? String) ?? (d["picture"] as? String) ?? ""
            let interval = firstInt(d, keys: ["interval", "duration", "durationms"])
            let durationMS: Int?
            if let v = interval {
                durationMS = v < 1000 ? v * 1000 : v
            } else {
                durationMS = nil
            }
            return Candidate(source: (d["source"] as? String) ?? defaultSource,
                             name: name, singer: singer, album: album, img: img,
                             id: id, durationMS: durationMS)
        }
    }

    private static func extractURL(_ raw: Any) -> String? {
        if let s = raw as? String, s.hasPrefix("http") { return s }
        if let dict = raw as? [String: Any] {
            if let u = dict["url"] as? String, u.hasPrefix("http") { return u }
            if let data = dict["data"] as? [String: Any], let u = data["url"] as? String, u.hasPrefix("http") { return u }
        }
        return nil
    }

    private static func firstString(_ d: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let n = d[k] as? NSNumber, !n.stringValue.isEmpty { return n.stringValue }
        }
        return nil
    }

    private static func firstInt(_ d: [String: Any], keys: [String]) -> Int? {
        for k in keys {
            if let n = d[k] as? NSNumber { return n.intValue }
            if let s = d[k] as? String, let n = Int(s) { return n }
        }
        return nil
    }
}
