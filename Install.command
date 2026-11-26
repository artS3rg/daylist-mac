#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    echo 'Установите инструменты Apple в открывшемся окне, затем снова запустите Install.command.'
    /usr/bin/xcode-select --install
    exit 0
fi
stage="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/Daylist.XXXXXX")"
trap '/bin/rm -rf "$stage"' EXIT
app="$stage/Дела.app"
/bin/mkdir -p "$app/Contents/MacOS" "$HOME/Applications"
/bin/cp Info.plist "$app/Contents/Info.plist"
echo 'Собираю «Дела» для Apple Silicon…'
/usr/bin/xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos13.0 Daylist.swift -o "$app/Contents/MacOS/Daylist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
target="$HOME/Applications/Дела.app"
if [[ -e "$target" ]]; then
    echo "Приложение уже существует: $target"
else
    /usr/bin/ditto "$app" "$target"
fi
/usr/bin/open "$target"
