#!/usr/bin/env bash
# Installs the latest Nook release into /Applications.
# Usage: curl -fsSL https://raw.githubusercontent.com/octavio1199/nook/main/scripts/install.sh | bash
set -euo pipefail

URL="https://github.com/octavio1199/nook/releases/latest/download/Nook.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Nook…"
curl -fsSL "$URL" -o "$TMP/Nook.zip"
ditto -x -k "$TMP/Nook.zip" "$TMP"

pkill -x Nook 2>/dev/null || true
rm -rf /Applications/Nook.app
mv "$TMP/Nook.app" /Applications/Nook.app
# The build is ad-hoc signed (not notarized), so clear the download quarantine flag.
xattr -dr com.apple.quarantine /Applications/Nook.app 2>/dev/null || true

open /Applications/Nook.app
echo "Nook installed. Hover the notch or press ⌃⌥N."
