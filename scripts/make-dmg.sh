#!/bin/bash
# Packages SystemMonitorBar.app into a distributable .dmg with a drag-to-
# Applications layout. Run ./build.sh first so the .app exists.
#
#   ./scripts/make-dmg.sh            # -> SystemMonitorBar.dmg
#   VERSION=1.1.0 ./scripts/make-dmg.sh   # -> SystemMonitorBar-1.1.0.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="SystemMonitorBar.app"
VERSION="${VERSION:-}"
DMG="SystemMonitorBar${VERSION:+-$VERSION}.dmg"
VOL="System Monitor Bar"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found — run ./build.sh first" >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Unsigned/un-notarized apps are quarantined on download. Ship a short note so
# users know the one-time step to open it.
cat > "$STAGING/如何打开 How to Open.txt" << 'NOTE'
System Monitor Bar
==================

中文
----
1. 把 SystemMonitorBar 拖到旁边的 Applications 文件夹。
2. 首次打开：在「应用程序」里【右键点击 SystemMonitorBar → 打开】，
   在弹窗里再次点「打开」。
3. 如果提示“已损坏 / 无法验证开发者”，打开「终端」执行一次：
       xattr -dr com.apple.quarantine /Applications/SystemMonitorBar.app
   然后正常双击打开即可。

本应用是开源、未做苹果付费公证的程序，以上是系统对未公证应用的正常拦截，
执行一次后不再提示。源码：https://github.com/harveyxiacn/system-monitor-bar

English
-------
1. Drag SystemMonitorBar onto the Applications folder shown here.
2. First launch: in Applications, right-click SystemMonitorBar -> Open,
   then click Open in the dialog.
3. If macOS says it is "damaged" or "cannot verify the developer", run this
   once in Terminal:
       xattr -dr com.apple.quarantine /Applications/SystemMonitorBar.app
   Then open it normally.

This is open-source software that is not paid-notarized by Apple; the prompt is
macOS's normal handling of un-notarized apps and only appears once.
NOTE

rm -f "$DMG"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "Wrote $DMG"
