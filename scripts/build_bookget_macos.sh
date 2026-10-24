#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PYTHON="${MUTIAN_BUILD_PYTHON:-python3}"
VENV="$ROOT_DIR/.build/bookget-packaging-venv"
if [[ ! -x "$VENV/bin/python" ]]; then
  "$BUILD_PYTHON" -m venv "$VENV"
fi
if ! "$VENV/bin/python" - "$ROOT_DIR/scripts/requirements-packaging.txt" <<'PYVERIFY'
import importlib.metadata
from pathlib import Path
import sys
try:
    for line in Path(sys.argv[1]).read_text().splitlines():
        name, version = line.split("==")
        if importlib.metadata.version(name) != version:
            raise ValueError(name)
except (importlib.metadata.PackageNotFoundError, ValueError):
    sys.exit(1)
PYVERIFY
then
  "$VENV/bin/python" -m pip install -r "$ROOT_DIR/scripts/requirements-packaging.txt"
fi
export PYINSTALLER_CONFIG_DIR="$ROOT_DIR/.build/pyinstaller-cache"
"$VENV/bin/python" -m PyInstaller --noconfirm --clean --onedir --name bookget \
  --collect-data certifi --paths "$ROOT_DIR/bookget_py" \
  --distpath "$ROOT_DIR/.build/bundled-downloader" \
  --workpath "$ROOT_DIR/.build/pyinstaller-work" \
  --specpath "$ROOT_DIR/.build/pyinstaller-spec" "$ROOT_DIR/bin/bookget"
"$ROOT_DIR/.build/bundled-downloader/bookget/bookget" --version
