#!/bin/zsh
set -eu
ROOT=${0:A:h:h}
BUILD_DIR="${CODEX_METER_BUILD_DIR:-$ROOT/build}"
DIST_DIR="${CODEX_METER_DIST_DIR:-$ROOT/dist}"
APP="$BUILD_DIR/Codex Meter.app"
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
[[ -d "$APP" ]] || ARCHS="arm64 x86_64" "$ROOT/build.sh"
mkdir -p "$DIST_DIR" "$BUILD_DIR/dmg"
ditto "$APP" "$BUILD_DIR/dmg/Codex Meter.app"
ln -sfn /Applications "$BUILD_DIR/dmg/Applications"
cp "$ROOT/LICENSE" "$BUILD_DIR/dmg/LICENSE.txt"
cat > "$BUILD_DIR/dmg/安装说明.txt" <<'TXT'
Codex Meter

把 Codex Meter.app 拖入 Applications，然后从应用程序启动。
需要 macOS 13+，并在本机 Codex / ChatGPT / Codex CLI 登录自己的账号。
本版本尚未经过 Apple Developer ID 公证；首次打开可能需在系统设置的隐私与安全性中确认。
说明及源码：https://github.com/Haofei-Hu/codex-meter
TXT
hdiutil create -volname "Codex Meter" -srcfolder "$BUILD_DIR/dmg" -format UDZO -ov "$DIST_DIR/CodexMeter-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/CodexMeter-$VERSION-universal.zip"
(cd "$DIST_DIR" && shasum -a 256 "CodexMeter-$VERSION-universal.dmg" "CodexMeter-$VERSION-universal.zip" > SHA256SUMS.txt)
print "Release files: $DIST_DIR"
