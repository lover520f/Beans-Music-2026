import SwiftUI
import UniformTypeIdentifiers

/// 导入第三方解锁源：粘贴 JSON / JS 配置，或直接从 .js / .json / .txt 文件导入，解析后保存到音源库
struct ThirdPartySourceImportSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UnblockSourceStore.shared

    @State private var jsonText = ""
    @State private var errorMessage: String?
    @State private var showFilePicker = false

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("粘贴或导入第三方解锁源配置（支持 JSON / JS 文件）")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansLabel)
                HStack(spacing: 8) {
                    Button {
                        BeansHaptics.tap()
                        showFilePicker = true
                    } label: {
                        Label("从文件导入 JS / JSON", systemImage: "folder")
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.beansGlassFill))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                TextEditor(text: $jsonText)
                    .font(.system(size: 12, design: .monospaced))
                    .beansScrollContentBackgroundHidden()
                    .padding(8)
                    .frame(minHeight: 150)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.beansGlassFill))
                if let errorMessage {
                    Text(errorMessage)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(.red)
                }
                Text("字段：name 名称；kind 查询方式（netease-id 按网易云 ID / keyword 按关键词 / lx 落雪 API 服务器）；template 请求模板；urlPath 响应里播放地址的字段路径（如 url、data.url）；headers 可选请求头。\n占位符：{id} 网易云ID、{name} 歌名、{artist} 歌手、{keyword} 歌名+歌手。\n落雪（kind 填 lx）：template 填 lx-music-api-server 的服务器地址，headers 里 source 可选 wy/kg/qq/mg/tx，br 可选 320/128。播放时自动搜索并取流。\n支持直接选择 .js / .json / .txt 文件导入：JS 文件会先尝试提取内嵌的 JSON 配置；若识别为落雪 LX 脚本音源（如星海、全豆要等聚合音源），将直接导入并用内置 JS 引擎运行。导入后可在「设置 → 第三方音源」中独立开关；播放时需先开启「免费听歌」开关。")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                Button {
                    importSource()
                } label: {
                    Text("导入")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.beansAmber))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("导入第三方源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showFilePicker) {
            SourceFilePicker { url in
                importFromFile(url)
            }
            .ignoresSafeArea()
        }
    }

    /// 粘贴内容导入（支持单个音源或 JSON 数组）
    private func importSource() {
        let text = jsonText
        let sources = parseSources(text)
        if !sources.isEmpty {
            for source in sources { store.add(source) }
            BeansLogger.shared.log("导入第三方音源 \(sources.count) 个：\(sources.map(\.name).joined(separator: "、"))", level: .info)
            BeansHaptics.success()
            ToastCenter.shared.show(sources.count > 1 ? "已导入 \(sources.count) 个音源" : "已导入「\(sources.first?.name ?? "")」")
            dismiss()
            return
        }
        if Self.looksLikeLXScript(text) {
            let name = Self.lxScriptName(from: text) ?? "落雪音源脚本"
            store.add(ThirdPartySource(name: name, kind: "lxscript", template: "", script: text))
            BeansLogger.shared.log("导入落雪 LX 脚本音源：\(name)", level: .info)
            BeansHaptics.success()
            ToastCenter.shared.show("已导入「\(name)」（LX 脚本音源）")
            dismiss()
            return
        }
        errorMessage = Self.friendlyParseError(text)
    }

    /// 从文件导入：读取文本后走同一套解析
    private func importFromFile(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "读取文件失败，请选择 .js / .json / .txt 文件"
            return
        }
        jsonText = text
        let sources = parseSources(text)
        if !sources.isEmpty {
            for source in sources { store.add(source) }
            BeansLogger.shared.log("从文件导入第三方音源 \(sources.count) 个：\(url.lastPathComponent)", level: .info)
            BeansHaptics.success()
            ToastCenter.shared.show(sources.count > 1 ? "已导入 \(sources.count) 个音源" : "已导入「\(sources.first?.name ?? "")」")
            dismiss()
            return
        }
        if Self.looksLikeLXScript(text) {
            let name = Self.lxScriptName(from: text) ?? url.deletingPathExtension().lastPathComponent
            store.add(ThirdPartySource(name: name, kind: "lxscript", template: "", script: text))
            BeansLogger.shared.log("从文件导入落雪 LX 脚本音源：\(name)", level: .info)
            BeansHaptics.success()
            ToastCenter.shared.show("已导入「\(name)」（LX 脚本音源）")
            dismiss()
            return
        }
        errorMessage = Self.friendlyParseError(text)
    }

    /// 解析失败时的友好提示：识别落雪 LX 脚本源等常见情况
    private static func friendlyParseError(_ text: String) -> String {
        if looksLikeLXScript(text) {
            return "已识别为落雪 LX 脚本音源，但脚本内容不完整，无法运行。请重新选择完整的 JS 音源文件导入。"
        }
        return "未找到可用的音源配置。支持：JSON 对象 / JSON 数组、JS 文件内嵌 JSON 配置，或直接导入落雪 LX 脚本音源（JS 文件）。"
    }

    /// 从 LX 脚本头部注释提取 @name 作为音源名
    private static func lxScriptName(from text: String) -> String? {
        guard let range = text.range(of: "@name\\s+([^\\r\\n*]+)", options: .regularExpression) else { return nil }
        let name = text[range]
            .replacingOccurrences(of: "@name", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 检测是否为落雪音乐 LX 脚本音源（JS 程序：含 @name 头注释、EVENT_NAMES / httpFetch 等协议特征）
    private static func looksLikeLXScript(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("@name"), lower.contains("音源") || lower.contains("音乐源") { return true }
        if lower.contains("event_names"),
           lower.contains("httpfetch") || lower.contains("musicsearch") || lower.contains("musicsource") { return true }
        return false
    }

    /// 解析音源列表：支持单个 JSON 对象、JSON 数组、以及从 JS 代码中提取 JSON
    private func parseSources(_ text: String) -> [ThirdPartySource] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        if let list = try? JSONDecoder().decode([ThirdPartySource].self, from: data), !list.isEmpty {
            return list
        }
        if let single = try? JSONDecoder().decode(ThirdPartySource.self, from: data) {
            return [single]
        }
        // JS 文件：提取第一对 {} 或 [] 之间的内容再解析（module.exports = {...} 等常见写法）
        for pair in [("{", "}"), ("[", "]")] as [(Character, Character)] {
            guard let first = trimmed.firstIndex(of: pair.0), let last = trimmed.lastIndex(of: pair.1), first < last else { continue }
            let start = trimmed.index(after: first)
            let end = trimmed.index(before: last)
            let sub = String(trimmed[start...end])
            guard let subData = sub.data(using: .utf8) else { continue }
            if let list = try? JSONDecoder().decode([ThirdPartySource].self, from: subData), !list.isEmpty {
                return list
            }
            if let single = try? JSONDecoder().decode(ThirdPartySource.self, from: subData) {
                return [single]
            }
        }
        return []
    }
}

// MARK: - 音源文件选择器（UIDocumentPicker 封装，可选 .js / .json / .txt）

struct SourceFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SourceFilePicker
        init(_ parent: SourceFilePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
