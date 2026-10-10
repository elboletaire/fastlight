# Fastlight extensions: design

Status: implemented in protocol version **1**. Author-facing docs live in
[README.md](README.md); this document explains how and why it works.

## Goals

- Anyone can add results to Fastlight in any language: a folder with a
  manifest and an executable that speaks **JSON lines over stdin/stdout**, the
  same style Fastlight already uses with fsearch. No plugin runtime, nothing
  loaded into Fastlight's process.
- Two ways in: a **keyword mode**, where the extension owns the result list,
  and an opt-in **global mode**, where it adds a few results under its own
  section, inside a strict time budget so typing never lags.
- Installing is dropping a folder into
  `~/Library/Application Support/Fastlight/Extensions/`. The manifest already
  carries what a later `fastlight://install?…` flow needs (id, version,
  source URL), so that flow won't change the format.
- Nothing from that folder runs until the user said yes to that exact code.
  A misbehaving extension can never take Fastlight down or slow it down.

## Architecture

```text
 Sources/FastlightCore (no AppKit, unit-tested)
 ┌───────────────────────────────────────────────────────────────────────┐
 │ SearchFanout ── runs ResultProviders concurrently, latest query wins, │
 │   │             per-provider time budget, first paint after 50 ms     │
 │   ├─ AppProvider        AppIndex                                      │
 │   ├─ FileProvider       FSearchClient ── fsearch daemon (socket)      │
 │   └─ ExtensionProvider  ExtensionHost ── ExtensionProcess ── child    │
 │                            │   one per extension, JSON lines on pipes │
 │ ExtensionLibrary ── scans folders, ExtensionManifest validation,      │
 │                     fingerprints, KeywordRouter                       │
 │ ConsentStore ── approved fingerprints, disabled ids (UserDefaults)    │
 └───────────────────────────────────────────────────────────────────────┘
 Sources/Fastlight (AppKit/SwiftUI)
   SearchModel (scope pill, sections) · PanelController (keys, actions,
   paste) · ExtensionsMenu · consent alert · Toast
 Sources/FastlightEmoji + Sources/fastlight-emoji
   the bundled emoji picker, a normal protocol-1 extension
 Sources/FastlightCalc + Sources/fastlight-calc
   the bundled calculator, likewise
 Sources/FastlightSystem + Sources/fastlight-system
   System Settings, Shortcuts and System: three built-ins, one helper
```

Apps, files and extensions all implement `ResultProvider`:

```swift
public protocol ResultProvider: Sendable {
    var id: String { get }
    var budget: Duration? { get }  // nil: no deadline
    func results(for query: ProviderQuery) async throws -> [ResultEntry]
}
```

`SearchFanout` starts every provider for a keystroke at once. It paints
when all have answered or 50 ms have passed, whichever is first, then
repaints as late providers arrive. A provider with a `budget` (every
extension in global mode: **80 ms**) is raced against it; when it loses, its
outcome is `timedOut` and its answer is dropped for that keystroke. A new
keystroke cancels the previous generation, so stale answers never reach the
UI.

Sections in global mode: Top Hit, Applications, one section per global
extension (registry order, built-ins first), Files. Extension items don't
become the Top Hit, so an extension can't hijack ↵ for app launching. The
one exception is an item a **built-in** marks `"topHit": true`: the
calculator's answer, which is what someone typing `1920*1080` is after.

## Extension folder and manifest

```text
~/Library/Application Support/Fastlight/Extensions/
  bc/                         # folder name is free; the id is in the manifest
    extension.json
    bc.sh
```

`extension.json`:

```json
{
  "id": "com.example.bc",
  "name": "bc",
  "version": "1.0.0",
  "description": "Evaluates arithmetic with bc.",
  "author": "Jane Doe",
  "homepage": "https://example.com/bc",
  "source": "https://github.com/example/fastlight-bc",
  "icon": "terminal",
  "keywords": ["bc"],
  "command": ["/bin/sh", "bc.sh"],
  "global": { "maxResults": 1, "minQueryLength": 3 },
  "minFastlightVersion": "0.2.0"
}
```

