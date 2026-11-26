#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:?Supply the destination .app path}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/LaunchAgents"
cp Info.plist "$app/Contents/"
cp LaunchAgents/*.plist "$app/Contents/Library/LaunchAgents/"
plutil -lint "$app/Contents/Info.plist" "$app"/Contents/Library/LaunchAgents/*.plist
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos13.0 Daylist.swift WakeReminders.swift -o "$app/Contents/MacOS/Daylist"
lipo "$app/Contents/MacOS/Daylist" -verify_arch arm64
codesign --force --sign - "$app"
codesign --verify --strict "$app"
