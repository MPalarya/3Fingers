#!/usr/bin/env bash
# Builds the arm64 SPM binary and wraps it in build/3Fingers.app.
#
#   VERSION=1.2.3 scripts/build_app.sh
#   CODESIGN_IDENTITY="Developer ID Application: …" scripts/build_app.sh   # default: ad-hoc
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.0.0}"
VERSION="${VERSION#v}"
BUNDLE_ID="com.3fingers.app"
APP="$ROOT/build/3Fingers.app"

echo "==> Building 3Fingers $VERSION (arm64, release)"
swift build --package-path "$ROOT" -c release --arch arm64
BIN_DIR="$(swift build --package-path "$ROOT" -c release --arch arm64 --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/3Fingers" "$APP/Contents/MacOS/3Fingers"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>3Fingers</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>3Fingers</string>
    <key>CFBundleDisplayName</key>
    <string>3Fingers</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
EOF
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (${CODESIGN_IDENTITY:-ad-hoc})"
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
