<div align="center">

<img src="assets/brand/png/app-icon-256.png" width="128" alt="Fastlight logo">

# Fastlight

*A Spotlight-style launcher for macOS that finds any app or file in microseconds.*

[![CI](https://github.com/elboletaire/fastlight/actions/workflows/ci.yml/badge.svg)](https://github.com/elboletaire/fastlight/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-15161B?style=flat-square&logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-FF5C9A?style=flat-square&logo=swift&logoColor=white)
[![Powered by fsearch](https://img.shields.io/badge/powered%20by-fsearch-7B5CFF?style=flat-square)](https://github.com/noahdunnagan/fsearch)
[![License: MIT](https://img.shields.io/badge/license-MIT-FFC81A?style=flat-square)](LICENSE)

[Features](#features) • [Install](#install) • [Usage](#usage) • [Replace Spotlight](#replace-spotlight) • [Extensions](#extensions) • [Development](docs/development.md) • [Website](https://elboletaire.github.io/fastlight/)

<img src="site/og.png" alt="Fastlight: find anything on your Mac in microseconds" width="800">

</div>

Press **⌥Space** anywhere, type a few letters, hit **↵**. Fastlight searches your applications and your whole disk as you type, with fuzzy matching that forgives typos, and stays out of the way in the menu bar. File search is done by [fsearch](https://github.com/noahdunnagan/fsearch), which is bundled inside the app: there is nothing else to install.

## Features

- **Apps and files, kept apart.** A Top Hit, then Applications with their real icons, then Files, each in its own section.
- **Fast, all the time.** Name search over millions of files in microseconds, so results update on every keystroke with no debounce.
- **Forgiving matching.** `vsc` finds Visual Studio Code, `sys set` finds System Settings, `mian.rs` still finds `main.rs`. Apps you open often move up.
- **Search inside files.** `grep:`, `regex:` and `sym:` search file contents through fsearch's index and show the matching line. ↵ opens it at that line in VS Code, Cursor, VSCodium, Zed, BBEdit or TextMate, when one of them is the file's default app.
- **Power-user filters.** `ext:`, `in:`, `size:`, `mtime:`, `kind:` and more, straight from the search field.
- **Built in.** An emoji picker, a calculator, unit, time zone and date conversions, a dictionary, web search, System Settings panes, Shortcuts, system actions, Contacts, Calendar and Reminders. See [what each one does](#built-in-extensions).
- **Extensions in any language.** A folder with a manifest and a script or binary that speaks JSON lines. See [Extensions](#extensions).
- **Feels native.** A floating panel that looks and behaves like Spotlight, with Liquid Glass on macOS 27 and later, Quick Look, and Reveal in Finder.
- **Private.** Everything runs locally. No network access, no accounts, no telemetry. Contacts, Calendar and Reminders are read from this Mac's own stores, only after you allow it, and never written to. (Extensions you install can do whatever their code does.)

## Install

1. Install it with [Homebrew](https://brew.sh):

   ```sh
   brew install --cask elboletaire/tap/fastlight
   ```

   Or download `Fastlight-<version>.dmg` from the [latest release](https://github.com/elboletaire/fastlight/releases/latest), open it and drag **Fastlight** onto **Applications**.
2. Give `/Applications/Fastlight.app` **Full Disk Access** in System Settings › Privacy & Security, so it can see Desktop, Documents and other protected folders. Doing it before the first launch saves a restart of the search daemon, but granting it later works too: Fastlight notices and restarts the daemon by itself. Until then the panel shows a shortcut to that setting.
3. Open Fastlight. It lives in the menu bar; press **⌥Space** to search.

> [!NOTE]
> Builds that aren't notarized are blocked the first time you open them. Go to System Settings › Privacy & Security and click **Open Anyway**.
>
> Releases are signed ad hoc until there is a Developer ID, so each update has a new signature and macOS drops the Full Disk Access grant. After updating, remove Fastlight from the Full Disk Access list and add it again.

> [!TIP]
> With Homebrew, `brew upgrade --cask fastlight` updates it (quitting and reopening it), and `brew uninstall --cask fastlight` removes it and stops its search daemon. `brew uninstall --zap --cask fastlight` also deletes its settings, logs and extension data (extensions you installed stay), and fsearch's index unless a standalone fsearch is installed.

> [!TIP]
> Want another shortcut? Pick one in **Settings…** from the menu bar icon. For **⌘Space**, see [Replace Spotlight](#replace-spotlight).

The first time it runs, fsearch indexes the whole disk (under a minute, even with millions of files) and Fastlight shows its progress. After that the index stays current on its own and survives restarts. Apps are searched from the start, even while files are still being indexed.

### Troubleshooting

If files from Desktop or Documents still don't show up with Full Disk Access granted, reset the grant, stop the daemon, and open Fastlight again:

```sh
tccutil reset SystemPolicyAllFiles com.elboletaire.fastlight
pkill -f 'fsearch serve'
```

Then add Fastlight back to the Full Disk Access list. Its log is in `~/Library/Application Support/FSearch/daemon.log`.

## Usage

| Key | Does |
|---|---|
| ⌥Space (or your own, see Settings) | Show / hide |
| ↑ ↓ | Move through results |
| Tab, ⇧Tab (or ⌘↓, ⌘↑) | Next / previous section |
| ↵ | Open (an extension result: its main action, like Paste) |
| ⌘↵ | Show in Finder (an extension result: its second action, like Copy) |
| ⌘Y | Quick Look |
| ⌥⌘C | Copy path |
| ⌫ on an empty field | Leave an extension's keyword mode |
| ⎋ | Clear, then close |

The search field takes fsearch's query language. Words are fuzzy, and words of five letters or more survive one typo; operators narrow them down, and filters do the rest:

```text
invoice ext:pdf mtime:<30d       PDFs named like "invoice", changed this month
readme in:~/src                  only inside ~/src
type:image size:>5mb             big images
grep:TODO ext:swift              lines containing TODO in Swift files
sym:applyFilter                  where a symbol is defined
```

<details>
<summary><b>Operators and filters</b></summary>

| Operator | Does |
|---|---|
| `'exact` | No fuzziness |
| `^prefix` | Name starts with |
| `suffix$` | Name ends with |
| `!word` | Leave out paths with it in the name or a folder: `!node_modules`. Works with `'`, `^` and `$` too: `!.bak$` |
| `"two words"` | Quotes keep spaces in one word or value: `in:"~/My Notes"` |
| `folder/name` | Words can match folders on the path too, as long as one is in the name; `/` splits words. `src readme` and `src/readme` both find `~/src/app/README.md` |

| Filter | Does |
|---|---|
| `ext:` | Extension; commas for several: `ext:jpg,png` |
| `type:` | `image`, `video`, `audio`, `doc`, `code`, `archive`, `font` or `app`; commas for several |
| `kind:` | `file` (`f`), `dir` (`folder`, `d`) or `link` (`symlink`, `l`) |
| `in:` | Only under a folder, absolute or `~`: `in:~/src` |
| `size:` | `size:>5mb`, `size:1m..10m` |
| `mtime:` | Modified within (`mtime:<7d`) or longer ago than (`mtime:>1y`). Also `modified:` |
| `re:` | Regex over the name, ignoring case: `re:^IMG_\d+` |
| `path:` | Regex over the full path, ignoring case: `path:/tests?/` |
| `grep:` | Text inside files; ignores case unless it has capitals. Also `content:` |
| `regex:` | Regex inside files; ignores case unless it has capitals: `regex:fn\s+main` |
| `sym:` | Where a symbol is defined, case and all. Also `symbol:` |

`size:` and `mtime:` take `>`, `>=`, `<`, `<=` or a range `a..b`, and `size:` an exact value too. Sizes are in `b`, `k`/`kb`, `m`/`mb`, `g`/`gb` or `t`/`tb` (1 kb is 1000 bytes), and a bare number means bytes; times are in `s`, `m`/`min`, `h`, `d`, `w`, `mo` or `y`, and a bare number means days. Matching ignores case, except `sym:` and `grep:` or `regex:` patterns with capitals. The same reference is in **About Fastlight**.

</details>

Plain queries leave out noise like app bundles, dot-folders, `node_modules` and `~/Library`. Any filter turns that off, so `in:~/Library` searches there as usual.

## Replace Spotlight

Fastlight starts on ⌥Space because ⌘Space belongs to Spotlight. To move it, open **Settings…** from the menu bar icon: **Use ⌘Space Instead of Spotlight** walks you through it. There are two ways, because macOS has no public API for another app to take over Spotlight's shortcut.

- **Recommended:** click **Open Keyboard Settings…**, then **Keyboard Shortcuts… › Spotlight** and turn off **Show Spotlight search**. Fastlight notices while its Settings window is open and switches to ⌘Space by itself.
- **Do It for Me (experimental):** after asking, Fastlight turns off that one shortcut in `com.apple.symbolichotkeys` and applies it right away. It keeps a copy of the previous setting, so **Restore Spotlight's Shortcut** puts it back exactly and returns Fastlight to ⌥Space. If a future macOS doesn't pick the change up, Settings says so and it takes effect after you log out and back in.

Either way only the shortcut changes. Spotlight stays on, and so does its index, which Finder, Mail and other apps search with; ⌥⌘Space (Finder search) is left alone. If Fastlight is set to ⌘Space while Spotlight still has it, ⌘Space opens Spotlight, and Fastlight's Settings says so. To undo a manual change, pick another shortcut in Fastlight and turn **Show Spotlight search** back on.

<img src="docs/images/settings/settings-light.png" alt="Fastlight Settings: the shortcut recorder and the ⌘Space flow" width="520">

## Extensions

Extensions add results, either when you type their keyword (`:` for emoji, `=` for the calculator) or, if they opt in, in their own section of the normal results. An extension is a folder in `~/Library/Application Support/Fastlight/Extensions/` with an `extension.json` and any executable that reads requests on stdin and answers on stdout, one JSON object per line: a 30-line shell script is enough.

```sh
cp -R examples/extensions/bc ~/Library/Application\ Support/Fastlight/Extensions/
```

Then type `bc 2*21`. Fastlight asks before running a new or changed extension for the first time, since it runs with Fastlight's permissions. The menu bar icon › Extensions turns them on and off and opens their folder and logs.

The built-in extensions are bundled and built the same way. Write your own with [the extension guide](docs/extensions/README.md); the design is in [docs/extensions/design.md](docs/extensions/design.md).

### Built-in extensions

| Extension | Try |
|---|---|
| Emoji | `:joy`, `:tada:`: a name, keyword or Slack shortcode; ↵ pastes it where you were typing |
| Calculator | `1920*1080`, `2^10`, `15% of 80`: the answer is the Top Hit; ↵ copies it |
| Conversions | `10 km in mi`, `time in tokyo`, `3pm london in nyc`, `days until dec 25`, offline; ↵ copies the answer |
| Dictionary | `define serendipity`, from the dictionaries built into macOS, offline; ↵ opens Dictionary.app |
| Web | `github.com` or `localhost:3000` opens it; `web ` and anything searches Google (or DuckDuckGo, Wikipedia…; [configurable](docs/extensions/README.md)) |
| System Settings | `bluetooth`, `displays`, `full disk access`; ↵ opens that pane |
| Shortcuts | Run your shortcuts by name; `sc translate hello` passes "hello" as input |
| System | Lock Screen, Sleep, Toggle Dark Mode, Eject All Disks; Empty Trash, Log Out, Restart and Shut Down ask for a second ↵ |
| Contacts | A name, company, email or number; `contact ` lists them, one ↵ from an email, a call, a message or FaceTime |
| Calendar and Reminders | `cal ` is today's agenda and the next two weeks, `remind ` what's due, overdue first; events and reminders also show up in normal search. Read-only |

Contacts, Calendar and Reminders only work once you allow them.

## Languages

Fastlight speaks English, Catalan and Spanish, following the order of languages in System Settings › General › Language & Region. What you type stays English: keywords, units, date phrases and search filters work the same in every language. To add one, see [Translations](docs/development.md#translations).

## Build from source

You need the Swift 6 toolchain (the Command Line Tools are enough, no Xcode) and Rust 1.85+ to compile fsearch:

```sh
brew install rustup && "$(brew --prefix rustup)/bin/rustup" default stable
git clone --recursive https://github.com/elboletaire/fastlight.git && cd fastlight
make            # build/Fastlight.app, with fsearch embedded
make install    # replace /Applications/Fastlight.app
```

> [!IMPORTANT]
> Local builds are signed ad hoc, and macOS ties Full Disk Access to the signature. Grant it again after each rebuild, or sign with a real identity.

The [development guide](docs/development.md) covers the other `make` targets, releases, translations and how Fastlight runs fsearch.

## How it works

Fastlight is a menu-bar app in Swift. It registers a global hotkey and shows a floating panel. Apps come from its own index of `/Applications`, `/System/Applications`, `~/Applications` and a few system folders, ranked by name match and by how often you open them. Files come from [fsearch](https://github.com/noahdunnagan/fsearch): Fastlight starts the bundled daemon as its own child process, so the Full Disk Access you give Fastlight covers it, and talks to it as JSON lines over a Unix socket. The daemon keeps running after Fastlight quits, so the next launch answers at once and changes keep being tracked.

## Credits

File search is [fsearch](https://github.com/noahdunnagan/fsearch) by Noah Dunnagan, MIT licensed ([license](third_party/fsearch/LICENSE)).

Emoji names and keywords come from [Unicode](https://unicode.org/emoji/) and [CLDR](https://cldr.unicode.org/) (Unicode License v3, [license](Extensions/emoji/LICENSE-UNICODE.txt)), shortcodes from GitHub's [gemoji](https://github.com/github/gemoji) (MIT, [license](Extensions/emoji/LICENSE-GEMOJI.txt)).

Fastlight is not affiliated with Apple. Spotlight and macOS are trademarks of Apple Inc.