| Key | Rules |
|---|---|
| `id` | Required. Lowercase reverse-DNS, 2+ dot-separated labels of `a-z0-9-`, at most 100 characters. Unique across installed extensions. |
| `name` | Required, 1–40 characters. Shown in the scope pill, section title and menu. |
| `version` | Required. Semantic version `MAJOR.MINOR.PATCH`, optional `-prerelease`. |
| `description`, `author` | Optional strings (≤ 200 / ≤ 100 characters). |
| `homepage`, `source` | Optional `http(s)` URLs. `source` is where the code comes from (repository or download), which the future URL installer will use for updates. |
| `icon` | Optional icon (see *Icons*). A relative path is resolved inside the folder. |
| `keywords` | Required, 1–5 entries, 1–20 characters, no whitespace. See *Keywords*. |
| `command` | Required, non-empty array: executable then arguments. A relative executable must exist inside the folder and be executable; an absolute one (an interpreter such as `/bin/sh`) must exist. The working directory is the extension folder. |
| `global` | Optional. Opts in to global search. `maxResults` 1–5 (default 3), `minQueryLength` 1–10 (default 2). |
| `minFastlightVersion` | Optional semantic version; newer than the running app means the extension is not loaded. |

Unknown keys are rejected, so typos (`keyword`) fail loudly; newer manifest
fields come with a `minFastlightVersion` bump. Every problem is reported as
`<folder>/extension.json: <key path>: <what is wrong>` in the Extensions menu
and the log, and the extension is skipped. Two extensions with the same id:
the first one found wins (built-ins first, then folders in name order).

### Keywords

A keyword that ends in a letter or digit needs a space after it (`emoji `,
`gh `), so typing `emojis` is still a normal search. A keyword that ends in a
symbol triggers straight away (`:` → `:smile`, `=` → `=2+2`). Matching is
case-insensitive and the longest trigger wins. Keywords that would shadow
search syntax are rejected: anything starting with `'`, `^`, `!`, `.`, `/` or
`~`, and fsearch filter names (`ext:`, `in:`, …). A keyword already taken by
an earlier extension is ignored for the later one (reported, not fatal).

In keyword mode the keyword turns into a pill in the search bar and the rest
of the text goes to the extension, including the empty string (show
something useful: recents, help). Backspace on an empty field removes the
pill and puts the keyword text back minus its last character, so backspacing
feels continuous.

## Protocol (version 1)

UTF-8 JSON, one object per line, both directions. Fastlight writes to the
extension's stdin and reads its stdout. stderr goes to
`~/Library/Logs/Fastlight/Extensions/<id>.log`.

### Startup and handshake

Fastlight starts the process on first use with the working directory set to
the extension folder and this environment (plus `HOME`, `USER`, `LANG`,
`TMPDIR`, and `PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin`):

| Variable | Value |
|---|---|
| `FASTLIGHT_PROTOCOL` | Highest protocol version Fastlight speaks (`1`). |
| `FASTLIGHT_VERSION` | App version, e.g. `0.2.0`. |
| `FASTLIGHT_EXTENSION_ID` | The manifest id. |
| `FASTLIGHT_DATA_DIR` | A writable folder for settings and caches: `~/Library/Application Support/Fastlight/ExtensionData/<id>/`. Writing inside the extension folder changes its fingerprint and asks the user again. |

The extension's **first line** must be the handshake:

```json
{"type":"ready","protocol":1}
```

`protocol` is the version the extension speaks. Fastlight stops it if that
is not one it supports, and reports why. Requests made before `ready` wait
for it (up to 5 s).

### Requests and replies

Every request has an integer `id` and a `type`; the reply carries the same
`id`. Replies may come in any order. Unknown request types must be answered
with an `error` (or ignored, which costs a timeout).

**search**: `mode` is `keyword` or `global`; `limit` is how many items will
be shown at most.

```json
{"id":3,"type":"search","query":"joy","mode":"keyword","limit":50}
```
```json
{"id":3,"items":[
  {"id":"1f602","title":"Face with Tears of Joy","subtitle":"face, joy, laugh, tear",
   "icon":{"emoji":"😂"},"accessory":"Smileys",
   "actions":[{"type":"paste","text":"😂","title":"Paste Emoji"},
              {"type":"copy","text":"😂","title":"Copy Emoji"}]}
]}
```

**run**: asks the extension to perform a `run` action of one of its items.
`data` is echoed back from the action, `query` is what was typed.

