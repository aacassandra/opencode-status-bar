#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="OpenCodeStatusBar"
APP_PATH="build/$APP_NAME.app"
VERSION="1.1.4"
DMG_NAME="build/${APP_NAME}-${VERSION}.dmg"
STAGING="build/dmg-staging"
DMG_TMP="build/${APP_NAME}-tmp.dmg"
BG_SCRIPT="build/gen-bg.swift"
BG_PNG="build/dmg-bg.png"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH not found. Run build.sh first."
  exit 1
fi

rm -rf "$STAGING" "$DMG_TMP" "$DMG_NAME" "$BG_PNG"

cat > "$BG_SCRIPT" <<'SWIFT'
import Cocoa
let size = NSSize(width: 540, height: 380)
let img = NSImage(size: size, flipped: false) { rect in
    let grad = NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1),
                          ending: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1))
    grad?.draw(in: rect, angle: -45)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 22),
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
    ]
    let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    "OpenCode Status Bar".draw(at: NSPoint(x: 0, y: rect.height - 50), withAttributes: titleAttrs)
    let verAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor.gray,
        .paragraphStyle: para,
    ]
    "Version \(ver)".draw(at: NSPoint(x: 0, y: rect.height - 75), withAttributes: verAttrs)
    let instrAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor(srgbRed: 0.6, green: 0.6, blue: 0.65, alpha: 1),
        .paragraphStyle: para,
    ]
    "Drag OpenCode Status Bar to your Applications folder".draw(at: NSPoint(x: 0, y: 30), withAttributes: instrAttrs)
    let arrowPath = NSBezierPath()
    arrowPath.move(to: NSPoint(x: rect.width * 0.25 + 20, y: rect.height * 0.45))
    arrowPath.line(to: NSPoint(x: rect.width * 0.75 - 20, y: rect.height * 0.45))
    arrowPath.lineWidth = 2
    NSColor(srgbRed: 0.4, green: 0.4, blue: 0.5, alpha: 0.6).setStroke()
    arrowPath.stroke()
    let headPath = NSBezierPath()
    headPath.move(to: NSPoint(x: rect.width * 0.75 - 25, y: rect.height * 0.45 - 6))
    headPath.line(to: NSPoint(x: rect.width * 0.75 - 10, y: rect.height * 0.45))
    headPath.line(to: NSPoint(x: rect.width * 0.75 - 25, y: rect.height * 0.45 + 6))
    headPath.lineWidth = 2
    NSColor(srgbRed: 0.4, green: 0.4, blue: 0.5, alpha: 0.6).setStroke()
    headPath.stroke()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])
try? png?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

echo "Generating background image..."
if swiftc "$BG_SCRIPT" -o "${BG_SCRIPT%.swift}" -framework Cocoa 2>/dev/null && "${BG_SCRIPT%.swift}" "$BG_PNG" 2>/dev/null; then
    :
else
    echo "  Skipping background image (swiftc not available)"
fi

echo "Stage DMG contents..."
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating DMG..."
rm -f "$DMG_TMP"
hdiutil create -fs HFS+ -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -format UDRW \
  -size 64m \
  "$DMG_TMP" >/dev/null

echo "Configuring DMG window..."
MOUNT_POINT="/Volumes/$APP_NAME"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" | grep "$MOUNT_POINT" | awk '{print $1}')

sleep 2

osascript <<EOF
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {400, 100, 940, 480}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    delay 1
    set position of item "$APP_NAME" of container window to {120, 180}
    set position of item "Applications" of container window to {420, 180}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

if [ -f "$BG_PNG" ]; then
  cp "$BG_PNG" "$MOUNT_POINT/.background.png" 2>/dev/null || true
  SetFile -a V "$MOUNT_POINT/.background.png" 2>/dev/null || true
  osascript <<EOF || true
tell application "Finder"
  tell disk "$APP_NAME"
    set background picture of container window to file ".background.png"
    close
  end tell
end tell
EOF
fi

sync
hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
sleep 1

if [ -f "$BG_PNG" ]; then
  hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_NAME" -imagekey zlib-level=9 >/dev/null
else
  hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_NAME" >/dev/null
fi
rm -f "$DMG_TMP"

echo "Built $DMG_NAME"

rm -rf "$STAGING" "${BG_SCRIPT%.swift}" "$BG_SCRIPT" 2>/dev/null || true
