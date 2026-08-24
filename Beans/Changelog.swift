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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
            id: "1.9.8",
            version: "1.9.8",
            title: "QQ 歌单同步修复 · 音乐库精简",
            features: [
                "QQ 音乐歌单同步升级（借鉴 Mineradio）：同时拉取「创建的歌单 + 收藏的歌单」并合并去重，喜欢的歌单排最前",
                "QQ 昵称显示优化：登录后优先从资料接口 / ptnick Cookie 拉取真实昵称",
                "音乐库精简：移除「QQ 我喜欢」「酷狗音乐收藏」区块，仅保留歌单同步",
            ],
            fixes: [
                "修复 QQ 音乐歌单不同步：改用 fcg_user_created_diss + fcg_get_profile_order_asset 双接口",
                "酷狗创建 / 删除歌单增加网页版表单接口与 mobilecdn 双通道，提高成功率",
            ]
        ),
        VersionLog(
            id: "1.9.7",
            version: "1.9.7",
            title: "歌单修复 · 布局缩放 · 封面旋转",
            features: [
                "自定义底部布局新增「大小」滑杆：进度条 / 控制按钮 / 歌词 / 指示线均可单独缩放（0.6x ~ 1.5x）",
                "播放器设置新增「圆形封面旋转」开关（默认关闭），开启后播放时封面匀速旋转、暂停即停",
                "酷狗音乐支持创建 / 删除歌单，与账号同步",
            ],
            fixes: [
                "修复 QQ 音乐创建歌单「解析错误」：兼容 while(1); / JSONP 响应，code 宽松解析",
                "修复 QQ 音乐歌单不同步：用户歌单接口补充 g_tk / utf8 参数并兼容多种响应结构",
                "我的界面账号信息显示真实昵称：QQ 音乐 / 酷狗音乐登录后自动拉取昵称展示",
            ]
        ),
        VersionLog(
            id: "1.9.6",
            version: "1.9.6",
            title: "圆形封面 · 歌手页优化",
            features: [
                "新增圆形封面模式：播放器封面与歌词页左上角封面显示为圆形（播放器设置可开关）",
                "歌手主页新增「播放全部」「随机播放」",
            ],
            fixes: [
                "优化歌手主页排版间距，更紧凑",
                "修复底栏切换时搜索页每次重新加载热门搜索的问题",
            ]
        ),
        VersionLog(
            id: "1.9.5",
            version: "1.9.5",
            title: "布局调整修复",
            features: [
                "布局调整弹窗下移至封面下方，不遮挡顶栏",
            ],
            fixes: [
                "修复指示线 X/Y 滑块调整无效（拖动与滑块数据已同步）",
                "移除布局编辑时的全部黄色描边，界面更清爽",
            ]
        ),
        VersionLog(
            id: "1.9.4",
            version: "1.9.4",
            title: "注释配色 · 布局优化",
            features: [
                "新增「注释文字颜色」：我的 → 外观可自定义全 App 说明文字颜色",
                "布局调整：指示线可直接拖动，位置与滑块联动同步",
            ],
            fixes: [
                "修复布局调整弹窗触摸穿透问题",
                "播放器设置「布局调整」分区重组，消除说明文字下方空白",
                "移除布局编辑时指示线的描边，界面更清爽",
            ]
        ),
        VersionLog(
            id: "1.9.1",
            version: "1.9.1",
            title: "布局整合 · 个性化升级",
            features: [
                "播放器「布局调整」弹窗新增「歌词」「指示线」组件，可分别微调歌词与指示线位置",
                "播放器「布局调整」整合底部组件与歌词位置调节，集中管理更顺手",
                "新增歌词自定义发光颜色，色盘随心搭配",
                "底部指示线新增开关，可自由选择是否显示",
                "新增软件使用说明与更新日志，每次升级自动弹出更新说明",
            ],
            fixes: [
                "关闭底部指示线后仍可在原位置上滑呼出评论区",
                "音乐库网易云「我的歌单」未登录时显示引导文案，与 QQ / 酷狗保持一致",
            ]
        ),
        VersionLog(
            id: "1.9",
            version: "1.9",
            title: "歌词布局编辑",
            features: [
                "歌词新增位置调节与样式：居中 / 全部居左、水平偏移、垂直重心",
                "开启自定义底部布局后自动回到播放页，直接拖动调节",
                "歌词翻译默认开启，设置入口统一收拢到播放器",
            ],
            fixes: [
                "纯音乐等少行歌词不再贴顶，垂直居中显示",
                "进度条发光圆润化，消除生硬方边",
            ]
        ),
        VersionLog(
            id: "1.8",
            version: "1.8",
            title: "排行榜收缩 · 布局自由调整",
            features: [
                "排行榜收缩显示：收起只显示前三，展开可见前十",
                "播放器底部 UI 自由调整：拖动组件到任意位置，支持恢复默认",
                "波浪进度条升级辉光渐变效果",
            ],
            fixes: [
                "进入软件后自动刷新，避免首页显示无网络",
            ]
        ),
        VersionLog(
            id: "1.7",
            version: "1.7",
            title: "免责声明优化 · 榜单精简",
            features: [
                "首次进入使用原生免责声明确认弹窗，背景模糊透出主界面",
                "排行榜统一只显示前十个榜单",
            ],
            fixes: [
                "修复首次启动卡在初始化页面的问题",
            ]
        ),
    ]
}

// MARK: - 更新说明弹窗（每次升级首次进入展示）

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                .scrollIndicators(.hidden)
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
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 设置内更新日志（汇聚每次更新内容）

struct ChangelogListView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                .scrollIndicators(.hidden)
            }
            .navigationTitle("更新日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
        NavigationStack {
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
                        Text("Beans Music · 仅供学习交流，纯 AI 实现此应用 · 接入网易云音乐、QQ 音乐、酷狗音乐等公开接口")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("软件使用说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
