#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OpenCodeStatusBar.app"
BIN="$APP/Contents/MacOS/OpenCodeStatusBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "Compiling universal binary (arm64 + x86_64)…"
swiftc -O -target arm64-apple-macos12.0  Sources/*.swift -o "$BIN.arm64"  -framework Cocoa
swiftc -O -target x86_64-apple-macos12.0 Sources/*.swift -o "$BIN.x86_64" -framework Cocoa
lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"
rm -f "$BIN.arm64" "$BIN.x86_64"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OpenCodeStatusBar</string>
  <key>CFBundleDisplayName</key><string>OpenCode Status Bar</string>
  <key>CFBundleIdentifier</key><string>com.local.opencodestatusbar</string>
  <key>CFBundleExecutable</key><string>OpenCodeStatusBar</string>
  <key>CFBundleVersion</key><string>1.1.4</string>
  <key>CFBundleShortVersionString</key><string>1.1.4</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

mkdir -p "$APP/Contents/Resources"
cp plugin/statusbar.ts "$APP/Contents/Resources/statusbar.ts"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cp assets/completion.mp3 "$APP/Contents/Resources/completion.mp3" 2>/dev/null || true
cp assets/count.mp3 "$APP/Contents/Resources/count.mp3" 2>/dev/null || true
cp assets/tic-toc.wav "$APP/Contents/Resources/tic-toc.wav" 2>/dev/null || true

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
