#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/bin/bookget"

chmod +x "$OUTPUT"
"$OUTPUT" --version
echo "$OUTPUT"
