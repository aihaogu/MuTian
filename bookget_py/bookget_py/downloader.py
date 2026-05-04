from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Iterable

from .config import Config
from .http import download_file, extension_from_url


def download_urls(urls: Iterable[str], config: Config, headers: dict[str, str]) -> int:
    url_list = [url for url in urls if url]
    if not url_list:
        print("no URLs to download")
        return 0

    jobs: list[tuple[int, str, Path]] = []
    for index, url in enumerate(url_list):
        if not config.page_allowed(index, len(url_list)):
            continue
        ext = extension_from_url(url, config.ext)
        destination = config.directory / f"{index + 1:04d}{ext}"
        jobs.append((index + 1, url, destination))

    completed = 0
    with ThreadPoolExecutor(max_workers=max(1, config.concurrent)) as pool:
        future_map = {
            pool.submit(
                download_file,
                url,
                destination,
                headers,
                config.timeout,
                config.retries,
                0,
            ): (number, url)
            for number, url, destination in jobs
        }
        for future in as_completed(future_map):
            number, url = future_map[future]
            try:
                if future.result():
                    completed += 1
                print(f"[{number}/{len(url_list)}] done {url}")
            except Exception as exc:
                print(f"[{number}/{len(url_list)}] failed {url}: {exc}")
    print(f"Download complete. saved {completed} files.")
    return completed


def expand_template(template: str, config: Config) -> list[str]:
    if "[PAGE]" not in template:
        raise ValueError("URL template must include [PAGE]")

    start = config.seq_start or 1
    end = config.seq_end or start
    vol_start = config.vol_start or 1
    vol_end = config.vol_end or vol_start
    urls: list[str] = []

    for volume in range(vol_start, vol_end + 1):
        for page in range(start, end + 1):
            url = template.replace("[PAGE]", str(page))
            url = url.replace("[VOL]", str(volume))
            if "[AB]" in url:
                urls.extend([url.replace("[AB]", side) for side in ("A", "B")])
            elif "[ab]" in url:
                urls.extend([url.replace("[ab]", side) for side in ("a", "b")])
            else:
                urls.append(url)
    return urls