```json
{"id":4,"type":"run","name":"setTone","item":"tone-3","data":3,"query":"tone"}
```
```json
{"id":4}
```

**errors**: any reply can be `{"id":4,"error":"something readable"}`; it is
shown to the user in place of results (keyword mode) or as a toast (run).

**Notifications** carry no `id` and get no reply. Fastlight sends one when
the user picks an item with a built-in action, so extensions can learn
recents and frequency:

```json
{"type":"picked","item":"1f602","action":"paste"}
```

Extensions must ignore notification types they don't know.

### Items

| Key | Rules |
|---|---|
| `id` | Required string, unique within the reply. |
| `title` | Required, non-empty. |
| `subtitle`, `accessory` | Optional strings; `accessory` is right-aligned. |
| `icon` | Optional icon. |
| `actions` | Optional array. The first is the default (↵), the second runs on ⌘↵. No actions: the item is informational. |

At most 200 items per reply; longer strings are truncated for display. A reply
that breaks these rules fails as a whole with a message naming the field.

### Actions

| `type` | Fields | Does |
|---|---|---|
| `open` | `target` | Opens a URL (`https:`, `mailto:`, any registered scheme) or a path (`~` expanded) with the default app. |
| `copy` | `text` | Copies to the clipboard and shows a toast. |
| `paste` | `text` | Copies, hides the panel, re-activates the app that was frontmost and presses ⌘V. Needs Accessibility; without it Fastlight copies, tells the user, and offers to enable it once. |
| `reveal` | `path` | Shows the file in Finder. |
| `run` | `name`, optional `data` (any JSON), optional `then`: `close` (default), `refresh` (rerun the query, keep the panel), `stay` | Sends a `run` request. |

Every action may have a `title` (shown in the action bar at the bottom of the
results). Defaults: Open, Copy, Paste, Show in Finder, and the `name`.

### Icons

Either an object with exactly one key, or a string shorthand:

| Object | Shorthand | Shows |
|---|---|---|
| `{"emoji":"😂"}` | a string with no ASCII letters | The glyph. |
| `{"symbol":"globe"}` | any other string | An SF Symbol. |
| `{"path":"~/x.png"}` | a string starting with `/`, `~/` or `./` | The image at that path, or the file's Finder icon. |
| `{"app":"com.apple.Safari"}` | — | That app's icon. |

## Lifecycle, timeouts and failure handling

| Situation | What Fastlight does |
|---|---|
| Panel shown | Approved global extensions are started, so the first keystroke doesn't pay for a cold start. |
| First use (keyword or global) | Spawn, wait for `ready` (5 s). |
| Several keystrokes while a search is in flight | At most one search is in flight per extension; only the newest waiting query is kept, the rest are dropped. Replies to ids nobody waits for are discarded. |
| Global search slower than 80 ms | Section left out for that keystroke. |
| Keyword search slower than 3 s | "X didn't answer in time" notice. |
| `run` slower than 10 s | Error toast. |
| 3 timeouts in a row | Process killed; restarted on next use. |
| Process exits or crashes | Pending requests fail; restarted on next use. 3 crashes within 60 s mark it **failed** until Reload Extensions or the files change. |
| Non-JSON or unexpected lines on stdout | Logged and ignored; after 20 of them, or one line over 1 MiB, the process is killed (counts as a crash). |
| Idle for 5 minutes | stdin closed, then SIGTERM, then SIGKILL after 1 s. |
| Fastlight quits | Same as idle shutdown for every extension. Extensions should also exit when stdin closes (EOF), which covers a crash of Fastlight itself. |

The process manager is callback based and lock-protected; nothing on the main
thread blocks on an extension.

## Discovery

Built-ins live in `Fastlight.app/Contents/Resources/Extensions/<name>/`, with
their executables in `Contents/Helpers/` (signed with the app, like fsearch).
A built-in's relative `command` is looked up there (and next to the
Fastlight binary, for `swift run`). User extensions live in
`~/Library/Application Support/Fastlight/Extensions/<folder>/`, which
Fastlight creates on launch.

