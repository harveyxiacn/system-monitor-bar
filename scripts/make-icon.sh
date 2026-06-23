#!/bin/bash
# Generates Resources/AppIcon.icns from a programmatically-drawn 1024px icon:
# a blue→indigo squircle with a white gauge glyph (matching the menu-bar icon).
# Re-run only when the artwork changes; the resulting .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/draw.swift" << 'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-rect (squircle) background, inset to leave the standard icon margin.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = rect.width * 0.225
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let colors = [
    NSColor(srgbRed: 0.18, green: 0.45, blue: 0.96, alpha: 1).cgColor,
    NSColor(srgbRed: 0.36, green: 0.24, blue: 0.86, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY),
                       options: [])
ctx.restoreGState()

// White gauge glyph, centered.
let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
if let base = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                      accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = CGRect(origin: .zero, size: base.size)
    base.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let drawRect = CGRect(x: (size - base.size.width) / 2,
                          y: (size - base.size.height) / 2,
                          width: base.size.width,
                          height: base.size.height)
    tinted.draw(in: drawRect)
}

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
let out = ProcessInfo.processInfo.environment["ICON_OUT"]!
try! png.write(to: URL(fileURLWithPath: out))
SWIFT

ICON_OUT="$WORK/icon_1024.png" swift "$WORK/draw.swift"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$px" "$px" "$WORK/icon_1024.png" --out "$ICONSET/icon_${name}.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
