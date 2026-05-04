from __future__ import annotations

from urllib.parse import urlparse

from .config import Config
from .downloader import download_urls, expand_template
from .iiif import download_manifest


SUPPORTED_DOMAINS = {
    "read.nlc.cn": "国家图书馆",
    "mylib.nlc.cn": "国家图书馆",
    "guji.nlc.cn": "国家图书馆古籍",
    "taiwanebook.ncl.edu.tw": "臺灣華文電子書庫",
    "repository.lib.cuhk.edu.hk": "香港中文大学图书馆",
    "lbezone.hkust.edu.hk": "香港科技大学图书馆",
    "yun.szlib.org.cn": "深圳市图书馆古籍",
    "gj.tianyige.com.cn": "天一阁博物院",
    "dl.ndl.go.jp": "日本国立国会图书馆",
    "iiif.lib.harvard.edu": "哈佛大学图书馆",
    "archive.org": "Internet Archive",
    "www.loc.gov": "美国国会图书馆",
    "dcollections.lib.keio.ac.jp": "庆应义塾大学图书馆",
    "digital.bodleian.ox.ac.uk": "牛津大学博德利图书馆",
}


def route_and_download(url: str, config: Config, headers: dict[str, str]) -> int:
    lowered = url.lower()
    parsed = urlparse(url)
    host = parsed.netloc

    if "[PAGE]" in url:
        return download_urls(expand_template(url, config), config, headers)

    if config.downloader_mode == 2 or "manifest.json" in lowered or lowered.endswith(".json"):
        return download_manifest(url, config, headers)

    if config.downloader_mode == 1:
        return download_urls(expand_template(url, config), config, headers)

    if _looks_like_direct_file(lowered):
        return download_urls([url], config, headers)

    if host in SUPPORTED_DOMAINS:
        raise NotImplementedError(
            f"{SUPPORTED_DOMAINS[host]} 的定制解析尚未迁移到 Python。"
            "如果该页面有 IIIF manifest，请直接输入 manifest.json URL。"
        )

    raise NotImplementedError(
        "当前 Python 版支持直接文件 URL、URL 列表、[PAGE] 模板和 IIIF manifest；"
        f"暂不支持自动解析页面：{url}"
    )


def _looks_like_direct_file(url: str) -> bool:
    return any(url.split("?", 1)[0].endswith(ext) for ext in (".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp", ".pdf"))
