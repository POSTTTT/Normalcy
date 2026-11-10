#!/bin/sh
# Builds dist/Normalcy.app and dist/Normalcy-<version>.zip from this package.
#   scripts/build-app.sh            version from the latest git tag (v0.1.0 -> 0.1.0)
#   scripts/build-app.sh 0.2.0      or as given
# Signed with the "Normalcy Signing" certificate when it's in the keychain (NORMALCY_SIGN_ID to use
# another), so macOS keeps Accessibility across builds and updates. Without it, ad hoc: macOS then
# asks for Accessibility again after every build. Either way it isn't notarized, so downloaded
# copies need right-click > Open once.
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
APP=dist/Normalcy.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Normalcy"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Normalcy"

# Icon: AppIcon.png -> AppIcon.icns, every size macOS asks for.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Sources/Normalcy/Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Sources/Normalcy/Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Normalcy</string>
  <key>CFBundleDisplayName</key><string>Normalcy</string>
  <key>CFBundleIdentifier</key><string>com.normalcy.Normalcy</string>
  <key>CFBundleExecutable</key><string>Normalcy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

SIGN_ID="${NORMALCY_SIGN_ID:-Normalcy Signing}"
if security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
  codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "warning: no \"$SIGN_ID\" certificate; signing ad hoc, so Accessibility resets with this build" >&2
  SIGN_ID="ad hoc"
  codesign --force --sign - "$APP"
fi
ditto -c -k --keepParent "$APP" "dist/Normalcy-$VERSION.zip"
echo "Built $APP and dist/Normalcy-$VERSION.zip ($VERSION, $(uname -m), signed: $SIGN_ID)"
