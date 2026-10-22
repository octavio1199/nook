#!/usr/bin/env bash
# Packages build/Nook.app into build/Nook.dmg with a drag-to-Applications window.
# Run scripts/bundle.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Nook.app
DMG=build/Nook.dmg
VOL=Nook
[ -d "$APP" ] || { echo "error: $APP not found, run scripts/bundle.sh first" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Background (1x + 2x in one TIFF so Retina displays get the sharp one).
swift scripts/make-dmg-background.swift "$WORK/bg.png" 1
swift scripts/make-dmg-background.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/background.tiff" >/dev/null 2>&1

mkdir -p "$WORK/stage/.background"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
cp "$WORK/background.tiff" "$WORK/stage/.background/background.tiff"

hdiutil create -quiet -volname "$VOL" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
mkdir -p "$WORK/mnt"
hdiutil attach -quiet -nobrowse -noautoopen -readwrite -mountpoint "$WORK/mnt" "$WORK/rw.dmg"

# Window layout via Finder. Needs Automation permission for Finder; skipped if denied.
if ! osascript <<OSA
tell application "Finder"
    set d to (POSIX file "$WORK/mnt" as alias)
    open d
    set w to container window of d
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 860, 548}
    delay 1
    set o to icon view options of w
    set arrangement of o to not arranged
    set icon size of o to 112
    set text size of o to 13
    set background picture of o to (POSIX file "$WORK/mnt/.background/background.tiff" as alias)
    set position of item "Nook.app" of w to {180, 200}
    set position of item "Applications" of w to {480, 200}
    set bounds of w to {200, 120, 860, 548}
    update d without registering applications
    delay 2
    close w
end tell
OSA
then
  echo "warning: Finder layout skipped (no Automation permission); the DMG still works." >&2
fi

chflags hidden "$WORK/mnt/.background" 2>/dev/null || true
sync
hdiutil detach -quiet "$WORK/mnt"
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "$PWD/$DMG"
