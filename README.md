# Fastlight

A Spotlight-style launcher for macOS, powered by
[fsearch](https://github.com/noahdunnagan/fsearch): whole-disk file search
with fuzzy names, typo tolerance and indexed content search in about a
millisecond.

Press **⌥Space** anywhere, type, hit **↵**.

## Install

1. Download `Fastlight-<version>.dmg` from the
   [Releases](../../releases) page, open it and drag **Fastlight** onto
   **Applications**. Everything is inside the app, fsearch included; there is
   nothing else to install. Needs macOS 14 or later.
2. Open Fastlight. Release builds that aren't notarized are blocked the first
   time: go to System Settings → Privacy & Security and click **Open Anyway**.
3. Give Fastlight **Full Disk Access** in System Settings → Privacy & Security,
   or protected folders like Desktop, Documents and Mail are left out of the
   index.

Fastlight starts the bundled fsearch daemon itself, as a child process. macOS
generally holds the app that launched a helper responsible for the helper's
file access, so the Full Disk Access grant for Fastlight should cover the
daemon too. Two caveats:

- The daemon keeps running after Fastlight quits and is reused next time. If
  it was started before you granted access, quit Fastlight, run
  `pkill -f 'fsearch serve'` and open Fastlight again so it rescans.
- If a daemon is already running from a standalone fsearch install (say,
  `fsearch install --login`), Fastlight uses that one instead, and the grant
  that matters is the one for that `fsearch` binary.

Ad-hoc signed builds get a new signature on every rebuild, and macOS ties the
grant to it: re-grant Full Disk Access after updating such a build.

## Build

Needs the Swift 6 toolchain (the Command Line Tools are enough; Xcode is not
needed) and Rust 1.85+ for fsearch:

```sh
brew install rustup && "$(brew --prefix rustup)/bin/rustup" default stable
```

The build scripts find `cargo` in `~/.cargo/bin` or Homebrew's keg-only
rustup without it being on `PATH`. Then:

```sh
git clone --recursive <this repo> && cd fastlight
make               # -> build/Fastlight.app, fsearch embedded
make run           # build and open
make install       # build, quit the running copy, replace /Applications/Fastlight.app
make dmg           # -> build/Fastlight-<version>.dmg
make test
make clean
```

`UNIVERSAL=1 make dmg` builds arm64 + x86_64 (needs the `x86_64-apple-darwin`
Rust target, added automatically when rustup is around, and Xcode or Swift
6.2+). `CODESIGN_IDENTITY="Developer ID Application: …"` signs with a real
identity and the hardened runtime instead of ad-hoc. The release workflow
(`.github/workflows/release.yml`) does both on `v*` tags and notarizes when
the secrets listed at its top are set.

For quick iteration, `swift run Fastlight` works too; outside the bundle it
looks for fsearch in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`
(`make fsearch` builds one at `.build/fsearch/release/fsearch`).

## Keys

| Key | Does |
|---|---|
| ⌥Space | Show / hide |
| ↑ ↓ | Move |
| Tab, ⇧Tab (or ⌘↓, ⌘↑) | Next / previous section |
| ↵ | Open |
| ⌘↵ | Show in Finder |
| ⌘Y | Quick Look |
| ⌥⌘C | Copy path |
| ⎋ | Clear, then close |

Results come in sections: a **Top Hit**, then **Applications** (from
`/Applications`, `/System/Applications`, `~/Applications` and a few system
folders, ranked by how well the name matches, so `vsc` finds Visual Studio
Code, and by how often you open them), then **Files**. Plain queries leave
out app bundles, dot-folders and `~/Library`; any filter below turns that off.

The search field takes fsearch's query language: `'exact`, `^prefix`,
`suffix$`, `!exclude`, and the filters `ext:` `type:` `kind:` `in:` `size:`
`mtime:` `path:` `grep:` `regex:` `sym:`.

```
invoice ext:pdf mtime:<30d
readme in:~/src
grep:TODO ext:swift
```

## Layout

- `Sources/FastlightCore`: the fsearch socket client (JSON lines over
  `~/Library/Application Support/FSearch/fsearch.sock`), the app index and
  its ranking, and the file result filter. No AppKit.
- `Sources/Fastlight`: the menu-bar app, hotkey, panel and results UI.
- `third_party/fsearch`: fsearch, as a git submodule pinned to a known
  commit. Shipped at `Fastlight.app/Contents/Helpers/fsearch`.
- `scripts/`: `build-fsearch.sh`, `bundle.sh` (assembles and signs the `.app`),
  `dmg.sh`, and `test.sh`. The `Makefile` drives them.
- `scripts/snapshot.sh`: renders the panel with sample data to
  `build/snapshots/*.png`, light and dark; pass queries to add real results.

`make test` runs `scripts/test.sh`: `swift test`, working around a Command
Line Tools quirk.

## Credits

Search is done by [fsearch](https://github.com/noahdunnagan/fsearch) by Noah
Dunnagan, MIT licensed; its license is at
[`third_party/fsearch/LICENSE`](third_party/fsearch/LICENSE).
