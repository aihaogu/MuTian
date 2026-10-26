#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
VERSION="$(tr -d '\r\n' < VERSION)"
ARCH="$(uname -m)"
APP="$ROOT_DIR/dist/木天.app"
OUT="$ROOT_DIR/dist/release"
NAME="MuTian-v${VERSION}-macOS-${ARCH}.zip"

MUTIAN_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build
./scripts/test_bundle.sh
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
test "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/MuTian")" = "$ARCH"
mkdir -p "$OUT"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME"
(
  cd "$OUT"
  /usr/bin/shasum -a 256 "$NAME" > SHA256SUMS.txt
)
{
  printf 'MuTian v%s\nArchitecture: %s\n' "$VERSION" "$ARCH"
  printf 'Commit: %s\n' "$(git rev-parse HEAD)"
  printf 'Minimum macOS: 14.0\nConfiguration: release\nSigning: ad-hoc (not notarized)\n'
  /usr/bin/xcodebuild -version
  swift --version
} > "$OUT/BUILD_INFO.txt"
echo "Release assets: $OUT"
