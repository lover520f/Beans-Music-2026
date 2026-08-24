import SwiftUI

// MARK: - 播放器底部 UI 自由调整（x / y / z）

/// 可自由调整的底部组件
enum PlayerLayoutPart: String, CaseIterable, Identifiable {
    case progress = "进度条"
    case controls = "控制按钮"
    case lyric = "歌词"
    case grabber = "指示线"

    var id: String { rawValue }
}

/// 单个组件的自定义位置（相对默认位置的偏移）
struct PlayerLayoutEntry: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
}

/// 播放器底部布局调整存储（UserDefaults JSON，持久化）
enum PlayerLayoutStore {
    static let modeKey = "beans.playerLayoutMode"
    static let dataKey = "beans.playerLayoutData"

    static func load() -> [String: PlayerLayoutEntry] {
        guard let raw = UserDefaults.standard.string(forKey: dataKey),
              let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: PlayerLayoutEntry].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func save(_ dict: [String: PlayerLayoutEntry]) {
        if let data = try? JSONEncoder().encode(dict),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: dataKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: dataKey)
    }
}

/// 让组件可自由拖动并应用自定义位置（x / y 偏移 + z 层级）
struct Layoutable: ViewModifier {
    let part: PlayerLayoutPart
    /// 编辑模式开关：开启时可拖动，未开启时完全无影响
    let enabled: Bool
    /// 布局数据（双向绑定，实时保存）
    @Binding var data: [String: PlayerLayoutEntry]

    func body(content: Content) -> some View {
        let entry = data[part.rawValue] ?? PlayerLayoutEntry()
        content
            .offset(x: entry.x, y: entry.y)
            .overlay(alignment: .topLeading) {
                if enabled {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.beansAmber.opacity(0.9), lineWidth: 1.5)
                        .padding(-7)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                enabled
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            var e = data[part.rawValue] ?? PlayerLayoutEntry()
                            e.x = value.translation.width
                            e.y = value.translation.height
                            data[part.rawValue] = e
                        }
                    : nil
            )
    }
}
