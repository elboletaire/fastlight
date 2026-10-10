#!/usr/bin/env bash
# Packs build/Fastlight.app into build/Fastlight-<version>.dmg, with an
# /Applications link to drag it onto. Run scripts/bundle.sh first (`make dmg`
# does). The DMG is signed when CODESIGN_IDENTITY is a real identity.
set -euo pipefail

cd "$(dirname "$0")/.."
app=build/Fastlight.app
if [ ! -d "$app" ]; then
  echo "error: $app not found; run scripts/bundle.sh first" >&2
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="build/Fastlight-$version.dmg"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
# ditto keeps the signature's extended attributes and symlinks intact.
ditto "$app" "$stage/Fastlight.app"
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
hdiutil create -volname "Fastlight $version" -srcfolder "$stage" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$dmg" >/dev/null

identity="${CODESIGN_IDENTITY:--}"
if [ "$identity" != "-" ]; then
  codesign --force --sign "$identity" --timestamp "$dmg"
fi

echo "$dmg"
