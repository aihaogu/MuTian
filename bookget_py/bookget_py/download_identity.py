from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
from pathlib import Path
import uuid


def source_directory(base: Path, url: str) -> Path:
    # Stable across retries; two books never share a numbered file namespace.
    return base.resolve() / ("book-" + hashlib.sha256(url.encode()).hexdigest()[:20])


def receipt_path(destination: Path) -> Path:
    return destination.parent / ".bookget" / (destination.name + ".json")


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def verified_existing(destination: Path, url: str) -> bool:
    if not destination.exists():
        return False
    try:
        receipt = json.loads(receipt_path(destination).read_text(encoding="utf-8"))
        if (receipt["url"] == url and destination.stat().st_size > 0
                and receipt["size"] == destination.stat().st_size
                and receipt["sha256"] == digest(destination)):
            return True
    except (OSError, ValueError, KeyError, TypeError):
        pass
    # Never silently treat an unrelated or damaged local file as a completed page.
    raise RuntimeError(f"existing file cannot be verified; move it aside before retrying: {destination}")


@contextmanager
def destination_lock(destination: Path):
    metadata = destination.parent / ".bookget"
    metadata.mkdir(parents=True, exist_ok=True)
    with (metadata / (destination.name + ".lock")).open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def save_verified(data: bytes, destination: Path, url: str) -> None:
    if not data:
        raise ValueError("empty download")
    token = uuid.uuid4().hex
    temporary = destination.with_name(destination.name + "." + token + ".part")
    receipt = receipt_path(destination)
    pending_receipt = receipt.with_name(receipt.name + "." + token + ".tmp")
    receipt.parent.mkdir(parents=True, exist_ok=True)
    try:
        temporary.write_bytes(data)
        pending_receipt.write_text(json.dumps({
            "url": url, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()
        }), encoding="utf-8")
        temporary.replace(destination)
        pending_receipt.replace(receipt)
    finally:
        temporary.unlink(missing_ok=True)
        pending_receipt.unlink(missing_ok=True)
