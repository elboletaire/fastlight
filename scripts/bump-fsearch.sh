#!/usr/bin/env bash
# Moves third_party/fsearch to the head of upstream's main and bumps the
# patch version (and build number) in Resources/Info.plist, as one commit.
# Does nothing when the pin is already current. The fsearch workflow runs it
# weekly and turns the commit into a PR; it works the same locally.
#
#   scripts/bump-fsearch.sh [upstream-ref]     # default: main
#
# Writes changed, version, old, new and notes (a Markdown list of the
# upstream commits) to $GITHUB_OUTPUT when set, else prints them.
set -euo pipefail

cd "$(dirname "$0")/.."
ref="${1:-main}"
sub=third_party/fsearch
plist=Resources/Info.plist
pb=/usr/libexec/PlistBuddy

output() { # key value
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1=$2" >> "$GITHUB_OUTPUT"; else echo "$1=$2"; fi
}

if [ ! -f "$sub/Cargo.toml" ]; then
  git submodule update --init "$sub"
fi
old="$(git ls-tree HEAD "$sub" | awk '{print $3}')"
git -C "$sub" fetch --quiet origin "$ref"
new="$(git -C "$sub" rev-parse FETCH_HEAD)"

if [ "$old" = "$new" ]; then
  echo "fsearch is up to date at ${old:0:7}"
  output changed false
  exit 0
fi
# Only ever forward: a pin ahead of upstream (or off its history) is left
# for a human to sort out.
if ! git -C "$sub" merge-base --is-ancestor "$old" "$new"; then
  echo "error: pinned ${old:0:7} isn't an ancestor of upstream $ref (${new:0:7})" >&2
  exit 1
fi
git -C "$sub" checkout --quiet "$new"

version="$($pb -c 'Print :CFBundleShortVersionString' "$plist")"
build="$($pb -c 'Print :CFBundleVersion' "$plist")"
IFS=. read -r major minor patch <<<"$version"
next="$major.$minor.$((patch + 1))"
$pb -c "Set :CFBundleShortVersionString $next" -c "Set :CFBundleVersion $((build + 1))" "$plist"

notes="$(mktemp)"
git -C "$sub" log --reverse --format='- [`%h`](https://github.com/noahdunnagan/fsearch/commit/%H) %s' "$old..$new" > "$notes"

# Just these two paths, whatever else happens to be staged.
git commit --quiet -m "build(deps): update fsearch to ${new:0:7} and bump to $next" \
  -m "Upstream changes: https://github.com/noahdunnagan/fsearch/compare/$old...$new" \
  -- "$sub" "$plist"

echo "fsearch ${old:0:7} -> ${new:0:7}, Fastlight $version -> $next"
output changed true
output version "$next"
output old "$old"
output new "$new"
output notes "$notes"