The library rescans when the panel is shown and from **Reload Extensions**.
A rescan only lists files and compares a stamp of (path, size, mtime,
ctime); it re-reads manifests and re-hashes only folders whose stamp
changed. The ctime is there because it can't be set back by hand. A changed
extension's running process is stopped.

## Security and consent

Extensions run with Fastlight's privileges, which may include Full Disk
Access. So:

- Every user extension has a **fingerprint**: SHA-256 over the relative path
  and contents of every file in its folder (length-prefixed; everything but
  Finder's `.DS_Store`, hidden files and `.git/` included, since code can run
  from anywhere in there). It covers the manifest (and with it id and
  version), the executable and any script it loads from its folder. A
  symlinked folder is hashed through the link. Folders over 100 MB or 5,000
  files are refused.
- `ConsentStore` remembers approved `id → fingerprint` pairs. Nothing is
  spawned unless the current fingerprint is approved: `ExtensionHost` checks
  consent before every request, independent of the UI, and re-hashes the
  folder right before every process start, so files changed since the last
  rescan don't run either.
- The first time a new or changed extension would run (its keyword is typed,
  or the user picks it in the menu), Fastlight hides the panel and asks with
  a standard alert showing the name, id, version, folder and command, and
  whether it is new or changed since an approved version. Global search never
  prompts: unapproved extensions are just skipped, and the idle panel shows
  "N extensions need your approval" with a Review button.
- Any extension can be disabled from the menu (stored by id; a disabled
  extension is never started and its keywords are free).
- Built-ins ship inside the signed app bundle and are trusted without asking;
  they can still be disabled.

What consent does not do: sandbox the extension. It is the same trust model
as installing a command-line tool. The fingerprint makes sure the user
approves the code that actually runs, and is re-asked when it changes.

## The emoji picker

`Sources/fastlight-emoji` is a protocol-1 extension like any other, built
from the same package and bundled as a built-in (`id
com.elboletaire.fastlight.emoji`, keywords `:` and `emoji`, global with 3
results for queries of 3+ characters). The search logic is the
`FastlightEmoji` library, so it is unit tested.

- Data: `Extensions/emoji/emoji.tsv`, generated by
  `scripts/generate-emoji.swift` from Unicode's `emoji-test.txt` (names,
  groups, skin-tone variants) and CLDR's English annotations (keywords), both
  under the Unicode License v3 (`LICENSE-UNICODE.txt`), plus Slack/GitHub
  shortcodes (`:tada:`) from GitHub's gemoji, MIT (`LICENSE-GEMOJI.txt`).
  Versions are pinned in the script. No network at runtime. Emoji newer than
  the running macOS can draw are left out.
- Ranking: every query word must prefix-match a word of the name, a
  shortcode or a keyword. An exact name or shortcode wins; whole words beat
  prefixes; name and shortcode matches beat keyword matches; then shorter
  names, a small bonus for the most used emoji overall (Unicode's frequency
  list), how often and how recently the user picked it (from `picked`
  notifications, stored in `FASTLIGHT_DATA_DIR`), and Unicode order.
- Empty query: recently and frequently used emoji first, then a few popular
  defaults.
- Skin tone: typing `tone` lists the six tones; picking one is a `run` action
  that stores it and refreshes. Emoji that support tones are returned in
  that tone.
- Actions: Paste Emoji (↵), Copy Emoji (⌘↵).

## The calculator

`Sources/fastlight-calc` is the second built-in (`id
com.elboletaire.fastlight.calculator`, keyword `=`, global with one result).
It needs no `bc` or shell: `FastlightCalc` has its own lexer, a Pratt
parser and an evaluator, so answers take microseconds.

- Precedence, low to high: `+ −`; `× ÷` and juxtaposition (`2π`,
  `3(4+5)`, but not `1 2`); unary minus; `^`/`**`, right-associative (so
  `−2^2` is −4 and `2^3^2` is 512); postfix `%` and `!`.
- `%` is a hundredth on its own, a share of the left side after `+`/`−`
  (`80 + 10%` = 88), and `15% of 80` = 12. Functions take one argument,
  with or without parentheses (`sqrt 2`). Trig is in radians; `deg`/`rad`
  convert.
- Numbers: `.` is always a decimal point; `,` is one where the locale says
  so, and elsewhere only valid as thousands grouping (`1,000,000`).
  `x` multiplies only between numbers (`3x4`).
