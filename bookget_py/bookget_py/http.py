from __future__ import annotations

import time
import urllib.error
import urllib.request
from pathlib import Path
from .download_identity import destination_lock, verified_existing, save_verified


def read_cookie_file(path: str) -> str:
    file_path = Path(path).expanduser()
    if not file_path.exists():
        return ""
    lines: list[str] = []
    for line in file_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" in line:
            parts = line.split("\t")
            if len(parts) >= 7:
                lines.append(f"{parts[5]}={parts[6]}")
        else:
            lines.append(line)
    return "; ".join(lines)


def read_headers_file(path: str) -> dict[str, str]:
    file_path = Path(path).expanduser()
    if not file_path.exists():
        return {}
    headers: dict[str, str] = {}
    for line in file_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip()] = value.strip()
    return headers


def build_headers(user_agent: str, cookie_file: str, header_file: str) -> dict[str, str]:
    headers = {"User-Agent": user_agent}
    cookie = read_cookie_file(cookie_file)
    if cookie:
        headers["Cookie"] = cookie
    headers.update(read_headers_file(header_file))
    return headers


def get_bytes(
    url: str,
    headers: dict[str, str],
    timeout: int,
    retries: int,
    min_size: int = 0,
) -> bytes:
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = response.read()
            if min_size and len(data) < min_size:
                raise ValueError(f"response too small: {len(data)} bytes")
            return data
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(min(2 + attempt, 8))
    raise RuntimeError(f"download failed: {url}: {last_error}")


def download_file(
    url: str,
    destination: Path,
    headers: dict[str, str],
    timeout: int,
    retries: int,
    min_size: int = 0,
) -> bool:
    with destination_lock(destination):
        if verified_existing(destination, url):
            print(f"skip verified {destination}", flush=True)
            return False
        data = get_bytes(url, headers, timeout=timeout, retries=retries, min_size=max(1, min_size))
        save_verified(data, destination, url)
        print(f"saved {destination}", flush=True)
        return True


def read_url_lines(path: str) -> list[str]:
    file_path = Path(path).expanduser()
    return [
        line.strip()
        for line in file_path.read_text(encoding="utf-8", errors="ignore").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def extension_from_url(url: str, fallback: str) -> str:
    clean = url.split("?", 1)[0].split("#", 1)[0]
    suffix = Path(clean).suffix
    return suffix or fallback
