from __future__ import annotations

import re
import time
from html import unescape
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urljoin, urlparse

from .config import Config
from .http import get_bytes


def download_nlc(url: str, config: Config, headers: dict[str, str]) -> int:
    volume_urls = _volume_urls(url, config, headers)
    if not volume_urls:
        raise RuntimeError("未在国家图书馆页面中找到可下载的在线阅读链接。")

    print(f"国家图书馆：发现 {len(volume_urls)} 册")
    completed = 0
    total = len(volume_urls)
    for index, volume_url in enumerate(volume_urls):
        if not _volume_allowed(index, config):
            continue

        try:
            destination = config.directory / f"{index + 1:04d}.pdf"
            if _download_volume_pdf(volume_url, destination, config, headers):
                completed += 1
            print(f"[{index + 1}/{total}] done {volume_url}")
        except Exception as exc:
            print(f"[{index + 1}/{total}] failed {volume_url}: {exc}")

        if config.sleep > 0:
            time.sleep(config.sleep)

    print(f"Download complete. saved {completed} files.")
    return completed


def probe_nlc(url: str, config: Config, headers: dict[str, str]) -> dict[str, object]:
    html = "" if "OutOpenBook/OpenObjectBook" in urlparse(url).path else _get_text(url, config, headers)
    volume_urls = _volume_urls_from_html(url, html) if html else [url]
    title = _title_from_html(html) if html else ""
    return {
        "kind": "国家图书馆",
        "title": title,
        "volume_count": len(volume_urls),
        "url": url,
    }


def _volume_urls(url: str, config: Config, headers: dict[str, str]) -> list[str]:
    parsed = urlparse(url)
    if "OutOpenBook/OpenObjectBook" in parsed.path:
        return [url]

    html = _get_text(url, config, headers)
    return _volume_urls_from_html(url, html)


def _volume_urls_from_html(url: str, html: str) -> list[str]:
    matches = re.findall(
        r"""href=["']([^"']*OutOpenBook/OpenObjectBook\?[^"']+)["']""",
        html,
        flags=re.IGNORECASE,
    )

    seen: set[str] = set()
    urls: list[str] = []
    for match in matches:
        absolute = urljoin(url, match.replace("&amp;", "&"))
        if absolute not in seen:
            seen.add(absolute)
            urls.append(absolute)
    return urls


def _title_from_html(html: str) -> str:
    match = re.search(r"""<input[^>]+id=["']title["'][^>]+value=["']([^"']*)["']""", html)
    if match:
        return unescape(match.group(1)).strip()
    match = re.search(r"""<div[^>]+class=["']title["'][^>]*>\s*([^<]+?)\s*</div>""", html)
    return unescape(match.group(1)).strip() if match else ""


def _download_volume_pdf(
    volume_url: str,
    destination: Path,
    config: Config,
    headers: dict[str, str],
) -> bool:
    if destination.exists() and destination.stat().st_size > 0:
        print(f"skip existing {destination}")
        return False

    parsed = urlparse(volume_url)
    query = parse_qs(parsed.query)
    aid = _first(query, "aid")
    bid = _first(query, "bid")
    if not aid or not bid:
        raise RuntimeError("阅读链接缺少 aid 或 bid。")

    html = _get_text(volume_url, config, headers)
    token_key = _attribute(html, "tokenKey")
    time_key = _attribute(html, "timeKey")
    time_flag = _attribute(html, "timeFlag")
    if not token_key or not time_key or not time_flag:
        raise RuntimeError("阅读页缺少 tokenKey/timeKey/timeFlag，可能需要登录或馆内权限。")

    pdf_query = urlencode({
        "aid": aid,
        "bid": bid,
        "kime": time_key,
        "fime": time_flag,
    })
    pdf_url = f"{parsed.scheme}://{parsed.netloc}/menhu/OutOpenBook/getReaderNew?{pdf_query}"
    request_headers = dict(headers)
    request_headers.update({
        "Referer": f"{parsed.scheme}://{parsed.netloc}/static/webpdf/lib/WebPDFJRWorker.js",
        "Range": "bytes=0-1",
        "myreader": token_key,
    })

    data = get_bytes(pdf_url, request_headers, timeout=config.timeout, retries=config.retries, min_size=128)
    if not data.startswith(b"%PDF"):
        preview = data[:120].decode("utf-8", errors="replace")
        raise RuntimeError(f"返回内容不是 PDF：{preview}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    temporary.write_bytes(data)
    temporary.replace(destination)
    print(f"saved {destination}")
    return True


def _get_text(url: str, config: Config, headers: dict[str, str]) -> str:
    request_headers = dict(headers)
    request_headers.setdefault("Referer", url)
    data = get_bytes(url, request_headers, timeout=config.timeout, retries=config.retries, min_size=1)
    return data.decode("utf-8", errors="replace")


def _attribute(html: str, name: str) -> str:
    match = re.search(rf"""{name}=["']([^"']+)["']""", html)
    return match.group(1) if match else ""


def _first(query: dict[str, list[str]], key: str) -> str:
    values = query.get(key) or []
    return values[0] if values else ""


def _volume_allowed(index_zero_based: int, config: Config) -> bool:
    volume = index_zero_based + 1
    if config.vol_start is not None and volume < config.vol_start:
        return False
    if config.vol_end is not None and volume > config.vol_end:
        return False
    return True
