import SwiftUI

/// 导入第三方解锁源：粘贴 JSON 配置，解析后保存到音源库
struct ThirdPartySourceImportSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UnblockSourceStore.shared

    @State private var jsonText = ""
    @State private var errorMessage: String?

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("粘贴第三方解锁源 JSON 配置")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansLabel)
                HStack(spacing: 8) {
                    Button {
                        jsonText = #"""
                        {
                          "name": "落雪音乐源",
                          "kind": "lx",
                          "template": "https://你的服务器地址",
                          "urlPath": "url",
                          "headers": { "source": "kg", "br": "320" }
                        }
                        """#
                        errorMessage = nil
                    } label: {
                        Text("落雪音乐源" + (jsonText.contains("\"kind\": \"lx\"") ? " ✓" : ""))
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(jsonText.contains("\"kind\": \"lx\"") ? Color.beansAmber : Color.beansLabel)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.beansGlassFill))
                    }
                    .buttonStyle(.plain)
                    Button {
                        jsonText = #"""
                        {
                          "name": "我的音源",
                          "kind": "keyword",
                          "template": "https://api.example.com/music?keyword={keyword}",
                          "urlPath": "data.url"
                        }
                        """#
                        errorMessage = nil
                    } label: {
                        Text("通用音源示例")
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(Color.beansLabel)
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
                Text("字段：name 名称；kind 查询方式（netease-id 按网易云 ID / keyword 按关键词 / lx 落雪 API 服务器）；template 请求模板；urlPath 响应里播放地址的字段路径（如 url、data.url）；headers 可选请求头。\n占位符：{id} 网易云ID、{name} 歌名、{artist} 歌手、{keyword} 歌名+歌手。\n落雪（kind 填 lx）：template 填 lx-music-api-server 的服务器地址，headers 里 source 可选 wy/kg/qq/mg/tx，br 可选 320/128。播放时自动搜索并取流。")
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
    }

    private func importSource() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请先粘贴 JSON 配置"
            return
        }
        guard let data = trimmed.data(using: .utf8),
              let source = try? JSONDecoder().decode(ThirdPartySource.self, from: data),
              !source.template.isEmpty else {
            errorMessage = "JSON 解析失败，请检查格式（name / template / urlPath 必填）"
            return
        }
        store.add(source)
        BeansHaptics.success()
        dismiss()
    }
}
