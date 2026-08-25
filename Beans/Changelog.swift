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

    /// 日志按新到旧排列；每次发版在顶部追加一条
    static let logs: [VersionLog] = [
        VersionLog(
            id: "1.5.5",
            version: "1.5.5",
            title: "音频混合 / 灵动岛修复 / QQ歌单修复 / 汽水歌单修复",
            features: [
                "新增不打断其他音频开关（默认开启）：与其他 App 音频混合播放",
                "新增灵动岛实时活动开关（默认开启，iOS 16.1+ 生效）：播放时显示正在播放歌曲",
                "汽水音乐登录改为抖音授权：抖音网页版扫码 / 手机号登录后自动同步歌单",
                "汽水歌单同步接入 PC 网页版接口（创建 / 收藏）与 Luna App 歌单详情接口",
            ],
            fixes: [
                "修复灵动岛不显示：补全 NSSupportsLiveActivities 系统配置（此前开关无效）",
                "修复 QQ 主页歌单广场为空：改用 fcg_get_diss_by_tag 官方歌单广场接口",
                "修复 QQ 音乐歌单点开后歌曲列表为空：多组合重试 + 失败明确提示",
                "修复汽水音乐歌单列表与歌曲不显示：修正歌单列表路径与详情接口",
            ]
        ),
        VersionLog(
            id: "1.5.4",
            version: "1.5.4",
            title: "汽水网页登录修复 / 酷狗 VIP 播放 / 歌单错误提示",
            features: [
                "汽水音乐删除扫码登录，改为应用内网页登录并自动验证歌单同步",
            ],
            fixes: [
                "修复汽水音乐网页登录后歌单不同步：优先读取汽水官网 Cookie，兜底抖音 SSO",
                "修复酷狗会员歌曲播放失败：新增 H5 trackercdn 与 Android gateway 播放链路",
                "修复音乐库歌单加载失败显示空白：酷狗 / 汽水 / QQ 歌单错误可显示并重试",
            ]
        ),
        VersionLog(
            id: "1.5.3",
            version: "1.5.3",
            title: "汽水网页登录 / 平台记忆 / 板块自定义排序",
            features: [
                "汽水音乐新增应用内网页登录，扫码无反应时可网页登录自动同步登录态",
                "主页网易云 / QQ音乐平台选择记忆，下次进入沿用上次平台",
                "音乐库平台选择记忆，自动记住上次选择的平台",
                "主页与音乐库板块支持自定义排序，可拖动调整顺序并持久化",
            ],
            fixes: [
                "修复汽水音乐扫码确认后软件内无反应的问题（新增网页登录通道）",
            ]
        ),
        VersionLog(
            id: "1.5.2",
            version: "1.5.2",
            title: "修复酷狗歌单 / 壁纸恢复 / 汽水扫码与音乐库平台切换",
            features: [
                "汽水音乐扫码登录补齐设备指纹与 msToken 参数，提高扫码同步成功率",
                "音乐库平台切换改为固定等宽点击，不再横向滑动",
            ],
            fixes: [
                "修复酷狗音乐歌单不同步：兼容网页登录 Cookie 中的复合凭证（KuGoo / userid / token）",
                "修复备份恢复无法恢复壁纸：恢复后同步更新内存壁纸库与当前背景",
                "汽水音乐粘贴 Session 支持整段 Cookie 导入，自动提取登录态",
            ]
        ),

        VersionLog(
            id: "1.5.0",
            version: "1.5.0",
            title: "新增酷狗 / 汽水音乐登录与歌单同步",
            features: [
                "新增酷狗音乐登录：应用内网页登录或粘贴 Cookie，支持歌单同步",
                "新增汽水音乐登录：抖音 App 扫码登录或粘贴 sessionid，支持歌单同步",
                "音乐库平台切换升级为网易云 / QQ音乐 / 酷狗 / 汽水四平台",
                "账号中心整合四平台登录状态、昵称与 VIP / SVIP 标识",
            ],
            fixes: [
                "修复酷狗 / 汽水歌单在音乐库与歌单详情页无法加载的问题",
                "兼容旧版本地收藏数据：新增酷狗来源字段，历史数据自动兼容不丢失",
            ]
        ),

        VersionLog(
            id: "1.5.1",
            version: "1.5.1",
            title: "修复酷狗 / 汽水登录与 QQ 歌单封面",
            features: [
                "登录界面与首次引导页接入酷狗 / 汽水官方品牌图标",
                "汽水音乐扫码登录改用官方扫码链路，扫码确认后自动下发登录态",
            ],
            fixes: [
                "修复酷狗音乐歌单不同步、「我的喜欢」不显示的问题",
                "修复汽水音乐扫码后 404 无法登录的问题",
                "修复 QQ 音乐同步歌单封面一直加载的问题",
                "替换登录界面与引导页的酷狗 / 汽水非官方图标",
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
