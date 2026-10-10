#!/usr/bin/env bash
# Builds the vendored fsearch (third_party/fsearch) in release mode and prints
# the path of the resulting binary. UNIVERSAL=1 (or --universal) builds
# arm64 + x86_64 and lipos them together, as the release workflow does.
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
src="$root/third_party/fsearch"
target_dir="$root/.build/fsearch"

universal="${UNIVERSAL:-0}"
for arg in "$@"; do
  case "$arg" in
    --universal) universal=1 ;;
    *) echo "usage: $0 [--universal]" >&2; exit 2 ;;
  esac
done

if [ ! -f "$src/Cargo.toml" ]; then
  echo "error: $src is empty. Fetch the submodule first:" >&2
  echo "  git submodule update --init" >&2
  exit 1
fi

# rustup installs proxies that aren't always on PATH: Homebrew's rustup is
# keg-only, and the official installer may not have touched this shell's
# profile. Look in the usual places before giving up.
find_cargo() {
  if command -v cargo >/dev/null 2>&1; then command -v cargo; return; fi
  local dirs=("$HOME/.cargo/bin")
  if command -v brew >/dev/null 2>&1; then
    dirs+=("$(brew --prefix rustup 2>/dev/null)/bin")
  fi
  dirs+=(/opt/homebrew/opt/rustup/bin /usr/local/opt/rustup/bin)
  for d in "${dirs[@]}"; do
    if [ -x "$d/cargo" ]; then echo "$d/cargo"; return; fi
  done
  return 1
}

if ! cargo="$(find_cargo)"; then
  cat >&2 <<'MSG'
error: cargo not found. Building Fastlight needs Rust 1.85+ (for fsearch).
Install it with either:
  brew install rustup && "$(brew --prefix rustup)/bin/rustup" default stable
or:
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
then run this again.
MSG
  exit 1
fi
# cargo calls rustc by name; keep its directory on PATH.
export PATH="$(dirname "$cargo"):$PATH"

build() { # [triple]
  local args=(build --release --locked --manifest-path "$src/Cargo.toml" --target-dir "$target_dir")
  if [ -n "${1:-}" ]; then args+=(--target "$1"); fi
  "$cargo" "${args[@]}" >&2
}

if [ "$universal" = 1 ]; then
  triples=(aarch64-apple-darwin x86_64-apple-darwin)
  if command -v rustup >/dev/null 2>&1; then
    rustup target add "${triples[@]}" >&2
  fi
  slices=()
  for t in "${triples[@]}"; do
    build "$t"
    slices+=("$target_dir/$t/release/fsearch")
  done
  out="$target_dir/universal/fsearch"
  mkdir -p "$(dirname "$out")"
  lipo -create "${slices[@]}" -output "$out"
else
  build
  out="$target_dir/release/fsearch"
fi

echo "$out"
