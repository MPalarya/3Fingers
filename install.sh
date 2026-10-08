#!/usr/bin/env bash
# Installs the latest 3Fingers release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/MPalarya/3Fingers/main/install.sh | bash
set -euo pipefail

URL="https://github.com/MPalarya/3Fingers/releases/latest/download/3Fingers.dmg"
DEST="/Applications/3Fingers.app"

[[ "$(uname -m)" == "arm64" ]] || { echo "error: 3Fingers requires an Apple Silicon Mac" >&2; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ]] || { echo "error: 3Fingers requires macOS 14 or later" >&2; exit 1; }

TMP="$(mktemp -d)"
MOUNT="$TMP/mnt"
cleanup() {
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> Downloading 3Fingers"
curl -fL --progress-bar "$URL" -o "$TMP/3Fingers.dmg"

echo "==> Installing to $DEST"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$TMP/3Fingers.dmg"
pkill -x 3Fingers 2>/dev/null || true

SUDO=""
[[ -w /Applications ]] || SUDO="sudo"
$SUDO rm -rf "$DEST"
$SUDO ditto "$MOUNT/3Fingers.app" "$DEST"
$SUDO xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching 3Fingers (look for the hand icon in the menu bar)"
open "$DEST"
