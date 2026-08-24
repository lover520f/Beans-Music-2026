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
            id: "1.9.20",
            version: "1.9.20",
            title: "恢复播放器液态玻璃底栏面板",
            features: [
                "播放器底部控制区恢复 iOS 26 原生液态玻璃底栏面板：进度条 / 控制按钮 / 指示线统一收纳进玻璃面板，歌词滑入面板下方后由玻璃层模糊遮盖，不再直接透出",
                "底栏跟随全局 液态玻璃 / 磨砂玻璃 设置，深浅模式自适应",
            ],
            fixes: []
        ),
        VersionLog(
            id: "1.9.19",
            version: "1.9.19",
            title: "回到 1.9.10 功能状态 · 保留指定功能",
            features: [
                "播放器功能恢复 1.9.10 基础状态，仅保留以下功能：抖音式切歌、歌词模糊调节（起始距离 0~10 行 + 强度）、咪咕音源（默认关闭可独立开关）、播放失败提示更明确",
                "保留布局调整悬浮窗实时预览（歌词字号 / 显示多少 / 对齐 / 模糊 / 发光边调边看）与播放器设置「播放 / 歌词显示 / 歌词效果 / 布局 / 封面」五大板块",
                "保留悬浮窗预览滑杆始终显示、网易云扫码登录成功后二维码自动收起",
                "移除下载即分享（下载恢复保存到本地文件 App）、液态玻璃底栏等 1.9.14 之后新增内容，底部控件保持悬浮在模糊背景上的原始样式",
            ],
            fixes: []
        ),
        VersionLog(
            id: "1.9.13",
            version: "1.9.13",
            title: "修复播放器按钮穿透 · 扫码登录自动收起",
            features: [
                "布局调整悬浮窗实时预览升级：歌词字号 / 显示多少 / 对齐 / 模糊 / 发光滑杆始终显示，不再只有一个进度条样式",
                "网易云扫码登录成功后二维码区域自动收起，无需手动下拉关闭",
            ],
            fixes: [
                "修复播放器顶栏 / 底栏按钮点击穿透无反应：回退歌词页全屏悬浮结构，顶栏与底部控制按钮恢复可正常点击",
                "移除歌词页顶部黑色渐变与大片空白区域",
                "回退底部组件默认偏移（进度条 / 控制按钮 / 指示线恢复默认位置），避免遮挡导致按钮无法点击",
            ]
        ),
        VersionLog(
            id: "1.9.12",
            version: "1.9.12",
            title: "悬浮窗实时调节 · 播放器设置整合 · 顶部歌词透出",
            features: [
                "播放器布局调整升级为悬浮窗实时预览：选择「歌词」可直接调字号 / 显示多少 / 对齐 / 模糊 / 发光，选择「进度条」可实时切换样式与光晕强度，边调边看不用再切设置面板",
                "播放器设置重新整合为「播放 / 歌词显示 / 歌词效果 / 布局 / 封面」五大板块，不再散乱",
                "顶部歌词透出背景：歌词页改为全屏滚动，歌词可滚到顶栏玻璃下方透出显示，新增「顶部显示」留白调节",
                "底部组件默认布局按需求调整：进度条 Y116、控制按钮 Y22 1.2 倍、指示线 Y-57 0.85 倍",
            ],
            fixes: [
                "修复调整歌词等播放器设置时看不到实时效果的问题：所有调节都在悬浮窗中边调边预览",
            ]
        ),
        VersionLog(
            id: "1.9.11",
            version: "1.9.11",
            title: "刷抖音切歌动画 · 歌词显示调节 · 音源开关全可控",
            features: [
                "刷抖音式切歌升级动画：上滑旧封面飞出、新封面从底部滑入；下滑反向，过渡更接近短视频翻页",
                "歌词显示调节：新增上下留白滑杆，歌词显示更多 / 更少可自由调整；歌词可滚到控制栏玻璃下方透出显示",
                "歌词模糊起始距离范围放开（0~10 行），配合强度可调出更柔和的渐隐效果",
                "咪咕直连纳入音源开关：新增「咪咕音源」（周杰伦等版权歌曲官方 CDN 直链），与其余音源一样默认关闭、可独立控制",
            ],
            fixes: [
                "修复播放器上滑切歌时误触封面跳转歌词页：滑动改为与封面点击互斥的手势，拖动不再触发轻点",
                "播放失败提示更明确：区分「未开启免费听歌」与「音源未命中」，不再笼统显示未找到原唱音源",
            ]
        ),
        VersionLog(
            id: "1.9.10",
            version: "1.9.10",
            title: "第三方音源默认关闭 · 抖音式切歌 · 歌词模糊调节",
            features: [
                "第三方音源默认关闭：首次安装后 pyncmd / 酷我 / 波点音源默认不启用，需在「我的 → 设置 → 音源」手动开启",
                "抖音式切歌融入播放器：专辑界面上下滑动即可像刷视频一样切歌（上滑下一首、下滑上一首），不再需要单独页面",
                "歌词模糊可调：新增模糊起始距离与强度调节，可自行决定歌词从第几行开始模糊、模糊多重，0 强度可完全关闭",
                "播放器封面下预览歌词多显示一行；歌词页上下各多露出一行歌词，看得更多",
                "QQ 歌单封面兜底：歌单没有封面时自动取第一首歌曲封面展示",
            ],
            fixes: [
                "修复酷我音源播放错误音频：酷我 antiserver 现对全部歌曲返回同一个占位提示音（\"请去酷我音乐手机版播放\"），已识别并自动跳过，不再播放错误声音",
                "修复周杰伦等版权歌曲播放：登录 QQ 音乐 VIP/SVIP 账号后优先使用 vkey 官方完整音轨，未登录才走网易云同名兜底",
                "修复 QQ 歌单每次进入都重新加载：会话内缓存 5 分钟，下拉可强制刷新",
                "修复音乐库最近播放\"正在播放\"图标乱跳：所有歌曲列表改用跨平台唯一标识（网易云 / QQ 同 id 不再串行）",
            ]
        ),
        VersionLog(
            id: "1.9.9",
            version: "1.9.9",
            title: "抖音模式 · DJ 视觉 · 本地音乐库 · 落雪音源",
            features: [
                "新增刷抖音模式：主页右上角与播放器更多菜单进入，竖向翻页浏览歌曲、上滑/下滑切歌",
                "新增 DJ 视觉模式：播放器封面背后随节拍扩散的光环与环绕彩带（播放器设置可开关、可调强度）",
                "新增本地音乐库：设备本机歌单，可新建 / 重命名 / 删除 / 播放 / 搜索添加歌曲，覆盖安装不丢失",
                "接入落雪音乐源：第三方音源导入支持 lx-music-api-server 格式，播放 VIP 歌曲时自动搜索取流",
            ],
            fixes: [
                "修复 QQ 音乐歌单封面一直加载：fcg 接口返回的相对路径封面自动补全 y.gtimg.cn 域名",
                "修复 QQ 音乐歌单点开不显示歌曲：歌单详情改用 fcg_ucc_getcdinfo_byids_cp 主通道并兼容 track_info 包裹结构",
                "全面移除酷狗音乐相关功能（登录 / 歌单 / 搜索 / 排行 / 音源），精简体积与维护成本",
            ]
        ),
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
                        Text("Beans Music · 仅供学习交流，纯 AI 实现此应用 · 接入网易云音乐、QQ 音乐等公开接口")
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
