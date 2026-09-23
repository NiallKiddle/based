#!/bin/bash
# Builds dist/Based.app (universal: Apple Silicon + Intel), plus Based.dmg and Based.zip.
# Usage: ./scripts/build.sh [version]      Needs Xcode or Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
DIST="dist"
APP="$DIST/Based.app"
MIN_OS="13.0"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST/obj"

echo "→ Compiling (arm64 + x86_64)…"
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos$MIN_OS" \
    Sources/Based.swift -o "$DIST/obj/Based-$ARCH"
done
lipo -create "$DIST/obj/Based-arm64" "$DIST/obj/Based-x86_64" -output "$APP/Contents/MacOS/Based"

cp Resources/Based.icns "$APP/Contents/Resources/Based.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Based</string>
  <key>CFBundleDisplayName</key><string>Based</string>
  <key>CFBundleIdentifier</key><string>com.niallkiddle.based</string>
  <key>CFBundleExecutable</key><string>Based</string>
  <key>CFBundleIconFile</key><string>Based</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© Niall Kiddle</string>
</dict>
</plist>
PLIST

# Optional: Developer ID signing + notarization (set these env vars / GitHub secrets)
#   SIGN_IDENTITY   e.g. "Developer ID Application: Niall Kiddle (TEAMID)"
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   for notarization
notarize() {
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "→ Notarizing $(basename "$1")…"
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" --wait
    return 0
  fi
  return 1
}

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "→ Signing with Developer ID…"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  if notarize "$DIST/notarize.zip"; then xcrun stapler staple "$APP"; fi
  rm -f "$DIST/notarize.zip"
else
  echo "→ Signing (ad-hoc)…"
  codesign --force --sign - "$APP"
fi

echo "→ Packaging…"
ditto -c -k --keepParent "$APP" "$DIST/Based.zip"

# Pretty drag-to-install DMG via dmgbuild (no Finder scripting, so it works on CI).
# dmgbuild picks up background@2x.png automatically for Retina.
VENV="$DIST/.venv"
if python3 -m venv "$VENV" >/dev/null 2>&1 \
   && "$VENV/bin/pip" install -q --disable-pip-version-check dmgbuild >/dev/null 2>&1; then
  "$VENV/bin/dmgbuild" -s scripts/dmg_settings.py \
    -D app="$APP" -D background=Resources/dmg/background.png -D icon=Resources/Based.icns \
    "Based" "$DIST/Based.dmg"
else
  echo "  (dmgbuild unavailable — building a plain DMG)"
  STAGE="$DIST/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Based" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Based.dmg" >/dev/null
  rm -rf "$STAGE"
fi
rm -rf "$VENV" "$DIST/obj"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/Based.dmg"
  if notarize "$DIST/Based.dmg"; then xcrun stapler staple "$DIST/Based.dmg"; fi
fi

echo "✓ Built $APP ($VERSION) → $DIST/Based.dmg"
