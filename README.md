<div align="center">

<img src="assets/brand/png/app-icon-256.png" width="128" alt="Fastlight logo">

# Fastlight

*A Spotlight-style launcher for macOS that finds any app or file in about a millisecond.*

[![CI](https://github.com/elboletaire/fastlight/actions/workflows/ci.yml/badge.svg)](https://github.com/elboletaire/fastlight/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-15161B?style=flat-square&logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-FF5C9A?style=flat-square&logo=swift&logoColor=white)
[![Powered by fsearch](https://img.shields.io/badge/powered%20by-fsearch-7B5CFF?style=flat-square)](https://github.com/noahdunnagan/fsearch)
[![License: MIT](https://img.shields.io/badge/license-MIT-FFC81A?style=flat-square)](LICENSE)

[Features](#features) • [Install](#install) • [Usage](#usage) • [Build from source](#build-from-source) • [How it works](#how-it-works) • [Website](https://elboletaire.github.io/fastlight/)

<img src="site/og.png" alt="Fastlight: find anything on your Mac in a millisecond" width="800">

</div>

Press **⌥Space** anywhere, type a few letters, hit **↵**. Fastlight searches your applications and your whole disk as you type, with fuzzy matching that forgives typos, and stays out of the way in the menu bar. File search is done by [fsearch](https://github.com/noahdunnagan/fsearch), which is bundled inside the app: there is nothing else to install.

## Features

- **Apps and files, kept apart.** A Top Hit, then Applications with their real icons, then Files, each in its own section.
- **Fast, all the time.** Name search over millions of files in about a millisecond, so results update on every keystroke with no debounce.
- **Forgiving matching.** `vsc` finds Visual Studio Code, `sys set` finds System Settings, `mian.rs` still finds `main.rs`. Apps you open often move up.
- **Search inside files.** `grep:`, `regex:` and `sym:` search file contents through fsearch's index and show the matching line.
- **Power-user filters.** `ext:`, `in:`, `size:`, `mtime:`, `kind:` and more, straight from the search field.
- **Feels native.** A floating panel that looks and behaves like Spotlight, with Liquid Glass on macOS 26 and later, Quick Look, and Reveal in Finder.
- **Private.** Everything runs locally. No network access, no accounts, no telemetry.

## Install

1. Download `Fastlight-<version>.dmg` from the [latest release](https://github.com/elboletaire/fastlight/releases/latest), open it and drag **Fastlight** onto **Applications**.
2. Open Fastlight. It lives in the menu bar; press **⌥Space** to search.
3. Give Fastlight **Full Disk Access** in System Settings › Privacy & Security, so it can see Desktop, Documents and other protected folders. Fastlight shows a shortcut to that setting until you do.

> [!NOTE]
> Builds that aren't notarized are blocked the first time you open them. Go to System Settings › Privacy & Security and click **Open Anyway**.

> [!TIP]
> Want **⌘Space** instead of ⌥Space? Turn off Spotlight's shortcut in System Settings › Keyboard › Keyboard Shortcuts › Spotlight first, then change the hotkey in `Sources/Fastlight/AppDelegate.swift`.

The first time it runs, fsearch indexes the whole disk (around 20 seconds) and Fastlight shows its progress. After that the index stays current on its own and survives restarts. Apps are searched from the start, even while files are still being indexed.

## Usage

| Key | Does |
|---|---|
| ⌥Space | Show / hide |
| ↑ ↓ | Move through results |
| Tab, ⇧Tab (or ⌘↓, ⌘↑) | Next / previous section |
| ↵ | Open |
| ⌘↵ | Show in Finder |
| ⌘Y | Quick Look |
| ⌥⌘C | Copy path |
| ⎋ | Clear, then close |

The search field takes fsearch's query language. Words are fuzzy; `'exact`, `^prefix`, `suffix$` and `!exclude` narrow them down, and filters do the rest:

```text
invoice ext:pdf mtime:<30d       PDFs named like "invoice", changed this month
readme in:~/src                  only inside ~/src
type:image size:>5mb             big images
grep:TODO ext:swift              lines containing TODO in Swift files
sym:applyFilter                  where a symbol is defined
```

Plain queries leave out noise like app bundles, dot-folders, `node_modules` and `~/Library`. Any filter turns that off, so `in:~/Library` searches there as usual.

## Build from source

You need the Swift 6 toolchain (the Command Line Tools are enough, no Xcode) and Rust 1.85+ to compile fsearch:

```sh
brew install rustup && "$(brew --prefix rustup)/bin/rustup" default stable
git clone --recursive git@github.com:elboletaire/fastlight.git && cd fastlight
make            # build/Fastlight.app, with fsearch embedded
```

| Command | Does |
|---|---|
| `make run` | Build and open the app |
| `make install` | Build, quit the running copy and replace `/Applications/Fastlight.app` |
| `make dmg` | Build `build/Fastlight-<version>.dmg` |
| `make test` | Run the test suite |
| `make clean` | Remove build output |

`UNIVERSAL=1 make dmg` builds for both Apple Silicon and Intel, and `CODESIGN_IDENTITY="Developer ID Application: …"` signs with a real identity and the hardened runtime. The [release workflow](.github/workflows/release.yml) does both on `v*` tags, and notarizes when the secrets listed at its top are set.

> [!IMPORTANT]
> Local builds are signed ad hoc, and macOS ties Full Disk Access to the signature. Grant it again after each rebuild, or sign with a real identity.

`scripts/snapshot.sh` renders the panel with sample data to `build/snapshots/`, in light and dark, which is handy when working on the design.

## How it works

Fastlight is a menu-bar app in Swift. It registers a global hotkey and shows a floating panel. Apps come from its own index of `/Applications`, `/System/Applications`, `~/Applications` and a few system folders, ranked by name match and by how often you open them. Files come from fsearch: Fastlight starts the bundled daemon at `Fastlight.app/Contents/Helpers/fsearch` and talks to it as JSON lines over `~/Library/Application Support/FSearch/fsearch.sock`.

| Path | What's there |
|---|---|
| `Sources/FastlightCore` | fsearch client, app index and ranking, file result filter. No AppKit, covered by unit tests. |
| `Sources/Fastlight` | Menu-bar app, hotkey, panel and results UI. |
| `third_party/fsearch` | fsearch, as a git submodule pinned to a known commit. |
| `scripts/` | Build, bundle, DMG, test and snapshot scripts, driven by the `Makefile`. |
| `assets/brand` | Logo, icons and the [brand guide](assets/brand/BRAND.md). |

> [!NOTE]
> Fastlight starts the fsearch daemon as its own child process, so the Full Disk Access you give Fastlight covers it. The daemon keeps running after Fastlight quits and is reused next time. If it started before you granted access, run `pkill -f 'fsearch serve'` and reopen Fastlight so it rescans. If you already run a standalone fsearch daemon, Fastlight uses that one instead.

## Website

The project site lives in `site/`: plain HTML, CSS and a little vanilla JavaScript, with no build step. [`pages.yml`](.github/workflows/pages.yml) publishes it to <https://elboletaire.github.io/fastlight/> on every push to `main` that touches `site/`. To preview it locally:

```sh
python3 -m http.server -d site    # then open http://localhost:8000
```

The social card `site/og.png` is rendered from `site/og/og.html`; see `site/og/README.txt`.

## Credits

File search is [fsearch](https://github.com/noahdunnagan/fsearch) by Noah Dunnagan, MIT licensed ([license](third_party/fsearch/LICENSE)).

Fastlight is not affiliated with Apple. Spotlight and macOS are trademarks of Apple Inc.
