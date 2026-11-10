#!/bin/sh
# Builds a universal (Apple Silicon + Intel) app and packs it into a DMG with an
# Applications link. The app gets an ad-hoc signature (no Apple notarization).
#
#   Scripts/build-dmg.sh [output directory, default build/dmg]
set -e
cd "$(dirname "$0")/.."
out=${1:-build/dmg}
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
dmg="$out/Railcast-$version-universal.dmg"

Scripts/build-app.sh

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto build/Railcast.app "$stage/Railcast.app"
# build-app.sh builds for this Mac only. Resources are the same, so only the executable is replaced.
for arch in arm64 x86_64; do swift build -c release --product Railcast --arch "$arch"; done
lipo -create .build/arm64-apple-macosx/release/Railcast .build/x86_64-apple-macosx/release/Railcast \
  -output "$stage/Railcast.app/Contents/MacOS/Railcast"
codesign --force --sign - "$stage/Railcast.app"
codesign --verify --deep --strict "$stage/Railcast.app"
ln -s /Applications "$stage/Applications"

mkdir -p "$out"
# hdiutil sometimes fails with "Resource busy" on CI runners; a repeat clears it.
tries=0
until hdiutil create -volname "Railcast $version" -srcfolder "$stage" -ov -format UDZO "$dmg"; do
  tries=$((tries + 1))
  [ "$tries" -lt 4 ] || exit 1
  sleep 5
done
echo "$dmg"
