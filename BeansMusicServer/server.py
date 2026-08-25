#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Beans Music 服务器（基于 musicdl 的多平台音源接口）
=====================================================
提供三个能力：
  1. GET /api/search?keyword=xxx&sources=qq,netease,migu  搜索并直接解析出可播放直链
  2. GET /api/stream?url=xxx                              音频代理（解决直链失效/防盗链/免登录播放）
  3. GET /                                               内置网页版测试页（搜索即播）

启动：python server.py [--host 0.0.0.0] [--port 8765] [--limit 8]
"""
import sys
import time
import threading
import argparse
import logging
from pathlib import Path
from urllib.parse import quote

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import requests

from musicdl.musicdl import MusicClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("beans-music-server")

SOURCE_MAP = {
    "QQMusicClient": "qq",
    "NeteaseMusicClient": "netease",
    "KugouMusicClient": "kugou",
    "MiguMusicClient": "migu",
    "KuwoMusicClient": "kuwo",
    "QianqianMusicClient": "qianqian",
    "SodaMusicClient": "soda",
}
SOURCE_REVERSE = {v: k for k, v in SOURCE_MAP.items()}
DEFAULT_SOURCES = ["qq", "netease", "kugou", "migu"]

app = FastAPI(title="Beans Music 服务器", version="1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_client_lock = threading.Lock()
_client = None
_client_sources = []
_client_limit = 8

_cache_lock = threading.Lock()
_cache = {}
CACHE_TTL = 600


def ensure_client(sources, limit):
    global _client, _client_sources, _client_limit
    desired = [s for s in sources if s in SOURCE_REVERSE] or DEFAULT_SOURCES
    with _client_lock:
        if _client is None or set(desired) - set(_client_sources) or limit > _client_limit:
            merged = list(dict.fromkeys(_client_sources + desired))
            _client_limit = max(_client_limit, limit)
            log.info("初始化 musicdl 音源：%s", merged)
            _client = MusicClient(
                music_sources=[SOURCE_REVERSE[s] for s in merged],
                init_music_clients_cfg={
                    SOURCE_REVERSE[s]: {
                        "search_size_per_source": _client_limit,
                        "max_retries": 2,
                        "maintain_session": False,
                    }
                    for s in merged
                },
                requests_overrides={
                    SOURCE_REVERSE[s]: {"timeout": (4, 10)}
                    for s in merged
                },
            )
            _client_sources = merged
        return _client


def serialize(song):
    ext = (song.ext or "").lstrip(".")
    url = song.download_url if isinstance(song.download_url, str) else ""
    return {
        "id": str(song.identifier or ""),
        "name": song.song_name or "",
        "artists": song.singers or "",
        "album": song.album or "",
        "cover": song.cover_url or "",
        "duration": int(song.duration_s or 0),
        "ext": ext,
        "bitrate": song.bitrate,
        "source": SOURCE_MAP.get(song.source, song.source or ""),
        "url": url,
    }


def cache_get(key):
    with _cache_lock:
        hit = _cache.get(key)
        if hit and time.time() - hit[0] < CACHE_TTL:
            return hit[1]
        return None


def cache_set(key, value):
    with _cache_lock:
        _cache[key] = (time.time(), value)
        if len(_cache) > 200:
            now = time.time()
            for k in [k for k, (ts, _) in list(_cache.items()) if now - ts > CACHE_TTL]:
                _cache.pop(k, None)


@app.get("/", response_class=HTMLResponse)
def index():
    return (BASE_DIR / "index.html").read_text(encoding="utf-8")


@app.get("/api/health")
def health():
    return {"status": "ok", "sources": _client_sources or DEFAULT_SOURCES}


@app.get("/api/search")
def search(keyword: str = "", sources: str = "", limit: int = 8):
    keyword = (keyword or "").strip()
    if not keyword:
        raise HTTPException(status_code=400, detail="keyword 不能为空")
    limit = max(1, min(limit, 20))
    source_list = [s.strip().lower() for s in sources.split(",") if s.strip()] or DEFAULT_SOURCES
    cache_key = keyword + "|" + ",".join(sorted(source_list)) + "|" + str(limit)
    cached = cache_get(cache_key)
    if cached is not None:
        return {"code": 0, "keyword": keyword, "sources": source_list, "songs": cached, "cached": True}

    client = ensure_client(source_list, limit)
    log.info("搜索：%s（%s）", keyword, ",".join(source_list))
    t0 = time.time()
    try:
        raw = client.search(keyword=keyword)
    except Exception as err:
        log.error("搜索失败：%s（%s）", keyword, err)
        raise HTTPException(status_code=502, detail="搜索失败：" + str(err))
    elapsed = round(time.time() - t0, 1)

    songs = []
    for src in source_list:
        items = raw.get(SOURCE_REVERSE.get(src, src), []) or []
        for s in items:
            item = serialize(s)
            if item["url"] and item["name"]:
                item["stream"] = "/api/stream?url=" + quote(item["url"], safe="")
                songs.append(item)
    seen = set()
    per_source_count = {}
    deduped = []
    for item in songs:
        key = item["source"] + "|" + item["id"]
        if key in seen:
            continue
        if per_source_count.get(item["source"], 0) >= limit:
            continue
        seen.add(key)
        per_source_count[item["source"]] = per_source_count.get(item["source"], 0) + 1
        deduped.append(item)
    log.info("搜索完成：%s，%d 首，耗时 %ss", keyword, len(deduped), elapsed)
    cache_set(cache_key, deduped)
    return {"code": 0, "keyword": keyword, "sources": source_list, "songs": deduped, "elapsed_s": elapsed}


@app.get("/api/stream")
def stream(url: str, request: Request):
    if not (url.startswith("http://") or url.startswith("https://")):
        raise HTTPException(status_code=400, detail="url 参数非法")
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
    }
    range_header = request.headers.get("range")
    if range_header:
        headers["Range"] = range_header
    try:
        upstream = requests.get(url, headers=headers, stream=True, timeout=30)
    except Exception as err:
        raise HTTPException(status_code=502, detail="拉取音频失败：" + str(err))
    if upstream.status_code >= 400:
        upstream.close()
        raise HTTPException(status_code=502, detail="上游音频源不可用")

    def gen():
        try:
            for chunk in upstream.iter_content(chunk_size=65536):
                if chunk:
                    yield chunk
        finally:
            upstream.close()

    pass_headers = {
        k: v
        for k, v in upstream.headers.items()
        if k.lower() in ("content-type", "content-length", "content-range", "accept-ranges")
    }
    return StreamingResponse(gen(), status_code=upstream.status_code, headers=pass_headers)


if __name__ == "__main__":
    import uvicorn

    parser = argparse.ArgumentParser(description="Beans Music 服务器")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--limit", type=int, default=8, help="每个音源返回的搜索结果数量")
    args = parser.parse_args()
    log.info("Beans Music 服务器启动：http://%s:%d （默认音源：%s）", args.host, args.port, ",".join(DEFAULT_SOURCES))
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
