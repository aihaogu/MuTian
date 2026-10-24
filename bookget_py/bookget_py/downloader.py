from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .config import Config
from .http import download_file, extension_from_url
from .results import DownloadResult


@dataclass(frozen=True)
class TemplatePage:
    url: str
    stem: str


def download_urls(urls: Iterable[str | TemplatePage], config: Config, headers: dict[str, str]) -> DownloadResult:
    jobs: list[tuple[str, Path]] = []
    for index, item in enumerate(urls):
        if isinstance(item, TemplatePage):
            # These pages already carry the requested original page/volume numbers.
            url, stem = item.url, item.stem
        else:
            if not item or not config.page_allowed(index, 0):
                continue
            url, stem = item, f"{index + 1:04d}"
        ext = extension_from_url(url, config.ext)
        jobs.append((url, config.directory / (stem + ext)))
    result = DownloadResult()
    if not jobs:
        result.failure("No pages matched the requested range.")
        return result
    with ThreadPoolExecutor(max_workers=max(1, config.concurrent)) as pool:
        futures = {
            pool.submit(download_file, url, path, headers, config.timeout, config.retries, 1): (url, path)
            for url, path in jobs
        }
        for processed, future in enumerate(as_completed(futures), 1):
            url, path = futures[future]
            try:
                if future.result():
                    result.saved += 1
                else:
                    result.skipped += 1
                result.files.append(str(path.resolve()))
                print(f"[{processed}/{len(jobs)}] done {url}", flush=True)
            except Exception as exc:
                result.failure(f"{url}: {exc}")
                print(f"[{processed}/{len(jobs)}] failed {url}: {exc}", flush=True)
    return result


def expand_template(template: str, config: Config) -> list[TemplatePage]:
    if "[PAGE]" not in template:
        raise ValueError("URL template must include [PAGE]")
    start = config.seq_start or 1
    end = config.seq_end or start
    vol_start = config.vol_start or 1
    vol_end = config.vol_end or vol_start
    pages = []
    for volume in range(vol_start, vol_end + 1):
        for page in range(start, end + 1):
            url = template.replace("[PAGE]", str(page)).replace("[VOL]", str(volume))
            stem = f"{volume:04d}-{page:04d}" if "[VOL]" in template else f"{page:04d}"
            marker = "[AB]" if "[AB]" in url else "[ab]" if "[ab]" in url else None
            if marker:
                for side in ("AB" if marker == "[AB]" else "ab"):
                    pages.append(TemplatePage(url.replace(marker, side), stem + "-" + side))
            else:
                pages.append(TemplatePage(url, stem))
    return pages
