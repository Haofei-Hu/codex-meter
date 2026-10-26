#!/bin/zsh
set -eu
ROOT=${0:A:h:h}
BUILD_DIR="${CODEX_METER_BUILD_DIR:-$ROOT/build}"
DIST_DIR="${CODEX_METER_DIST_DIR:-$ROOT/dist}"
APP="$BUILD_DIR/Codex Meter.app"
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
[[ -d "$APP" ]] || ARCHS="arm64 x86_64" "$ROOT/build.sh"
mkdir -p "$DIST_DIR" "$BUILD_DIR/dmg" "$BUILD_DIR/pkg-root" "$BUILD_DIR/pkg-scripts"
ditto "$APP" "$BUILD_DIR/pkg-root/Codex Meter.app"
HELPERS=()
for ARCH in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$ARCH-apple-macos13.0" -framework SystemConfiguration "$ROOT/Installer/main.swift" -o "$BUILD_DIR/objects/InstallerSupport-$ARCH"
    HELPERS+=("$BUILD_DIR/objects/InstallerSupport-$ARCH")
done
lipo -create "${HELPERS[@]}" -output "$BUILD_DIR/pkg-scripts/InstallerSupport"
python3 "$ROOT/scripts/test-installer.py" "$BUILD_DIR/pkg-scripts/InstallerSupport"
for STAGE in preinstall postinstall; do
    ACTION=prepare
    [[ "$STAGE" == postinstall ]] && ACTION=finish
    cat > "$BUILD_DIR/pkg-scripts/$STAGE" <<SH
#!/bin/sh
set -eu
SCRIPT_DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
exec "\$SCRIPT_DIR/InstallerSupport" "$ACTION" "$VERSION"
SH
    chmod 755 "$BUILD_DIR/pkg-scripts/$STAGE"
done
cat > "$BUILD_DIR/components.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
<key>RootRelativeBundlePath</key><string>Codex Meter.app</string>
<key>BundleIsRelocatable</key><false/>
<key>BundleHasStrictIdentifier</key><true/>
<key>BundleIsVersionChecked</key><true/>
<key>BundleOverwriteAction</key><string>upgrade</string>
</dict></array></plist>
PLIST
pkgbuild --root "$BUILD_DIR/pkg-root" --component-plist "$BUILD_DIR/components.plist" --scripts "$BUILD_DIR/pkg-scripts" --install-location /Applications --identifier local.codexquota.mac.installer --version "$VERSION" "$DIST_DIR/CodexMeter-$VERSION-universal.pkg"

ditto "$APP" "$BUILD_DIR/dmg/Codex Meter.app"
ln -sfn /Applications "$BUILD_DIR/dmg/Applications"
cp "$ROOT/LICENSE" "$BUILD_DIR/dmg/LICENSE.txt"
cat > "$BUILD_DIR/dmg/安装说明.txt" <<'TXT'
Codex Meter

推荐运行同一版本的 .pkg 安装包：它会自动停止并替换旧版、把同一用户应用目录的旧副本移入废纸篓，保留设置与登录。
DMG / ZIP 为手动安装方式，不执行自动清理。
需要 macOS 13+，并在本机 Codex / ChatGPT / Codex CLI 登录自己的账号。
本版本尚未经过 Apple Developer ID 公证；首次打开可能需在系统设置的隐私与安全性中确认。
说明及源码：https://github.com/Haofei-Hu/codex-meter
TXT
hdiutil create -volname "Codex Meter" -srcfolder "$BUILD_DIR/dmg" -format UDZO -ov "$DIST_DIR/CodexMeter-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/CodexMeter-$VERSION-universal.zip"
(cd "$DIST_DIR" && shasum -a 256 "CodexMeter-$VERSION-universal.dmg" "CodexMeter-$VERSION-universal.zip" "CodexMeter-$VERSION-universal.pkg" > SHA256SUMS.txt)
print "Release files: $DIST_DIR"
