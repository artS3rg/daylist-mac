#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:?Supply the destination .app path}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/LaunchAgents"
cp Info.plist "$app/Contents/"
cp LaunchAgents/*.plist "$app/Contents/Library/LaunchAgents/"
resources="$app/Contents/Resources"
mkdir -p "$resources"
for pig in Angry Planner Icon Painter Laptop; do
  sips -z 256 256 "Art/$pig.png" --out "$resources/$pig.png" >/dev/null
done
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
icons="$stage/Daylist.iconset"
mkdir "$icons"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Art/Icon.png --out "$icons/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Art/Icon.png --out "$icons/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icons" -o "$resources/Daylist.icns"
plutil -lint "$app/Contents/Info.plist" "$app"/Contents/Library/LaunchAgents/*.plist
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos13.0 Daylist.swift RichNotes.swift WakeReminders.swift -o "$app/Contents/MacOS/Daylist"
lipo "$app/Contents/MacOS/Daylist" -verify_arch arm64
codesign --force --sign - "$app"
codesign --verify --strict "$app"
