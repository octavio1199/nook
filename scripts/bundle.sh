#!/usr/bin/env bash
# Builds build/Nook.app (universal if possible, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Nook.app
if swift build -c release --arch arm64 --arch x86_64; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Nook"
  echo "Built universal binary (arm64 + x86_64)."
else
  echo "warning: universal build failed, falling back to the native architecture." >&2
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Nook"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nook"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon (optional): skipped silently if generation fails.
ICON_TMP="$(mktemp -d)"
if swift scripts/make-icon.swift "$ICON_TMP/icon.png" 2>/dev/null; then
  SET="$ICON_TMP/AppIcon.iconset"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICON_TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns" || true
fi
rm -rf "$ICON_TMP"

codesign --force --deep -s - --options runtime --entitlements Resources/Nook.entitlements "$APP"
codesign --verify --deep "$APP" && echo "Signature OK (ad-hoc)."
lipo -archs "$APP/Contents/MacOS/Nook" | sed 's/^/Architectures: /'
echo "$PWD/$APP"