- No result, never a crash, for syntax errors, unknown names, division by
  zero (no "∞": it is almost always a typo), out-of-domain input
  (`sqrt(-1)`), and anything that overflows.
- Normal search only shows an answer when the query computes something: a
  bare number (`2026`), a constant alone (`pi`), dates (`2026-10-10`,
  `10/10/2026`) and anything that doesn't parse are left alone. Then it is
  the Top Hit. Keyword mode always answers or says why not.
- Display: rounded to 12 significant digits (0.1 + 0.2 = 0.3), at most 10
  decimals, the locale's grouping (`2,073,600`), and `1.5 × 10²⁰` beyond
  10¹⁵ or below 10⁻⁹. The subtitle is the expression as understood
  (`1920 × 1080 =`). ↵ copies the answer without grouping, so it pastes
  into code and spreadsheets; ⌘↵ pastes it, as in Raycast.

## System Settings, Shortcuts and System

Three more built-ins (`com.elboletaire.fastlight.settings`, `.shortcuts`
and `.system`), all served by `Sources/fastlight-system`: the manifests
in `Extensions/settings`, `shortcuts` and `system` run the same helper
with `settings`, `shortcuts` or `actions` as its argument. The logic is
the `FastlightSystem` library; anything that would touch the system goes
through a `CommandRunner` or `SystemExecutor` protocol, so tests check
the exact commands with fakes and never run them.

**System Settings** (keywords `settings`, `pref`; global, 3 results for
3+ characters).

- Panes are discovered, not listed: every bundle in
  `/System/Library/ExtensionKit/Extensions` whose extension point is
  `com.apple.Settings.extension.ui` and that sets
  `allowsXAppleSystemPreferencesURLScheme`. Its bundle id is what
  `x-apple.systempreferences:<id>` opens, so the URLs are the ones the
  running macOS accepts (`com.apple.BluetoothSettings`,
  `com.apple.wifi-settings-extension`…), from 14 to 26.
- The name is the bundle's `CFBundleDisplayName` in the user's language
  (`InfoPlist.loctable`, or `InfoPlist.strings` in `.lproj` folders), with
  the English one as an alias, so "keyboard" also finds Teclat. Bundles
  without one (Battery, whose name is in its `Localizable` strings, and
  "Energy" on Macs without a battery) get it from `SettingsCatalog`, which
  also adds aliases (`wifi`, `dock`, `dark mode`, `fda`), and SF Symbols for
  the few bundles Finder can't draw an icon for. Code names
  (`PowerPreferences`) never show.
- Pages: each pane's `.searchTerms` file names its sections, and those keys
  are the URL anchors (`Privacy_AllFiles`). The catalog lists the pages
  worth a result (Full Disk Access, Accessibility, Screen & System Audio
  Recording, Input Monitoring, Automation, Camera…, FileVault, Lockdown
  Mode), each offered only when the installed pane lists its anchor, and
  named in the user's language when the pane's strings have it.
- Normal search matches names and aliases word by word (`full disk`,
  `blue`, `desktop and dock`); keyword mode also matches the search terms
  (titles and index words of every setting in the pane). Third-party
  `.prefPane` bundles in `/Library/PreferencePanes` and
  `~/Library/PreferencePanes` are included and opened by path.
- Scanning reads a few hundred small plists (about half a second, cold),
  so the index is cached in `FASTLIGHT_DATA_DIR/settings.json`, keyed by
  macOS version, languages and battery, and rebuilt in the background
  after every handshake. Until there's an index, normal search has
  nothing and keyword mode waits for it (up to 2 s).

**Shortcuts** (keywords `sc`, `shortcut`, `shortcuts`; global, 3 results
for 3+ characters).

- `/usr/bin/shortcuts list --show-identifiers`, plus one listing per
  folder for the subtitle, in the background after the handshake and on a
  search when the list is over 30 s old; cached in
  `FASTLIGHT_DATA_DIR/shortcuts.json` with when each was last run, which
  orders the empty query.
- Normal search shows a shortcut only when every word typed starts a word
  of its name (`go sleep`, `resize web`), not for parts of words.
