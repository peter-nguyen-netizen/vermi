#!/bin/bash
#
# Build Vermi.app from a release build and package it into Vermi.dmg.
#
# Usage:
#   ./scripts/build-dmg.sh
#
# IMPORTANT: this ALWAYS compiles the release binary first. `swift build`
# (debug) does NOT update .build/release, so packaging without this step ships
# a stale binary. Do not remove the `swift build -c release` line.
#
set -euo pipefail

# Project root = parent of this script's directory (portable, no hardcoded path).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REL="$ROOT/.build/release"
APP="$ROOT/dist/Vermi.app"
DMG="$ROOT/Vermi.dmg"

echo "==> Building release binary…"
( cd "$ROOT" && swift build -c release )

echo "==> Assembling Vermi.app…"
rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Executable
cp "$REL/Vermi" "$APP/Contents/MacOS/Vermi"
chmod +x "$APP/Contents/MacOS/Vermi"

# SPM resource bundle (Bundle.module finds it in Contents/Resources)
cp -R "$REL/RedisClient_RedisClient.bundle" "$APP/Contents/Resources/"

# Icon
cp "$ROOT/RedisClient/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Info.plist (concrete executable name + icon)
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Vermi</string>
    <key>CFBundleIdentifier</key><string>io.clearer.vermi</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Vermi</string>
    <key>CFBundleDisplayName</key><string>Vermi</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Clearer.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so Gatekeeper lets it run locally
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "codesign skipped"

echo "==> Building DMG…"
STAGE="$ROOT/dist/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Vermi" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "APP: $APP"
echo "DMG: $DMG"
ls -lh "$DMG"
echo "binary: $(stat -f '%Sm' "$APP/Contents/MacOS/Vermi")"
