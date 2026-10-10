#!/usr/bin/env bash
# Renders the panel with sample data to build/snapshots/*.png (light and
# dark), for visual QA and the website. Needs no screen-recording permission.
# Extra arguments are real queries to render against the running daemon:
#   scripts/snapshot.sh invoice "readme in:~/src"
set -euo pipefail

cd "$(dirname "$0")/.."
out=build/snapshots
live=()
for q in "$@"; do live+=(--query "$q"); done
swift build
"$(swift build --show-bin-path)/Fastlight" --snapshot "$out" ${live[@]+"${live[@]}"}
