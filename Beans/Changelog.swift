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
            id: "1.4.0",
            version: "1.4.0",
            title: "第三方音源重做：仅支持导入 + 独立开关 + 自检",
            features: [
                "移除全部内置第三方音源（GD 音乐台 / 酷我 / 波点 / 咪咕直连），第三方音源仅支持用户导入",
                "导入的第三方音源支持独立开启 / 关闭，关闭后播放时自动跳过",
                "第三方音源列表新增「自检」按钮：一键验证音源能否取到播放地址，失败时显示真实原因",
            ],
            fixes: [
                "优化「未找到原唱音频」提示：QQ VIP 歌曲未开启「免费听歌」时明确提示开启位置",
                "修复 LX 脚本音源取流失败原因被吞掉的问题，失败详情写入日志可精确定位",
                "未导入或未开启第三方音源时，提示先导入并开启音源",
            ]
        ),

        VersionLog(
            id: "1.3.5",
            version: "1.3.5",
            title: "QQ 播放音源修复",
            features: [],
            fixes: [
                "修复 QQ 音乐播放与原版不一致的问题：未开启「免费听歌」时仅播放官方音源",
                "关闭「免费听歌」后不再静默改用网易云 / 第三方音源",
                "修复开启免费听歌时网易云同名匹配可能误播无关歌曲的问题",
            ]
        ),

        VersionLog(
            id: "1.3.4",
            version: "1.3.4",
            title: "落雪 JS 音源直跑 + 登录页改版 + 搜索历史 + 日志",
            features: [
                "导入第三方音源支持直接选择 .js / .json / .txt 文件，自动提取 JS 中的 JSON 配置，一个文件可包含多个音源",
                "落雪 LX 脚本音源直接导入运行：星海、全豆要等 JS 音源文件由内置 JS 引擎执行，自动搜索歌曲并取流播放",
                "搜索界面新增历史搜索：自动记录、点击重搜、单条删除与一键清空",
                "设置备份升级：同时备份壁纸库、字体文件与本地歌单，恢复后自动重建",
                "新增日志功能：记录搜索、播放、下载、登录、导入、备份等关键事件，可查看、导出分享或导入日志文件，方便反馈 Bug",
                "下载歌曲不再自动保存到本地：下载完成直接弹出系统原生分享，可自行选择保存到文件或转发给朋友",
                "播放页「加入本地歌单」改为歌单选择弹窗，可直接选择已创建的本地歌单或新建并加入",
                "检查更新自动下载新版 IPA：下载完成后直接呼出系统原生分享面板，自行选择保存位置或转发，不再固定存到本地",
                "网易云登录页改版：网页 / 扫码分栏选择，网页登录底部提示可直接使用网页手机号登录",
                "圆形封面旋转改为默认开启，无需手动打开",
                "移除 QQ 扫码登录，保留网页登录与粘贴 Cookie",
            ],
            fixes: [
                "修复导入落雪 LX 脚本音源提示不支持的问题：现在可直接导入并运行 JS 脚本音源",
                "导入解析兼容带 BOM 的 JSON 文件",
                "设置页「备份与恢复」「日志」板块统一改为液态玻璃质感",
                "移除第三方音源导入页的「落雪音乐源」「通用音源示例」预设示例",
            ]
        ),

        VersionLog(
            id: "1.3.3",
            version: "1.3.3",
            title: "关于页新增免费开源提示",
            features: [
                "关于页新增提示：本软件完全免费，全部功能开源于 GitHub",
            ],
            fixes: []
        ),

        VersionLog(
            id: "1.3.2",
            version: "1.3.2",
            title: "检查更新自动下载新版 IPA",
            features: [
                "检查更新后自动下载新版 IPA：检测到新版本直接下载到「文件」App → Beans → Downloads，无需跳转浏览器",
                "下载或检查失败时提示可能需要特殊网络环境（代理 / VPN）",
                "iOS 26 以下系统隐藏「液态玻璃 / 磨砂玻璃」切换开关，低版本自动使用磨砂玻璃",
            ],
            fixes: []
        ),

        VersionLog(
            id: "1.3.1",
            version: "1.3.1",
            title: "兼容 iOS 15 低版本系统",
            features: [
                "兼容 iOS 15+ 低版本系统：iOS 15 / 16 均可正常运行，液态玻璃自动回退磨砂玻璃",
            ],
            fixes: [
                "引导登录第一页更换为 Beans 专属图标",
                "修复相册上传壁纸在低版本系统无法使用的问题",
            ],
        ),

        VersionLog(
            id: "1.2.2",
            version: "1.2.2",
            title: "自动检测更新 + 兼容 iOS 16 低版本",
            features: [
                "自动检测更新：启动时静默检查 GitHub 最新版本，发现新版弹出提示，可一键前往下载",
                "「我的」页面底部新增「更新地址」与「检查更新」入口，可随时手动检测",
                "兼容 iOS 16+ 低版本系统：液态玻璃自动回退磨砂玻璃，低版本也能正常使用",
            ],
            fixes: []
        ),

        VersionLog(
            id: "1.1.1",
            version: "1.1.1",
            title: "首次使用引导 + 网易云网页登录 + 歌词倾斜",
            features: [
                "首次使用引导式登录：新用户安装后先浏览 4 页引导（欢迎、DIY 美化、双平台、免责确认），再进入软件",
                "网易云网页登录：应用内打开网页版完成登录，支持扫码 / 手机号，自动同步账号与歌单",
                "歌词倾斜角度：新增 3D 立体倾斜（后仰 + 左右倾斜），角度自由调节，营造立体透视感",
                "覆盖安装新版本后首次进入，自动展示本版本更新说明（仅弹一次，设置内可随时查看历史更新日志）",
                "设置配置备份与恢复：一键导出全部自定义配置（主题、配色、歌词效果、播放器布局、音质等）为 JSON 文件，支持导入恢复",
            ],
            fixes: []
        ),

        VersionLog(
            id: "1.0",
            version: "1.0",
            title: "欢迎使用 Beans Music",
            features: [
                "欢迎使用 Beans Music，感谢你的支持！",
                "聚合网易云 / QQ 音乐 / 酷狗音乐：扫码登录即可同步歌单、收藏与 VIP 标识",
                "歌词滚动与翻译、自定义歌词颜色 / 渐变 / 发光，打造专属播放体验",
                "液态玻璃界面、抖音式切歌、动态封面取色、播放排行等丰富功能",
                "本软件仅供个人学习研究使用，音乐版权归各平台所有，请支持正版",
            ],
            fixes: []
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
