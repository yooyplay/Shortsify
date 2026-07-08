#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# ── Build binary ──────────────────────────────────────────────────────────────
echo "Building…"
swift build -c release 2>&1

# ── Generate icon ─────────────────────────────────────────────────────────────
echo "Generating icon…"
swift make-icon.swift /tmp/shortsify-icon-src.png

mkdir -p /tmp/shortsify.iconset
for size in 16 32 64 128 256 512; do
    sips -z $size $size /tmp/shortsify-icon-src.png \
         --out /tmp/shortsify.iconset/icon_${size}x${size}.png     > /dev/null
    double=$((size * 2))
    sips -z $double $double /tmp/shortsify-icon-src.png \
         --out /tmp/shortsify.iconset/icon_${size}x${size}@2x.png  > /dev/null
done
iconutil -c icns /tmp/shortsify.iconset -o /tmp/AppIcon.icns

# ── Assemble .app bundle ──────────────────────────────────────────────────────
APP="Shortsify.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/Shortsify "$APP/Contents/MacOS/Shortsify"
cp /tmp/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Shortsify</string>
    <key>CFBundleIdentifier</key>
    <string>com.shortsify.app</string>
    <key>CFBundleName</key>
    <string>Shortsify</string>
    <key>CFBundleDisplayName</key>
    <string>Shortsify</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.video</string>
                <string>public.mpeg-4</string>
                <string>com.apple.quicktime-movie</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# ── Ad-hoc code sign (avoids "damaged" Gatekeeper error) ─────────────────────
echo "Signing…"
codesign --deep --force --sign - "$APP"

# ── Build DMG (with drag-to-Applications window) ──────────────────────────────
echo "Building DMG..."

DMG="Shortsify.dmg"
RW_DMG="/tmp/shortsify-rw.dmg"
VOL="/tmp/shortsify-vol"
BG_IMG="/tmp/dmg-bg.png"

swift make-dmg-bg.swift "$BG_IMG"

# Unmount any leftover volume from a previous run
hdiutil detach "/Volumes/Shortsify" -quiet 2>/dev/null || true

# Create a writable DMG
rm -f "$RW_DMG"
hdiutil create -size 300m -fs HFS+ -volname "Shortsify" "$RW_DMG" > /dev/null
hdiutil attach "$RW_DMG" -quiet
sleep 3

VOL="/Volumes/Shortsify"

# Populate (ditto preserves code-signature xattrs)
ditto "$APP" "$VOL/Shortsify.app"
ln -sf /Applications "$VOL/Applications"
mkdir -p "$VOL/.background"
cp "$BG_IMG" "$VOL/.background/bg.png"

# Configure window with AppleScript (positions, background, icon size)
osascript << APPLESCRIPT
tell application "Finder"
  tell disk "Shortsify"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 550}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set background picture of viewOptions to file ".background:bg.png"
    set position of item "Shortsify.app" of container window to {160, 200}
    set position of item "Applications" of container window to {440, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Unmount and compress
hdiutil detach "$VOL" -quiet
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" -ov > /dev/null
rm -f "$RW_DMG"

echo ""
echo "✅ Built: $(pwd)/$APP"
echo "✅ Built: $(pwd)/$DMG"
echo ""
echo "To run:    open $APP"
echo "To ship:   upload $DMG to GitHub Releases"