- ↵ is a `run` action: `shortcuts run <id> [--input-path <file>]`, which
  is given a second to fail (an unknown shortcut) and then left to finish
  on its own, since shortcuts can run for minutes. In keyword mode, text
  after a whole name is input: written to a temporary `.txt` file,
  removed once the shortcut ends. ⌘↵ opens
  `shortcuts://open-shortcut?name=…`.

**System** (keyword `sys`; global, 3 results for 3+ characters).

| Action | How | Asks first | Permission |
|---|---|---|---|
| Lock Screen | `SACLockScreenImmediate` (login framework, as the Apple menu) | | none |
| Sleep, Sleep Displays | `pmset sleepnow`, `pmset displaysleepnow` | | none |
| Start Screen Saver | `open -b com.apple.ScreenSaver.Engine` | | none |
| Toggle Dark Mode | `osascript`: System Events' appearance preferences | | Automation (System Events) |
| Eject All Disks | `diskutil eject` per external, removable, image or network volume | | none |
| Empty Trash | `osascript`: Finder's `empty trash` | yes | Automation (Finder) |
| Log Out, Restart, Shut Down | `osascript`: loginwindow's `aevtrlgo`, `aevtrrst`, `aevtrsdn` | yes | Automation (loginwindow) |

The loginwindow events skip its own confirmation dialog (Fastlight has
asked already), but apps still get to save or cancel, as with the Apple
menu. Nothing needs Accessibility.

- Normal search is strict: the query must be plain words (no `.`, `/`,
  `~`) that are a name or alias (`reboot`, `power off`) or, from 4
  letters on, the start of one. `sleep`, `lock`, `rest` offer actions;
  `sleep.txt`, `sleeping beauty`, `log` don't.
- Confirmation is a small state machine in the extension. The first ↵ on
  a disruptive action is `run "arm"` with `then: "refresh"`: it records the
  action and the time, and the list is searched again. The armed action
  now reads "Confirm Restart?", comes first in keyword mode and is the
  Top Hit in normal search (a built-in may), so the next ↵ lands on it:
  `run "confirm"`, which runs the command only if that same action was
  armed in the last 5 seconds, and uses the arming up either way. ⌘↵ is
  `disarm`. `perform` (the one-step action) refuses disruptive actions,
  so no reply shape can skip the second step.

## Testing

All in `Tests/` with Swift Testing, deterministic and offline:

- Manifest parsing and every validation rule, including messages.
- Protocol encoding and decoding: items, actions, icon shorthands, errors.
- `ExtensionProcess` against small `/bin/sh` fake extensions written to a
  temp folder: handshake, request/response, out-of-order replies, timeouts,
  crash and restart, crash-loop fault, garbage output, oversized lines,
  protocol mismatch, idle shutdown.
- `ExtensionHost`: consent gate, latest-wins coalescing, stale replies.
- `ExtensionLibrary`: discovery, duplicate ids and keywords, fingerprints and
  change detection. `ConsentStore`, `KeywordRouter`.
- `SearchFanout` with fake providers: first paint, time budget, stale
  generations.
- Emoji data parsing, search ranking, skin tones, recents.
- Calculator: precedence and associativity, operator spellings, numbers and
  locales, percentages, functions, every error, formatting, the
  "looks like math" rule, and its protocol replies.
- System Settings: discovery against fixture bundles (names per language,
  old `.strings`, code names, hidden and non-URL bundles, Battery or
  Energy, icons, pages only with their anchor), URLs, ranking and its
  negatives, the cache, plus a read-only pass over the installed panes.
- Shortcuts: `shortcuts list` parsing, folders, caching and staleness,
  input after a name, run commands and input files, through a fake runner.
- System: strict matching (with negatives), the confirmation state
  machine, and every command, through a fake executor.
- The shipped manifests and examples load together without problems.

The UI is checked with `scripts/snapshot.sh`, which renders keyword mode,
global sections and the consent notice with the real emoji and calculator
extensions running through the real host. The System Settings, Shortcuts
(with sample shortcuts) and System scenes include the Confirm Shut Down?
step.

## Not in this version

- **URL install and updates** (`fastlight://install?source=…`): the manifest
  already has `id`, `version` and `source` for it.
- **A store / directory** of extensions.
- Per-extension preferences UI, multiple-action menus (⌘K), streaming or
  incremental results, sandboxing.
