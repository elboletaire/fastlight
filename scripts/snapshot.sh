#!/usr/bin/env bash
# Renders the panel with sample data to build/snapshots/*.png (light and
# dark), for visual QA and the website. Needs no screen-recording permission.
# Extra arguments are real queries to render against the running daemon:
#   scripts/snapshot.sh invoice "readme in:~/src"
# --language renders in another language, into build/snapshots/<lang>;
# --only keeps the scenes whose names start with one of its prefixes:
#   scripts/snapshot.sh --language ca --only settings,about,convert
set -euo pipefail

cd "$(dirname "$0")/.."
out=build/snapshots
flags=()
while [ $# -gt 0 ]; do
  case "$1" in
    --language) out="build/snapshots/$2"; flags+=(--language "$2"); shift 2 ;;
    --only) flags+=(--only "$2"); shift 2 ;;
    *) flags+=(--query "$1"); shift ;;
  esac
done
swift build
"$(swift build --show-bin-path)/Fastlight" --snapshot "$out" ${flags[@]+"${flags[@]}"}
