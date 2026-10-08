#!/usr/bin/env bash
# Packages build/3Fingers.app into build/3Fingers.dmg (drag-to-Applications layout).
# Run scripts/build_app.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/3Fingers.app"
DMG="$ROOT/build/3Fingers.dmg"
STAGING="$ROOT/build/dmg-staging"

[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/build_app.sh first" >&2; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "3Fingers" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"

rm -rf "$STAGING"
echo "==> Done: $DMG"
