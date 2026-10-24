#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$CLANG_MODULE_CACHE_PATH}"
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="$ROOT_DIR/bookget_py${PYTHONPATH:+:$PYTHONPATH}"
swift build --disable-sandbox
./scripts/test_app_paths.sh
./scripts/test_readers.sh
./scripts/test_stores.sh
python3 -m unittest discover -s Tests/DownloadTests -v
