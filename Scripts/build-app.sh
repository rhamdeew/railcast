#!/bin/bash
# Builds build/Railcast.app. Signs with the first Apple Development certificate,
# because a stable signature keeps the Accessibility permission across rebuilds.
# Falls back to ad-hoc signing. RAILCAST_SIGN_IDENTITY overrides the choice.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product Railcast
binary="$(swift build -c release --show-bin-path)/Railcast"

app=build/Railcast.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Railcast"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/emoji.json Resources/AppIcon.icns Resources/MenuBarIcon.png "$app/Contents/Resources/"
detected="$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }')"
codesign --force --sign "${RAILCAST_SIGN_IDENTITY:-${detected:--}}" "$app"
echo "$app"
