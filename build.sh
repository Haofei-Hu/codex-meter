#!/bin/zsh
set -eu
ROOT=${0:A:h}
BUILD_DIR="${CODEX_METER_BUILD_DIR:-$ROOT/build}"
APP="$BUILD_DIR/Codex Meter.app"
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
TARGET_VERSION="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
ARCHS="${ARCHS:-$(uname -m)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/objects"
BINARIES=()
for ARCH in ${(z)ARCHS}; do
    BINARY="$BUILD_DIR/objects/CodexMeter-$ARCH"
    swiftc -swift-version 5 -O -target "$ARCH-apple-macos$TARGET_VERSION" \
        -framework AppKit -framework SwiftUI -framework ServiceManagement \
        "$ROOT"/Source/*.swift -o "$BINARY"
    BINARIES+=("$BINARY")
    if [[ "$ARCH" == "$(uname -m)" ]]; then "$BINARY" --self-test; fi
done
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/CodexQuota"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexQuota</string>
<key>CFBundleIdentifier</key><string>local.codexquota.mac</string>
<key>CFBundleName</key><string>Codex Meter</string>
<key>CFBundleDisplayName</key><string>Codex Meter</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>29</string>
<key>LSMinimumSystemVersion</key><string>$TARGET_VERSION</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright 2026 Haofei-Hu. MIT License.</string>
</dict></plist>
PLIST
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/Assets/MakeIcon.swift" "$BUILD_DIR/AppIcon.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$BUILD_DIR/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$BUILD_DIR/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
print "Built $APP ($ARCHS, macOS $TARGET_VERSION+)"
