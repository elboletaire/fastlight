#!/usr/bin/env bash
# Builds build/Fastlight.app: the SwiftPM executable plus the vendored fsearch
# daemon, so the app needs nothing else installed. No Xcode needed.
#
#   scripts/bundle.sh [--universal] [debug|release]
#
#   UNIVERSAL=1          arm64 + x86_64 (same as --universal)
#   CODESIGN_IDENTITY    signing identity; "-" (ad-hoc) by default. A real
#                        identity also turns on the hardened runtime and a
#                        secure timestamp, as notarization requires.
set -euo pipefail

cd "$(dirname "$0")/.."
config=release
universal="${UNIVERSAL:-0}"
for arg in "$@"; do
  case "$arg" in
    --universal) universal=1 ;;
    debug|release) config="$arg" ;;
    *) echo "usage: $0 [--universal] [debug|release]" >&2; exit 2 ;;
  esac
done
identity="${CODESIGN_IDENTITY:--}"

# fsearch first: it's the step most likely to fail (no Rust), and fails fast.
if [ "$universal" = 1 ]; then
  fsearch="$(scripts/build-fsearch.sh --universal)"
else
  fsearch="$(scripts/build-fsearch.sh)"
fi

# Several --arch flags yield one fat binary. That needs Xcode or Swift 6.2+
# (whose bundled build system handles it); per-arch builds can't be lipo'd
# instead, as newer toolchains put every arch in the same bin path.
swift_flags=(-c "$config")
if [ "$universal" = 1 ]; then
  swift_flags+=(--arch arm64 --arch x86_64)
fi
swift build "${swift_flags[@]}" --product Fastlight
bin="$(swift build "${swift_flags[@]}" --show-bin-path)/Fastlight"

app=build/Fastlight.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin" "$app/Contents/MacOS/Fastlight"
# Helpers/, not MacOS/: Contents/MacOS is for the bundle's main executable,
# and Apple's bundle layout reserves Contents/Helpers for helper tools.
cp "$fsearch" "$app/Contents/Helpers/fsearch"

# Artwork is optional so the bundle still builds without it.
for f in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png; do
  if [ -f "Resources/$f" ]; then cp "Resources/$f" "$app/Contents/Resources/$f"; fi
done

# Inside out: the helper first, then the app, whose seal covers the helper's
# signature. --deep would re-sign the helper without its identifier, so don't.
sign_flags=(--force --sign "$identity")
if [ "$identity" != "-" ]; then
  sign_flags+=(--options runtime --timestamp)
fi
codesign "${sign_flags[@]}" --identifier com.elboletaire.fastlight.fsearch "$app/Contents/Helpers/fsearch"
codesign "${sign_flags[@]}" "$app"
codesign --verify --deep --strict "$app"

# Ad-hoc signatures change with every build, and Full Disk Access is tied to
# the signature: re-grant it after rebuilding (or sign with a real identity).
echo "$app"
