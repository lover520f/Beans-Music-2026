import SwiftUI
import UIKit

/// 应用图标管理
/// - 系统预设图标：通过 UIApplication.setAlternateIconName 一键切换（iOS 10.3+，仅支持 App 内置图标）
/// - 自定义图标：用户上传图片保存到沙盒，作为软件内图标（引导页等）展示
@MainActor
final class AppIconStore: ObservableObject {
    static let shared = AppIconStore()

    struct PresetIcon: Identifiable, Equatable {
        let id: String
        /// setAlternateIconName 的 key；nil 表示恢复系统主图标
        let iconName: String?
        let title: String
        let imageName: String
    }

    static let presets: [PresetIcon] = [
        PresetIcon(id: "default", iconName: nil, title: "默认", imageName: "AppIcon"),
        PresetIcon(id: "neon", iconName: "AppIconNeon", title: "赛博霓虹", imageName: "AppIconNeon"),
        PresetIcon(id: "pink", iconName: "AppIconPink", title: "蜜桃粉", imageName: "AppIconPink"),
        PresetIcon(id: "gold", iconName: "AppIconGold", title: "鎏金", imageName: "AppIconGold")
    ]

    /// 当前系统预设图标名（nil = 默认主图标）
    @Published private(set) var presetIconName: String?
    /// 用户上传的自定义图标文件 URL（nil = 未上传）
    @Published private(set) var customIconURL: URL?

    static let presetKey = "beans.appIconPreset"
    static let customIconFileName = "beans.customAppIcon.png"

    private init() {
        presetIconName = UserDefaults.standard.string(forKey: Self.presetKey)
        customIconURL = Self.customIconFileURL()
    }

    /// 当前选中的预设（默认主图标）
    var currentPreset: PresetIcon {
        Self.presets.first { $0.iconName == presetIconName } ?? Self.presets[0]
    }

    /// 用户自定义图标的 UIImage（软件内展示）
    var customIconImage: UIImage? {
        guard let url = customIconURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// 切换系统预设图标（真机桌面图标立即生效）
    func applyPreset(_ preset: PresetIcon) {
        guard presetIconName != preset.iconName else { return }
        UIApplication.shared.setAlternateIconName(preset.iconName) { error in
            Task { @MainActor in
                if let error {
                    ToastCenter.shared.show("图标切换失败：\(error.localizedDescription)")
                } else {
                    self.presetIconName = preset.iconName
                    UserDefaults.standard.set(preset.iconName, forKey: Self.presetKey)
                    BeansHaptics.success()
                }
            }
        }
    }

    /// 保存用户上传的自定义图标（软件内展示用）
    @discardableResult
    func saveCustomIcon(_ data: Data) -> Bool {
        guard let dir = Self.customIconDirectory() else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(Self.customIconFileName)
            try data.write(to: url, options: .atomic)
            customIconURL = url
            return true
        } catch {
            return false
        }
    }

    /// 移除自定义图标
    func removeCustomIcon() {
        guard let url = customIconURL else { return }
        try? FileManager.default.removeItem(at: url)
        customIconURL = nil
    }

    // MARK: - 文件位置

    static func customIconDirectory() -> URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    static func customIconFileURL() -> URL? {
        guard let dir = customIconDirectory() else { return nil }
        let url = dir.appendingPathComponent(customIconFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
