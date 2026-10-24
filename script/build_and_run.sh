#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MuTian"
DISPLAY_NAME="木天"
BUNDLE_ID="dev.local.MuTian"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/MuTian/Resources/AppIcon.icns"

cd "$ROOT_DIR"

case "$MODE" in
  --build|build|run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *) echo "Unknown build mode: $MODE" >&2; exit 2 ;;
esac

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$CLANG_MODULE_CACHE_PATH}"
swift build --disable-sandbox
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

"$ROOT_DIR/scripts/build_bookget_macos.sh"

# Stage a complete bundle before replacing the previous successful build.
FINAL_BUNDLE="$APP_BUNDLE"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.build/bundle.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_BUNDLE="$STAGING_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
mkdir -p "$APP_RESOURCES"
/usr/bin/ditto "$ROOT_DIR/.build/bundled-downloader/bookget" "$APP_RESOURCES/bookget"
mkdir -p "$APP_RESOURCES/ThirdPartyLicenses"
cp "$ROOT_DIR/bookget/LICENSE" "$APP_RESOURCES/ThirdPartyLicenses/bookget-LICENSE"
cp "$ROOT_DIR/bookget_py/README.md" "$APP_RESOURCES/ThirdPartyLicenses/bookget-source.md"
if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST"
# PyInstaller signs nested binaries; ad-hoc signing is enough for local builds.
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/env -i PATH=/usr/bin:/bin "$APP_RESOURCES/bookget/bookget" --version
mkdir -p "$DIST_DIR"
rm -rf "$FINAL_BUNDLE"
mv "$APP_BUNDLE" "$FINAL_BUNDLE"
APP_BUNDLE="$FINAL_BUNDLE"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
