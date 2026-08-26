import SwiftUI

// MARK: - 版本更新日志（每次发版追加一条，用于更新弹窗与设置内更新日志）

struct VersionLog: Identifiable {
    let id: String
    let version: String
    let title: String
    let features: [String]
    let fixes: [String]
}

enum ChangelogStore {
    static let lastSeenKey = "beans.lastSeenVersion"

    static var currentVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return short
    }

    static var lastSeenVersion: String {
        UserDefaults.standard.string(forKey: lastSeenKey) ?? ""
    }

    static func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }

    /// 版本更新后首次进入展示更新说明
    static var shouldShowWhatsNew: Bool {
        lastSeenVersion != currentVersion
    }

    static var latest: VersionLog? { logs.first }

    /// 日志按新到旧排列；本次只保留当前版本说明
    static let logs: [VersionLog] = [
        VersionLog(
            id: "1.4.3",
            version: "1.4.3",
            title: "新增内置咪咕音源，周杰伦等版权歌可正常播放",
            features: [
                "主页记住上次选择的平台（网易云 / QQ音乐），下次打开仍保持该平台",
                "圆形封面旋转默认开启，播放时封面自动匀速旋转",
                "底部「发现」改为「主页」，图标同步更新",
                "设置新增「底栏显示文字」开关：关闭后底栏只显示图标",
                "日志更详细：记录播放解析过程、音质、免费听歌状态、搜索结果数量，方便排查问题",
            ],
            fixes: [
                "新增内置咪咕音源：咪咕拥有周杰伦等版权歌官方 CDN 直链，会员歌自动用它播放原唱，无需导入",
                "修复 QQ 音乐有会员仍无法播放周杰伦等版权歌曲的问题",
                "修复 QQ 音乐搜索后播放的音频与原歌不符的问题（兜底匹配不再乱选歌曲）",
                "修复播放器设置界面上下滑动卡顿掉帧",
                "优化整体流畅度：加入 120Hz 高刷新率渲染、缓存全局字体读取",
            ]
        ),
    ]
}

// MARK: - 更新说明弹窗（每次升级首次进入展示）

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let log = ChangelogStore.latest {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Beans Music")
                                    .font(BeansFont.appFont(17, .bold))
                                    .foregroundStyle(Color.beansLabel)
                                Text("已更新至 \(log.version) · \(log.title)")
                                    .font(BeansFont.appFont(13))
                                    .foregroundStyle(Color.beansComment)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("新增功能")
                                    .font(BeansFont.appFont(14, .bold))
                                    .foregroundStyle(Color.beansAmber)
                                ForEach(log.features, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.beansAmber)
                                            .padding(.top, 2)
                                        Text(item)
                                            .font(BeansFont.appFont(13))
                                            .foregroundStyle(Color.beansLabel)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                if !log.fixes.isEmpty {
                                    Divider().overlay(Color.beansComment.opacity(0.15))
                                    Text("问题修复")
                                        .font(BeansFont.appFont(14, .bold))
                                        .foregroundStyle(Color.beansAmber)
                                    ForEach(log.fixes, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.beansAmber)
                                                .padding(.top, 2)
                                            Text(item)
                                                .font(BeansFont.appFont(13))
                                                .foregroundStyle(Color.beansLabel)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .beansCardShadow(radius: 9, y: 3)
                        }
                    }
                    .padding(16)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("更新说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始使用") {
                        ChangelogStore.markSeen()
                        dismiss()
                    }
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansAmber)
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large]))
    }
}

// MARK: - 设置内更新日志（汇聚每次更新内容）

struct ChangelogListView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ChangelogStore.logs) { log in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("v\(log.version)")
                                        .font(BeansFont.appFont(15, .bold))
                                        .foregroundStyle(Color.beansAmber)
                                    Text(log.title)
                                        .font(BeansFont.appFont(14, .semibold))
                                        .foregroundStyle(Color.beansLabel)
                                }
                                ForEach(log.features, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("·")
                                            .foregroundStyle(Color.beansComment)
                                        Text(item)
                                            .font(BeansFont.appFont(12))
                                            .foregroundStyle(Color.beansLabel)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                ForEach(log.fixes, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("·")
                                            .foregroundStyle(Color.beansAmber)
                                        Text(item)
                                            .font(BeansFont.appFont(12))
                                            .foregroundStyle(Color.beansLabel)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .beansCardShadow(radius: 8, y: 3)
                        }
                    }
                    .padding(16)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("更新日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large]))
    }
}

// MARK: - 软件使用说明

struct UsageGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, icon: String, lines: [String])] = [
        (
            "应用简介",
            "music.note.house.fill",
            [
                "Beans Music 是一款聚合网易云音乐、QQ 音乐与酷狗音乐资源的第三方音乐播放器客户端，旨在为您提供跨平台的音乐发现、搜索与播放体验。本应用仅供个人学习研究使用，禁止用于商业及非法用途。"
            ]
        ),
        (
            "多平台切换",
            "arrow.left.arrow.right",
            [
                "首页、搜索与音乐库顶部均可切换数据源平台。每日推荐、排行榜、歌单广场与搜索热榜会随平台切换展示对应内容。"
            ]
        ),
        (
            "账号服务",
            "person.crop.circle.badge.checkmark",
            [
                "「我的」页面支持网易云、QQ 音乐与酷狗音乐账号登录（扫码 / 网页授权）。登录后自动同步各平台歌单、收藏与 VIP 标识，享受完整播放权益。"
            ]
        ),
        (
            "播放体验",
            "play.circle.fill",
            [
                "全屏播放器支持点击封面切换歌词视图，进度条可点击或拖动跳转，支持倍速、定时关闭、循环模式与音质选择。歌词支持发光、渐变、自定义颜色与位置调节。"
            ]
        ),
        (
            "个性化定制",
            "paintpalette.fill",
            [
                "支持上传自定义壁纸、全局主题色、底部布局自由调整（拖动组件到任意位置），让播放器界面更贴合您的审美。"
            ]
        ),
        (
            "使用提示",
            "lightbulb.fill",
            [
                "播放器右上角「更多」菜单集中管理定时关闭、下载、音质等次要功能；「我的」右上角设置包含外观、播放与更新日志。",
                "遇到播放异常时，可尝试切换音源平台或检查账号登录状态。"
            ]
        )
    ]

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.beansAmber)
                                    Text(section.title)
                                        .font(BeansFont.appFont(14, .bold))
                                        .foregroundStyle(Color.beansLabel)
                                }
                                ForEach(section.lines, id: \.self) { line in
                                    Text(line)
                                        .font(BeansFont.appFont(12.5))
                                        .foregroundStyle(Color.beansLabel.opacity(0.85))
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .beansCardShadow(radius: 8, y: 3)
                        }
                        Text("Beans Music · 仅供学习交流，纯 AI 实现此应用 · 接入网易云音乐、QQ 音乐等公开接口")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("软件使用说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.large]))
    }
}
