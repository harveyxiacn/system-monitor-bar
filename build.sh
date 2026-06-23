#!/bin/bash
# Builds SystemMonitorBar and packages it into a .app bundle.
#
#   ./build.sh                       # native-arch release build (local dev)
#   VERSION=1.2.0 ./build.sh         # override the marketing version
#   ARCH_FLAGS="--arch arm64 --arch x86_64" ./build.sh   # universal (needs full Xcode)
#
# Universal builds require a full Xcode install (the Command Line Tools alone
# lack xcbuild); CI sets ARCH_FLAGS to produce the universal release artifact.
set -euo pipefail

APP_NAME="SystemMonitorBar"
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH_FLAGS="${ARCH_FLAGS:-}"

echo "=== Building $APP_NAME $VERSION (build $BUILD_NUMBER) ${ARCH_FLAGS:+[$ARCH_FLAGS]} ==="
swift build -c release $ARCH_FLAGS

BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/$APP_NAME"

echo "=== Packaging .app ==="
APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.systemmonitor.bar</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>System Monitor Bar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
PLIST

echo "=== Ad-hoc code signing ==="
# Ad-hoc signing (-) lets the app run locally and after the quarantine attribute
# is removed; it is NOT notarization. Downloaded copies still need the Gatekeeper
# step documented in the README.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign unavailable — skipped)"

echo "=== Done ==="
echo "App at: $(pwd)/$APP"
echo "Run:    open $APP"
