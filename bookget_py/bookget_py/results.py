from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
import uuid


@dataclass
class DownloadResult:
    saved: int = 0
    skipped: int = 0
    failed: int = 0
    files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def merge(self, other: DownloadResult) -> None:
        self.saved += other.saved
        self.skipped += other.skipped
        self.failed += other.failed
        self.files.extend(other.files)
        self.errors.extend(other.errors)

    def failure(self, message: str) -> None:
        self.failed += 1
        self.errors.append(message)

    @property
    def succeeded(self) -> bool:
        return self.failed == 0 and self.saved + self.skipped > 0

    def report(self) -> dict:
        return {
            "version": 1, "saved": self.saved, "skipped": self.skipped,
            "failed": self.failed, "files": self.files, "errors": self.errors,
            "output_directories": sorted({str(Path(p).parent) for p in self.files}),
        }

    def write(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
        try:
            temporary.write_text(json.dumps(self.report(), ensure_ascii=False), encoding="utf-8")
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)

    def print_summary(self) -> None:
        print(f"Download result: saved {self.saved}, verified existing {self.skipped}, failed {self.failed}.", flush=True)
