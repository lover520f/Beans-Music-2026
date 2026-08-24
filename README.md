# Beans Music

一款基于 iOS 26 原生液态玻璃（Liquid Glass）风格的第三方音乐播放器，聚合网易云音乐、QQ 音乐与酷狗音乐资源，纯 SwiftUI 实现，仅供学习交流使用。

## 功能特性

**多平台聚合**
- 网易云 / QQ 音乐 / 酷狗音乐：首页每日推荐、排行榜、歌单广场、搜索、热门搜索均可切换数据源
- 网易云：扫码登录 / 应用内网页登录，同步歌单、收藏、听歌排行与 VIP / SVIP 标识
- QQ 音乐：扫码授权 / 网页登录，同步歌单与 VIP 标识；评论、歌词随平台切换
- 酷狗音乐：账号登录与歌单同步

**播放体验**
- AVPlayer 在线播放，锁屏控制、控制中心与后台播放
- 播放队列 / 插队播放 / 播放历史 / 睡眠定时 / 倍速（0.5x~2.0x）/ 循环与随机模式
- 多档音质选择（标准 / 较高 / 极高 / 无损 / Hi-Res），免费听歌开关
- 下载歌曲（多音质）、播放失败原因提示（区分未开启免费听歌与音源未命中）

**歌词系统**
- 逐行滚动跟随、点击歌词跳转播放、歌词翻译（网易云 tlyric）
- 自定义歌词颜色 / 渐变 / 发光强度与颜色 / 模糊起始距离与强度
- 3D 立体倾斜（上下后仰 + 左右倾斜）、歌词位置 / 对齐 / 显示行数调节
- 长按歌词多选复制、纯音乐空歌词兜底

**播放器界面**
- 动态封面取色：背景渐变、进度条、按钮、歌词高亮全部跟随专辑封面主色
- 封面点击切换歌词视图（封面飞入左上角动画）、圆形封面模式
- 底部布局自由调整（拖动组件到任意位置）、抖音式上下滑动切歌
- 歌词播放界面、评论区上滑呼出、进度条多种样式（流光 / 辉光 / 极光 / 波浪）

**个性化**
- 5 套全局配色主题一键切换（赛博青 / 蜜桃粉 / 鎏金黑等）
- 自定义壁纸库：上传多张壁纸随时切换、全局背景同步
- 全局主题色 / 注释颜色自定义、字体文件导入
- 设置配置一键备份 / 恢复（导出 JSON 分享，导入恢复）

**系统能力**
- iOS 26 原生液态玻璃（Liquid Glass）、深浅色模式自适应
- 更新弹窗与更新日志、软件使用说明、免责声明

## 工程结构

```
Beans/
├── BeansApp.swift                应用入口
├── RootView.swift                底部 Tab 液态玻璃导航 + 首次免责声明
├── DiscoverView.swift            发现页（每日推荐 / 排行榜 / 歌单广场）
├── SearchView.swift              搜索（多平台切换 / 热搜）
├── LibraryView.swift             音乐库（歌单 / 最近播放 / 听歌排行）
├── ProfileView.swift             我的（账号 / 听歌排行 / 外观 / 设置）
├── PlayerView.swift              播放器（动态取色 / 歌词 / 底部控制 / 设置）
├── LyricsSection                 歌词滚动（发光 / 渐变 / 3D 倾斜 / 模糊）
├── LoginView.swift               网易云登录（扫码 + 网页登录）
├── NetEaseWebLoginSheet.swift    网易云网页登录（WKWebView 读取 Cookie）
├── QQMusicAPI.swift / QQMusicAuth.swift / QQWebLoginSheet.swift  QQ 音乐接入
├── NetEaseAPI.swift / NetEaseCrypto.swift   网易云接口与加密（weapi / eapi）
├── PlayerManager.swift / AuthStore.swift / Models.swift   核心逻辑层
├── Theme.swift / CoverPalette.swift   全局主题与封面取色
├── PlayerLayout.swift / PlayerAmbience.swift   底部布局与氛围
├── DownloadManager.swift / UnblockService.swift / UnblockSourceStore.swift   下载与音源
├── Changelog.swift / Components.swift / SongCell.swift   日志与组件库
└── Assets.xcassets                图标与资源
```

## 构建

GitHub Actions（`Build Unsigned IPA`）在 macOS 云机上自动编译未签名 IPA：
- 触发：推送到 `main` 或手动 Run workflow
- 产物：Actions 页面 Artifacts 下载 `Beans-unsigned-ipa`；每次构建自动发布到 Releases 页面

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

## 安装到 iPhone

未签名 IPA 需自行签名安装：Sideloadly / AltStore / 爱思助手，使用 Apple ID 签名（免费自签 7 天有效，付费开发者账号 1 年）。
- 要求 iOS 26+（依赖原生液态玻璃）
- Bundle ID：`com.beans.app`

## 免责声明

- 本应用仅供个人学习研究使用，禁止用于商业及非法用途，如产生法律纠纷与作者无关
- 音乐 API 来源于 GitHub 开源项目（非官方版 API），本软件不提供任何音频存储服务
- 音乐版权归各平台所有，请支持正版；如需下载音频请在各平台官方渠道购买
- “QQ”、“QQ音乐”及企鹅形象等标识著作权或商标权归腾讯公司所有
- “网易云”、“网易云音乐”等标识著作权或商标权归网易公司所有
- 酷狗音乐相关标识著作权或商标权归酷狗公司所有

## License

[MIT](LICENSE)
