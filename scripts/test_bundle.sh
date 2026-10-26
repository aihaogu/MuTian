#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mutian-bundle.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
/usr/bin/ditto "$ROOT_DIR/dist/木天.app" "$TEST_DIR/木天.app"
ENGINE="$TEST_DIR/木天.app/Contents/Resources/bookget/bookget"
EXPECTED_VERSION="$(tr -d '\r\n' < "$ROOT_DIR/VERSION")"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TEST_DIR/木天.app/Contents/Info.plist")" = "$EXPECTED_VERSION"
/usr/bin/codesign --verify --deep --strict "$TEST_DIR/木天.app"
/usr/bin/env -i PATH=/usr/bin:/bin "$ENGINE" --version
printf 'offline image fixture' > "$TEST_DIR/fixture.jpg"
SOURCE_URL="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).as_uri())' "$TEST_DIR/fixture.jpg")"
/usr/bin/env -i PATH=/usr/bin:/bin "$ENGINE" --input "$SOURCE_URL" --dir "$TEST_DIR/downloads" --result-file "$TEST_DIR/result.json" --retries 0
python3 - "$TEST_DIR/result.json" <<'PY'
import json
from pathlib import Path
import sys
report = json.loads(Path(sys.argv[1]).read_text())
assert report['saved'] == 1 and report['failed'] == 0
assert len(report['files']) == 1
assert Path(report['files'][0]).read_bytes() == b'offline image fixture'
print('PASS: relocated bundled engine, clean PATH, offline download and result manifest')
PY
