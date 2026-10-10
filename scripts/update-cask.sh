#!/usr/bin/env bash
# Sets the version and sha256 of the Homebrew cask. The release workflow runs
# it on a copy of packaging/homebrew/tap/Casks/fastlight.rb inside the tap
# checkout; it works the same by hand.
#
#   scripts/update-cask.sh <version> <Fastlight-<version>.dmg | sha256> [cask]
#
# The cask defaults to packaging/homebrew/tap/Casks/fastlight.rb. Prints
# whether the file changed. Touches nothing but those two lines.
set -euo pipefail

usage() { echo "usage: $0 <version> <dmg-or-sha256> [cask]" >&2; exit 2; }
[ $# -ge 2 ] && [ $# -le 3 ] || usage

version="${1#v}"
src="$2"
cask="${3:-$(dirname "$0")/../packaging/homebrew/tap/Casks/fastlight.rb}"

if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "error: '$1' isn't a version like 0.5.0" >&2
  exit 1
fi

if [ -f "$src" ]; then
  if command -v sha256sum >/dev/null; then
    sha="$(sha256sum "$src" | awk '{print $1}')"
  else
    sha="$(shasum -a 256 "$src" | awk '{print $1}')"
  fi
else
  sha="$(printf '%s' "$src" | tr 'A-F' 'a-f')"
fi
if ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: '$src' is neither a file nor a sha256" >&2
  exit 1
fi

[ -f "$cask" ] || { echo "error: no cask at $cask" >&2; exit 1; }

# Exactly one top-level version and sha256 line, or the cask has changed
# shape (per-arch blocks, say) and this script needs to change with it.
for stanza in version sha256; do
  n="$(grep -cE "^  $stanza \"[^\"]*\"$" "$cask" || true)"
  if [ "$n" != 1 ]; then
    echo "error: expected one '  $stanza \"...\"' line in $cask, found $n" >&2
    exit 1
  fi
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v v="$version" -v s="$sha" '
  /^  version "[^"]*"$/ { print "  version \"" v "\""; next }
  /^  sha256 "[^"]*"$/  { print "  sha256 \"" s "\""; next }
  { print }
' "$cask" > "$tmp"

if cmp -s "$tmp" "$cask"; then
  echo "cask already at $version ($sha)"
else
  cat "$tmp" > "$cask"
  echo "cask set to $version ($sha)"
fi
