# Beans Music 🎵

> 一款基于 **iOS 26 原生液态玻璃（Liquid Glass）** 的第三方音乐播放器，聚合网易云音乐与 QQ 音乐，纯 SwiftUI 实现。
> 本软件完全开源，仅供学习研究使用。

[![GitHub Pages 预览](https://img.shields.io/badge/在线预览-GitHub%20Pages-blue)](https://xiaodou0416.github.io/Beans-Music/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%2026+-orange)]()
[![Swift](https://img.shields.io/badge/Swift-5-orange)]()

**👀 在线预览（HTML 介绍页）：** https://xiaodou0416.github.io/Beans-Music/

---

## 🚀 它有多强大？

**双平台聚合，一个 App 听遍网易云 + QQ 音乐**
- 网易云 / QQ 音乐一键切换：每日推荐、排行榜、推荐歌单、搜索、热门搜索全部跟随平台
- 网易云：扫码登录 + 应用内网页登录，同步歌单、收藏、听歌排行与 VIP / SVIP 标识
- QQ 音乐：扫码授权 + 网页登录 / Cookie 导入，同步歌单与 VIP 标识
- 双平台歌曲评论区、歌词、歌手主页互通

**播放器：从封面里长出来的界面**
- 动态封面取色：背景渐变、进度条、播放按钮、功能按钮、歌词高亮全部实时跟随专辑封面主色
- 封面点击切换歌词视图（封面飞入左上角动画）、圆形封面模式 + 自动旋转
- 抖音式上下滑动切歌，过渡动画丝滑；左右滑动也可切换
- 底部控制栏自由布局：进度条 / 控制按钮 / 指示线可拖动到任意位置、任意缩放
- 4 种进度条样式（流光 / 辉光 / 极光 / 波浪）、DJ 节奏脉冲光效
- 底部指示线上滑呼出评论区（网易云 + QQ 评论）

**歌词：专业级定制**
- 逐行滚动跟随、点击歌词跳转播放、歌词翻译（网易云 tlyric）
- 色盘自定义当前行 / 未播放行 / 发光颜色，渐变起止色自由搭配
- 发光强度、模糊起始距离与强度均可调；3D 立体倾斜（上下后仰 + 左右倾斜）
- 字号、行距、显示行数、对齐（居中 / 居左）、位置重心全部可调
- 长按多选复制歌词、纯音乐空歌词兜底

**个性化：你的播放器你做主**
- 9 套全局主题色（琥珀暖金 / 青碧湖绿 / 樱粉 / 星蓝 / 罗兰紫 / 赛博青 / 蜜桃粉 / 鎏金黑 / 翡翠绿）
- 主题模式跟随系统 / 浅色 / 深色；全局玻璃材质可选液态玻璃或磨砂玻璃
- 自定义壁纸库：上传多张壁纸随时切换，全局背景同步
- 自定义背景色、注释颜色、导入字体
- 设置配置一键备份 / 恢复（JSON 导出分享 / 导入恢复）

**播放能力拉满**
- 5 档音质（标准 / 较高 / 极高 / 无损 / Hi-Res），无损与 Hi-Res 自动回落
- 免费听歌开关（灰色 / VIP / 版权歌曲自动匹配第三方音源）
- 第三方音源：GD 音乐台、酷我音源、波点音源 + 自定义音源导入
- 歌曲下载（低质量 128k / 高质量 320k，存到文件 App）
- 锁屏控制、控制中心、后台播放、播放队列与插队、倍速（0.5x~2.0x）、循环模式、±15 秒、睡眠定时
- 播放历史、网易云听歌排行（本周 / 所有时间）

**系统体验**
- iOS 26 原生液态玻璃（Liquid Glass）TabBar，与系统 App 一致
- 首次进入免责声明确认门禁 + 版本更新说明弹窗 + 更新日志
- 软件使用说明、深浅色自适应

---

## 📂 工程结构

```
Beans/
├── BeansApp.swift                应用入口（免责声明门禁）
├── RootView.swift                底部 Tab 液态玻璃导航 + 迷你播放器
├── DiscoverView.swift            发现页（每日推荐 / 排行榜 / 推荐歌单）
├── SearchView.swift              搜索（网易云 / QQ 切换 / 热搜）
├── LibraryView.swift             音乐库（歌单 / 本地音乐库 / 最近播放）
├── ProfileView.swift             我的（功能 / 听歌排行 / 使用说明 / 设置）
├── PlayerView.swift              播放器（动态取色 / 歌词 / 底部控制 / 设置）
├── PlayerManager.swift           播放核心（队列 / 倍速 / 定时 / 历史）
├── LoginView.swift               网易云登录（扫码 + 网页登录）
├── NetEaseWebLoginSheet.swift    网易云网页登录（WKWebView 读取 Cookie）
├── QQMusicAPI.swift / QQMusicAuth.swift / QQWebLoginSheet.swift  QQ 音乐接入
├── NetEaseAPI.swift / NetEaseCrypto.swift   网易云接口与加密（weapi / eapi）
├── AuthStore.swift / Models.swift   登录态与数据模型
├── Theme.swift / CoverPalette.swift   全局主题与封面取色
├── PlayerLayout.swift / PlayerAmbience.swift / DJVisualView.swift   布局与氛围
├── DownloadManager.swift / UnblockService.swift / UnblockSourceStore.swift   下载与音源
├── CommentsSheet.swift / ArtistHomeSheet.swift   评论与歌手主页
├── Changelog.swift / Components.swift / SongCell.swift   日志与组件库
└── Assets.xcassets                图标与资源
```

---

## 🔨 构建

GitHub Actions（`Build Unsigned IPA`）自动构建，产物发布到 [Releases](https://github.com/XIaodou0416/Beans-Music/releases)。

本地构建（需要 Mac + Xcode 26）：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Beans.xcodeproj -scheme Beans -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Beans.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload Beans-unsigned.ipa
```

## 📲 安装

未签名 IPA 需自行签名安装：Sideloadly / AltStore / 爱思助手，使用 Apple ID 签名（免费自签 7 天有效）。
- 要求 iOS 26+（依赖原生液态玻璃）
- Bundle ID：`com.beans.app`

---

## ⚠️ 免责声明

- 本应用仅供个人学习研究使用，禁止用于商业及非法用途，如产生法律纠纷与作者无关
- 音乐 API 来源于 GitHub 开源项目（非官方版 API），本软件不提供任何音频存储服务
- 音乐版权归各平台所有，请支持正版；如需下载音频请在各平台官方渠道购买
- “QQ”、“QQ音乐”及企鹅形象等文字、图形和商业标识，其著作权或商标权归腾讯公司所有
- “网易云”、“网易云音乐”等文字、图形和商业标识，其著作权或商标权归网易公司所有
- 具体内容请参考各平台用户协议

## 🧑‍💻 关于作者

- 作者本人**什么都不会**，连这篇介绍都是 **AI 写的** 🤡
- 本软件由 **OpenAI Codex** 编程助手开发，从需求分析、UI 设计到代码实现全程由 AI 完成
- 软件完全开源（MIT License），欢迎任何人学习、修改、二次开发

## 📄 License

[MIT](LICENSE) © 2026 XIaodou0416

**开源说明：** 本项目为开源软件，代码公开透明，接受 Issue 反馈与 Fork 学习。非官方 API 属逆向学习范畴，请尊重各平台服务条款，合理使用。
