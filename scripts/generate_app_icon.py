#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "DeGu" / "Resources"
SOURCE = RESOURCES / "AppIconSource.png"
ICONSET = RESOURCES / "AppIcon.iconset"
ICNS = RESOURCES / "AppIcon.icns"


ICONSET_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

ICNS_CHUNKS = {
    16: ("icp4", "icon_16x16.png"),
    32: ("icp5", "icon_16x16@2x.png"),
    64: ("icp6", "icon_32x32@2x.png"),
    128: ("ic07", "icon_128x128.png"),
    256: ("ic08", "icon_128x128@2x.png"),
    512: ("ic09", "icon_256x256@2x.png"),
    1024: ("ic10", "icon_512x512@2x.png"),
}


def write_iconset() -> None:
    image = Image.open(SOURCE).convert("RGBA")
    if image.size != (1024, 1024):
        raise ValueError(f"{SOURCE} must be 1024x1024, got {image.size}")

    ICONSET.mkdir(parents=True, exist_ok=True)
    for filename, size in ICONSET_SIZES.items():
        target = ICONSET / filename
        image.resize((size, size), Image.Resampling.LANCZOS).save(target)


def write_icns() -> None:
    chunks: list[bytes] = []
    for _size, (code, filename) in ICNS_CHUNKS.items():
        data = (ICONSET / filename).read_bytes()
        chunks.append(code.encode("ascii") + (len(data) + 8).to_bytes(4, "big") + data)

    payload = b"".join(chunks)
    ICNS.write_bytes(b"icns" + (len(payload) + 8).to_bytes(4, "big") + payload)


def main() -> None:
    write_iconset()
    write_icns()
    print(f"wrote {ICONSET}")
    print(f"wrote {ICNS}")


if __name__ == "__main__":
    main()
