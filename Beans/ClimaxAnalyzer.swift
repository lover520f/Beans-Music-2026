import AVFoundation
import Foundation

/// 高潮点检测（PeakEnergy）：后台流式读取音频 PCM，按 1 秒窗口计算 RMS 能量，
/// 取能量最高的 20 秒窗口中心作为高潮提示点；结果按歌曲缓存到 UserDefaults。
/// 借鉴 Kumone 的音量分析思路，比「歌词密度」启发式更贴近真实听感。
enum ClimaxAnalyzer {
    private static let cacheKey = "beans.climaxCache.v1"

    struct Cache: Codable {
        var entries: [String: Double]
    }

    static func cachedClimax(for key: String) -> Double? {
        loadCache().entries[key]
    }

    /// 分析音频 URL（有缓存直接返回；后台 utility 优先级，不阻塞播放）
    static func analyze(url: URL, key: String) async -> Double? {
        if let cached = cachedClimax(for: key) { return cached }
        let result = await Task.detached(priority: .utility) {
            await analyzeSync(url: url)
        }.value
        if let result {
            var cache = loadCache()
            cache.entries[key] = result
            saveCache(cache)
        }
        return result
    }

    private static func loadCache() -> Cache {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return Cache(entries: [:])
        }
        return cache
    }

    private static func saveCache(_ cache: Cache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    /// 分析：AVAssetReader 流式读取，边读边算，不把整首歌载入内存
    /// 远程音频必须先异步加载音轨（loadTracks），同步 tracks 可能拿不到音轨
    private static func analyzeSync(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            return nil
        }
        guard let track = tracks.first else { return nil }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 22050,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }

        let samplesPerSecond = 22050
        var energies: [Double] = []
        var buffer: [Int16] = []
        var consumed = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var lengthAtOffset = 0
            var totalLength = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &pointer)
            guard let ptr = pointer, totalLength > 0 else { continue }
            let count = totalLength / MemoryLayout<Int16>.size
            ptr.withMemoryRebound(to: Int16.self, capacity: count) { p in
                buffer.append(contentsOf: UnsafeBufferPointer(start: p, count: count))
            }
            // 每凑满 1 秒计算一个 RMS 能量
            while buffer.count - consumed >= samplesPerSecond {
                var sum = 0.0
                for i in consumed..<(consumed + samplesPerSecond) {
                    let v = buffer[i]
                    sum += Double(v) * Double(v)
                }
                energies.append((sum / Double(samplesPerSecond)).squareRoot())
                consumed += samplesPerSecond
            }
            // 防止极端场景下内存膨胀（超过 8 分钟数据后丢弃已消费前缀）
            if consumed > samplesPerSecond * 480 {
                buffer.removeFirst(consumed)
                consumed = 0
            }
        }
        reader.cancelReading()

        // 至少 5 秒有效音频才可信
        guard energies.count >= 5 else { return nil }

        // 滑动窗口：能量最高的 20 秒窗口，取窗口中心作为高潮点
        let window = 20
        guard energies.count > window else {
            let peak = energies.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            return Double(peak)
        }
        var bestStart = 0
        var bestSum = energies.prefix(window).reduce(0, +)
        var running = bestSum
        for i in 1...(energies.count - window) {
            running = running - energies[i - 1] + energies[i + window - 1]
            if running > bestSum {
                bestSum = running
                bestStart = i
            }
        }
        return Double(bestStart + window / 2)
    }
}