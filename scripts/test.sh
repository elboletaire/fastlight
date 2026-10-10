#!/usr/bin/env bash
# `swift test`, plus the Swift Testing macro plugin path that SwiftPM misses
# when only the Command Line Tools are installed. Harmless with Xcode.
set -euo pipefail

cd "$(dirname "$0")/.."
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
