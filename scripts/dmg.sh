#!/usr/bin/env bash
# Packs build/Fastlight.app into build/Fastlight-<version>.dmg. Opening it
# shows a branded window (assets/dmg/background.tiff) with the app on the left
# and an /Applications link on the right to drag it onto. Run
# scripts/bundle.sh first (`make dmg` does). The DMG is signed when
# CODESIGN_IDENTITY is a real identity.
#
# The window layout lives in the volume's .DS_Store, written by dmgbuild
# (scripts/dmg-settings.py). dmgbuild writes it directly, without Finder:
# create-dmg and similar tools script Finder over AppleScript, which needs a
# logged-in GUI session and is flaky on headless CI runners. dmgbuild runs
# through uv, or a throwaway venv when there is no uv. If neither works
# locally, this falls back to a plain DMG (no background or layout) with a
# warning; in CI (CI=true) it fails instead, so releases always get the
# branded window.
set -euo pipefail

cd "$(dirname "$0")/.."
app=build/Fastlight.app
if [ ! -d "$app" ]; then
  echo "error: $app not found; run scripts/bundle.sh first" >&2
  exit 1
fi

# Pinned, with their dependencies, so a release doesn't change by itself.
dmgbuild_pkgs=(dmgbuild==1.6.7 ds_store==1.3.3 mac_alias==2.2.3)

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="build/Fastlight-$version.dmg"
volname="Fastlight $version"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Runs dmgbuild with the given arguments; returns non-zero if it can't run.
dmgbuild() {
  if command -v uv >/dev/null; then
    local with=()
    for p in "${dmgbuild_pkgs[@]}"; do with+=(--with "$p"); done
    uv run --quiet --no-project --python '>=3.10' "${with[@]}" python -m dmgbuild "$@"
    return
  fi
  # dmgbuild needs Python 3.10+; the Command Line Tools' python3 is older.
  local py
  for py in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$py" >/dev/null &&
      "$py" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
      "$py" -m venv "$tmp/venv" &&
        "$tmp/venv/bin/python" -m pip install --quiet --disable-pip-version-check "${dmgbuild_pkgs[@]}" &&
        "$tmp/venv/bin/python" -m dmgbuild "$@"
      return
    fi
  done
  echo "dmgbuild needs uv or Python 3.10+" >&2
  return 1
}

fancy() {
  dmgbuild -s scripts/dmg-settings.py \
    -D app="$app" \
    -D background=assets/dmg/background.tiff \
    -D volume_icon="$app/Contents/Resources/AppIcon.icns" \
    --no-hidpi "$volname" "$dmg"
}

plain() {
  local stage="$tmp/stage"
  mkdir -p "$stage"
  # ditto keeps the signature's extended attributes and symlinks intact.
  ditto "$app" "$stage/Fastlight.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "$volname" -srcfolder "$stage" -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 -ov "$dmg" >/dev/null
}

rm -f "$dmg"
if ! fancy; then
  rm -f "$dmg"
  if [ "${CI:-}" = true ]; then
    echo "error: couldn't build the styled DMG with dmgbuild" >&2
    exit 1
  fi
  echo "warning: couldn't build the styled DMG with dmgbuild; building a plain one" >&2
  echo "warning: install uv (brew install uv) or Python 3.10+ for the branded window" >&2
  plain
fi

identity="${CODESIGN_IDENTITY:--}"
if [ "$identity" != "-" ]; then
  codesign --force --sign "$identity" --timestamp "$dmg"
fi

echo "$dmg"
