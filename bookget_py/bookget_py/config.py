from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional


DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)


@dataclass
class Config:
    input_url: str = ""
    input_file: str = ""
    directory: Path = Path("downloads")
    sequence: str = ""
    seq_start: Optional[int] = None
    seq_end: Optional[int] = None
    volume: str = ""
    vol_start: Optional[int] = None
    vol_end: Optional[int] = None
    format: str = "full/full/0/default.jpg"
    user_agent: str = DEFAULT_USER_AGENT
    use_dzi: bool = True
    cookies: str = "cookie.txt"
    headers: str = "header.txt"
    threads: int = 1
    concurrent: int = 16
    quality: int = 80
    ext: str = ".jpg"
    retries: int = 3
    timeout: int = 300
    sleep: int = 3
    downloader_mode: int = 0

    def normalize(self) -> None:
        self.directory = Path(self.directory).expanduser()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.seq_start, self.seq_end = parse_range(self.sequence)
        self.vol_start, self.vol_end = parse_range(self.volume)
        if self.ext and not self.ext.startswith("."):
            self.ext = "." + self.ext

    def page_allowed(self, index_zero_based: int, total: int) -> bool:
        page = index_zero_based + 1
        if self.seq_start is not None and page < self.seq_start:
            return False
        if self.seq_end is not None and page > self.seq_end:
            return False
        return True


def parse_range(value: str) -> tuple[Optional[int], Optional[int]]:
    value = (value or "").strip()
    if not value:
        return None, None
    if ":" in value:
        left, right = value.split(":", 1)
        return int(left) if left else None, int(right) if right else None
    number = int(value)
    return number, number
