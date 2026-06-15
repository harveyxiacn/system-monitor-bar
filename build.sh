#!/bin/bash
set -e
APP_NAME="SystemMonitorBar"
echo "=== Building $APP_NAME ==="
swift build -c release 2>&1
echo "=== Packaging .app ==="
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
cp .build/release/"$APP_NAME" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
cat > "$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SystemMonitorBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.systemmonitor.bar</string>
    <key>CFBundleName</key>
    <string>SystemMonitorBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
echo "=== Done ==="
echo "App at: $(pwd)/$APP_NAME.app"
echo "Run: open $APP_NAME.app"
