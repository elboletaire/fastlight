#!/usr/bin/env bash
# Render Fastlight brand assets from the SVG sources in assets/brand/.
#
#   scripts/render-brand.sh          # SVG -> PNGs, AppIcon.icns, menu bar icons
#   scripts/render-brand.sh --svg    # first regenerate the SVGs (needs uv + network)
#
# Requires resvg (brew install resvg) and iconutil (ships with macOS).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
brand="$root/assets/brand"
src="$brand/src"
png="$brand/png"
res="$root/Resources"

command -v resvg >/dev/null || { echo "resvg not found: brew install resvg" >&2; exit 1; }

if [[ "${1:-}" == "--svg" ]]; then
  command -v uv >/dev/null || { echo "uv not found (needed for fontTools)" >&2; exit 1; }
  fontdir="$(mktemp -d)"
  trap 'rm -rf "$fontdir"' EXIT
  curl -fsSL -o "$fontdir/Sora.ttf" \
    "https://github.com/google/fonts/raw/main/ofl/sora/Sora%5Bwght%5D.ttf"
  uv run --quiet --with fonttools python "$src/generate.py" "$fontdir/Sora.ttf" "$brand"
fi

r() { resvg -w "$2" -h "$2" "$1" "$3"; }

mkdir -p "$png" "$res"

# App icon PNGs
for s in 1024 512 256 128; do r "$brand/app-icon.svg" "$s" "$png/app-icon-$s.png"; done

# Mark PNGs (transparent, square) and favicons
for s in 512 192; do
  r "$src/mark-square.svg" "$s" "$png/mark-$s.png"
  r "$src/mark-square-dark.svg" "$s" "$png/mark-dark-$s.png"
done
r "$src/apple-touch-icon.svg" 180 "$png/apple-touch-icon-180.png"
r "$brand/favicon.svg" 32 "$png/favicon-32.png"
r "$brand/favicon.svg" 16 "$png/favicon-16.png"

# Lockups (for README / social previews)
resvg -h 160 "$brand/logo-lockup.svg" "$png/logo-lockup.png"
resvg -h 160 "$brand/logo-lockup-dark.svg" "$png/logo-lockup-dark.png"

# AppIcon.icns: 16 and 32 px slots use the simplified glyph
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  d=$((s * 2))
  big="$brand/app-icon.svg"
  [[ $s -le 32 ]] && one="$src/app-icon-small.svg" || one="$big"
  [[ $d -le 32 ]] && two="$src/app-icon-small.svg" || two="$big"
  r "$one" "$s" "$iconset/icon_${s}x${s}.png"
  r "$two" "$d" "$iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns -o "$res/AppIcon.icns" "$iconset"
rm -rf "$(dirname "$iconset")"

# Menu bar template glyph (alpha only)
resvg "$src/menubar-18.svg" "$res/MenuBarIcon.png"
resvg "$src/menubar-36.svg" "$res/MenuBarIcon@2x.png"

echo "Brand assets rendered."
