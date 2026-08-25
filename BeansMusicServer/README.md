# Beans Music 服务器（musicdl 音源接口）

基于 [musicdl](https://github.com/CharlesPikachu/musicdl) 的本地音乐搜索 + 播放直链服务器。
在电脑上跑起来后，手机 App（同一 Wi-Fi）可以在搜索页顶部看到「服务器音源」结果并直接播放；
也可以在电脑浏览器里打开测试页搜索即播。

## 快速开始（Windows）

1. 双击 `run.bat`（首次会自动创建虚拟环境并安装依赖，约 2~5 分钟）
2. 浏览器打开 `http://127.0.0.1:8765` 即可搜索播放
3. 手机与电脑连同一 Wi-Fi，App 内「我的 → 设置 → 音乐服务器」填入 `http://电脑IP:8765`（在设置页可一键填入本机地址）

## 手动启动（Mac / Linux）

```bash
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python server.py --host 0.0.0.0 --port 8765
```

## 接口说明

| 接口 | 说明 |
| --- | --- |
| `GET /` | 网页版测试页（搜索即播） |
| `GET /api/search?keyword=周杰伦&sources=qq,netease,migu&limit=8` | 搜索并返回可播放直链 |
| `GET /api/stream?url=...` | 音频代理（解决直链失效 / 防盗链） |
| `GET /api/health` | 健康检查 |

`sources` 可选：`qq`（QQ音乐）、`netease`（网易云）、`kugou`（酷狗）、`migu`（咪咕）、`kuwo`（酷我）、`qianqian`（千千）。

## 说明

- 搜索会真实解析各平台音源（含 QQ VIP / 周杰伦等版权歌，能解析出直链即可播放，不保证全部命中）
- 首次搜索较慢（约 1~2 分钟），结果会缓存 10 分钟，重复搜索秒出
- 本服务仅用于个人学习研究，请支持正版音乐
