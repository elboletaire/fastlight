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
 Sources/FastlightConvert + Sources/fastlight-convert
   the bundled conversions (units, clocks, dates), likewise
 Sources/FastlightSystem + Sources/fastlight-system
   System Settings, Shortcuts and System: three built-ins, one helper
 Sources/FastlightDictionary + Sources/fastlight-dict
 Sources/FastlightWeb + Sources/fastlight-web
   the bundled dictionary and web addresses/search, likewise
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
search syntax are rejected: anything starting with `'`, `^`, `!`, `.`, `/`,
`~` or `"`, and anything starting with an fsearch filter (`ext:`, `in:~`,
`type:image`, …), so documented queries like `in:~/src readme` stay file
searches. A keyword already taken by
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
the extension folder and this environment (plus `HOME`, `USER`, `LOGNAME`,
`TMPDIR`, `LANG` (`en_US.UTF-8` when unset), `LC_ALL` and `SHELL` passed on
when set, and `PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin`):

| Variable | Value |
|---|---|
| `FASTLIGHT_PROTOCOL` | Highest protocol version Fastlight speaks (`1`). |
| `FASTLIGHT_VERSION` | App version, e.g. `0.2.0`. |
| `FASTLIGHT_EXTENSION_ID` | The manifest id. |
| `FASTLIGHT_DATA_DIR` | A writable folder for settings and caches: `~/Library/Application Support/Fastlight/ExtensionData/<id>/`. Writing inside the extension folder changes its fingerprint and asks the user again. |
| `FASTLIGHT_LANGUAGE` | The language the app's strings are in (`en`, `ca`, `es`). The built-ins speak it; anyone else may ignore it. |

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
| 3 timeouts in a row | Process killed; restarted on next use. The kill counts as a crash (below). |
| Process exits or crashes | Pending requests fail; restarted on next use. 3 crashes within 60 s (kills for timeouts, garbage or a missing `ready` included) mark it **failed** until Reload Extensions or the files change. |
| Non-JSON or unexpected lines on stdout | Logged and ignored; after 20 of them, or one line over 1 MiB, the process is killed (counts as a crash). |
| Idle for 5 minutes | stdin closed, then SIGTERM at 0.5 s if still running, then SIGKILL at 1.5 s. |
| Reload Extensions, or its files change | Stopped like when idle; a request still waiting fails with "X was stopped before it answered." |
| Fastlight quits | stdin closed and SIGTERM at once for every extension; nothing runs after Fastlight exits, so there is no SIGKILL. Extensions should exit when stdin closes (EOF), which also covers a crash of Fastlight itself. |

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
  symlinked folder is hashed through the link. Symlinks inside the folder
  aren't followed (their target path is hashed), so one that leads out of
  the folder, dangling or not, is refused: the code behind it could change
  without a new fingerprint. Folders over 100 MB or 5,000
  files are refused.
- `ConsentStore` remembers approved `id → fingerprint` pairs. Nothing is
  spawned unless the current fingerprint is approved: `ExtensionHost` checks
  consent before every request, independent of the UI, and checks the
  folder again right before every process start, so files changed since the
  last rescan don't run either. That check compares the folder's stamp with
  the one the library hashed (or the last start verified) and only re-hashes
  when it moved, so starting an unchanged extension costs a directory
  listing, not a read of every file.
- Typing the keyword of a new or changed extension shows an inline notice
  in the panel ("X needs your permission before it can run.") with a
  Review… button; ↵ does the same. Review (or picking the extension in the
  Extensions menu) hides the panel and asks with a standard alert showing
  the name, id, version, folder and command, and whether it is new or
  changed since an approved version. If the files change after the last
  rescan, the host refuses the start, and keyword mode rescans and shows
  the same notice, so Review asks about the files now on disk. Global search never
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
  (`sqrt(-1)`), anything that overflows, and input over 1,000 bytes or
  nested (parentheses, unary minus, `^`) or chained (`1+1+…`) more than
  100 deep, which would otherwise overflow the stack.
- Normal search only shows an answer when the query computes something: a
  bare number (`2026`), a constant alone (`pi`), dates (`2026-10-10`,
  `10/10/2026`, `2024-05`, `12-2025`, and `2024-0` while typing one), two
  numbers of 3+ digits joined by `-` (`555-1234`) and anything that
  doesn't parse are left alone. Then it is
  the Top Hit. Keyword mode always answers or says why not.
- Display: integers a Double holds exactly (below 2⁵³) as they are
  (`1234567890123 + 1` = 1,234,567,890,124), anything else rounded to 12
  significant digits (0.1 + 0.2 = 0.3), at most 10
  decimals, the locale's grouping (`2,073,600`), and `1.5 × 10²⁰` beyond
  10¹⁵ or below 10⁻⁹. The subtitle is the expression as understood
  (`1920 × 1080 =`). ↵ copies the answer without grouping, so it pastes
  into code and spreadsheets; ⌘↵ pastes it, as in Raycast.

## Conversions

`Sources/fastlight-convert` is the third built-in (`id
com.elboletaire.fastlight.convert`, keyword `convert`, global with one
result). `FastlightConvert` parses three kinds of question, in this order:
dates, clocks, units. Everything is in-process and offline; a reply takes
well under a millisecond once the tables are built, which happens before
the handshake.

- Units: Foundation `Dimension`s and their converters, redefined with the
  exact factor where Foundation rounds (a pound, US cups, km/h). Aliases
  are folded (case, diacritics, `²`, `µ`), numbers are split from units
  (`10km`, `72°f`, `5'11"`), and an amount may have several terms of one
  kind (`3 ft 4 in`, `1 h 30 min`). Numbers follow the locale like the
  calculator's, and so does formatting, at six significant digits.
- Clocks: every city in `TimeZone.knownTimeZoneIdentifiers`, minus
  Antarctica and names that are everyday words (`christmas`, `easter`),
  plus a small table of countries, big cities and abbreviations. `PST`
  means Pacific time, so it reads PDT in summer. Offsets (`utc+5:30`) work.
- Dates: on calendar days in the local time zone, so DST never shifts an
  answer. A day without a year is the next one (the last one for `since`);
  weeks are ISO 8601.
- Global search answers only when the query clearly is one (see the
  extension guide), so it never competes with the calculator: units, places
  and date words are unknown names to it, and plain math has no unit.
  Keyword mode also takes a place, a day or an ambiguous unit on its own.

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
  so the index is cached in
  `FASTLIGHT_DATA_DIR/settings.json`, keyed by macOS version, languages
  and battery, and rebuilt in the background after the handshake only when
  it's missing or a day old (for third-party panes), since a scan costs
  about 0.6 s of CPU. Until there's an index, normal search has
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
  removed once the shortcut ends (or, left by a helper that quit first,
  a day later, swept on the next start). ⌘↵ opens
  `shortcuts://open-shortcut?name=…`.

**System** (keyword `sys`; global, 3 results for 3+ characters).

| Action | How | Asks first | Permission |
|---|---|---|---|
| Lock Screen | `SACLockScreenImmediate` (login framework, as the Apple menu) | | none |
| Sleep, Sleep Displays | `pmset sleepnow`, `pmset displaysleepnow` | | none |
| Start Screen Saver | `open -b com.apple.ScreenSaver.Engine` | | none |
| Toggle Dark Mode | `osascript`: System Events' appearance preferences | | Automation (System Events) |
| Eject All Disks | `diskutil eject` per external, removable or image volume (the whole disk: its other volumes, gone by their turn, are skipped), `diskutil unmount` per network volume | | none |
| Empty Trash | `osascript`: Finder's `empty trash` | yes | Automation (Finder) |
| Log Out, Restart, Shut Down | `osascript`: loginwindow's `aevtrlgo`, `aevtrrst`, `aevtrsdn` | yes | Automation (loginwindow) |

The loginwindow events skip its own confirmation dialog (Fastlight has
asked already), but apps still get to save or cancel, as with the Apple
menu. Nothing needs Accessibility.

The Apple events are sent by `osascript`, started by `fastlight-system`,
started by Fastlight: TCC asks on behalf of the responsible app, so the
Automation prompt names Fastlight and shows its
`NSAppleEventsUsageDescription`. Under the hardened runtime (a real
signing identity), it denies them with -1743 and no prompt unless that app
has `com.apple.security.automation.apple-events`; `Fastlight.entitlements`
has it, and `fastlight-system.entitlements` gives it to the helper too,
which costs nothing and covers it being checked on the process that
starts `osascript`.

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
  armed in the last 5 seconds, but not in the first 0.4 (a held ↵
  repeating, not a second press), and uses the arming up either way. The
  panel never repeats ↵, ⌘↵ or the other action keys of a held key
  either, only ↑↓ and Tab. ⌘↵ is
  `disarm`. `perform` (the one-step action) refuses disruptive actions,
  so no reply shape can skip the second step.

## Contacts, Calendar and Reminders

Three more built-ins (`com.elboletaire.fastlight.contacts`,
`…calendar`, `…reminders`) read the system's personal-information stores.
`Sources/fastlight-contacts` uses the Contacts framework;
`Sources/fastlight-calendar` uses EventKit and serves both Calendar
(`fastlight-calendar events`) and Reminders (`fastlight-calendar
reminders`), two manifests on one binary, because the protocol doesn't tell
an extension which of its keywords was typed. Everything but the framework
calls lives in `FastlightContacts` and `FastlightCalendar` behind
`ContactSource` and `CalendarSource`, so it's tested with fakes;
`FastlightPIM` holds what the three share (`StoreExtension`).

- **Permissions.** The helpers are Fastlight's children, so TCC attributes
  their requests to Fastlight, the responsible app: the prompts name
  Fastlight, use its `NSContactsUsageDescription`,
  `NSCalendarsFullAccessUsageDescription` and
  `NSRemindersFullAccessUsageDescription` (macOS 14's full-access keys; the
  older ones only matter for apps that run on 13), and the switches in
  System Settings are Fastlight's. Under the hardened runtime (a real
  signing identity in `scripts/bundle.sh`), TCC also wants
  `com.apple.security.personal-information.addressbook` and `.calendars`
  (which covers Reminders) on the responsible app, or it denies without a
  prompt; `Resources/Fastlight.entitlements` gives them to the app, and
  `Resources/fastlight-pim.entitlements` to the two helpers. Ad-hoc builds have no hardened runtime and are signed
  without entitlements.
- **When it asks.** Never on its own. The helpers check the authorization
  status (which never prompts) on every search. Without access, global
  search returns nothing, and keyword mode returns one item: *Allow Access
  to Contacts…* (a `run` action that calls `requestAccess` /
  `requestFullAccessToEvents` / `requestFullAccessToReminders` and closes
  the panel, so the alert is in front), or, when denied or write-only, a
  link to `x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts`
  (`Privacy_Calendars`, `Privacy_Reminders`); restricted says so.
- **Speed.** Right after the handshake, and only when access is already
  on, the helper reads the store in the background: every card (name parts,
  nickname, company, job title, emails, phones), events from the start of
  today to 14 days ahead, incomplete reminders. Searches run over that copy
  in memory. It's read again in the background once older than 60 s; keyword
  mode waits up to 0.3 s for the fresher copy (2.5 s for the first), global
  search at most 30 ms and otherwise answers empty for that keystroke.
  Losing access drops the copy.
- **Matching.** Words are folded (case, accents, width) and every query
  word must start a word. Contacts: name, then nickname, then company, then
  email; whole words beat prefixes, a given name beats a family name, the
  exact full name wins; `@` (or a dot and no spaces) searches addresses, a
  query of digits (spaces, `+`, `-`, parentheses allowed) searches numbers.
  Global search only takes strong matches: names, nicknames, companies, the
  start of an address (3+ characters) or 4+ digits. Events and reminders:
  title matches first, then location, calendar, notes or list; global
  search only takes title matches.
- **Links.** Cards open with `addressbook://<identifier>` (Contacts'
  identifier already ends in `:ABPerson`), events with
  `ical://ekevent/<calendarItemIdentifier>?method=show&options=more` (a
  repeating event adds the occurrence's start,
  `ical://ekevent/20261016T090000Z/<id>?…`, UTC for timed events, the wall
  clock for all-day ones), reminders with
  `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>`. None of
  these schemes is documented. Mail is `mailto:`, calls `tel:` (FaceTime
  places them), Messages `sms:`, FaceTime `facetime:` and `facetime-audio:`.
- **Dates** are in English, like the rest of Fastlight, with the region's
  conventions (24-hour clock, day-month order) and the user's time zone:
  "Today, 10:00 – 10:30", "Now, until 09:15", "Tomorrow, all day",
  "Thursday, 10:00 – 12:00", "Sun, 18 Oct, 19:00 – 20:00",
  "Overdue · Yesterday".
- **Screenshots.** `--sample [access-file]` makes a helper answer from
  made-up people and events instead, with the access state read from that
  file. `scripts/snapshot.sh` runs the built-ins that way, so it never
  touches (or asks for) the real stores.

## The dictionary

`Sources/fastlight-dict` (`id com.elboletaire.fastlight.dictionary`,
keywords `define` and `dict`, keyword mode only). The logic is the
`FastlightDictionary` library.

- Source: the public `DCSCopyTextDefinition` with no dictionary, which asks
  the dictionaries turned on in Dictionary › Settings in their order, like
  Look Up. Offline. The private DictionaryServices calls
  (`DCSGetActiveDictionaries`, `DCSCopyRecordsForSearchString`,
  `DCSRecordCopyData`) would give each dictionary's name, every dictionary's
  entry and structured HTML instead of one flattened line, but they are
  undocumented and could change with any macOS release, so they're not used.
  The cost: one entry (the first dictionary's) and a text to shape.
- Shaping (`DefinitionText`): the headword (the query when the entry starts
  with it, else the entry's first word: `flies` finds `fly`), the
  pronunciation between the first pipes, then senses split on sense numbers
  (`1`, `2`…, `①`) and parts of speech in the languages macOS ships
  dictionaries for most (`noun`, `transitive verb`, `nom masculí`,
  `feminine noun`…). Each sense is cut at its examples (`:`), sub-senses
  (`•`), phrases (`▸`) and second sentence; `ORIGIN`, `DERIVATIVES` and the
  like are dropped. Every dictionary flattens entries differently, so this
  is a heuristic tested against real entries from the Oxford, bilingual,
  Larousse and Japanese dictionaries. The lookup sits behind a
  `DefinitionSource` protocol, so tests don't depend on what's installed;
  one test uses the real API and is skipped when nothing answers.
- Rows: the sense is the title, since it's what you came for, and
  `headword · part of speech · pronunciation` the subtitle. ↵ opens
  `dict://word` in Dictionary.app, ⌘↵ copies the sense. Keyword mode shows
  up to 8 senses, or says there's no entry.
- Not in normal search: a definition matches most common words
  (`invoice`, `party`), and its row would sit above Files on each of them.
  Normal search stays apps and files; `define ` is one word away.
- Timing: the first lookup in a process loads the dictionaries, 30–60 ms;
  after that a lookup takes 1–3 ms. Keyword searches have 3 s, so there's
  no warm-up: it would cost the same on the first request.

## The web extension

`Sources/fastlight-web` (`id com.elboletaire.fastlight.web`, keyword `web`,
global with one result). The logic is the `FastlightWeb` library. It never
makes a request: `open` actions hand the URL to the default browser, whose
icon the address row shows.

- Addresses (`WebAddress`): `http(s)://` and a host as typed; `localhost`
  with a port or path, and IPv4 addresses, with `http://`; otherwise a
  domain of valid labels whose TLD is in a short list of common ones, with
  an optional port and path, with `https://`. TLDs that double as file
  extensions (`app`, `sh`, `zip`, `mov`, `pl`, `cc`, `ai`, `so`, `in`) also
  need `www.`, a port or a path; other TLDs need the scheme. No spaces, no
  `@`, no other schemes. In global mode an address is the Top Hit (the web
  extension is a built-in): typing one and pressing ↵ goes there.
- Search: `web <query>` lists every engine, the default first, as
  `Search Google for “query”`. The query is percent-encoded as one opaque
  value (everything but `A–Z a–z 0–9 - . _ ~`, spaces as `%20`), so it is
  safe in a query string or a path. If the query is also an address,
  opening it comes first. Per-engine keywords (`g `, `ddg `) would need the
  search request to say which keyword was typed; one engine list under one
  keyword doesn't, and keeps one-letter keywords from shadowing searches.
- Settings: `settings.json` in `FASTLIGHT_DATA_DIR`, read on every keyword
  search so edits apply at once. `engine` picks the default, `engines` adds
  or replaces engines (`id`, `name`, an `http(s)` `url` with `%s`). Problems
  are listed as rows and the valid parts still apply. The **Default Search
  Engine** row, shown for an empty query, is a `run` action that writes a
  starting file if there's none and opens it with `open -t`.
- Normal search never gets a "search the web" row: it would sit above
  Files on every query.

## Translations of the built-ins

The built-ins speak the app's language (English, Catalan or Spanish; see
"Translations" in the README). Their helpers use the same lookup as the app
(`Sources/FastlightL10n`): each module has its own table,
`Resources/<lang>.lproj/<Module>.strings` (and `.stringsdict` for plurals),
and a helper finds them in `Fastlight.app/Contents/Resources`, two folders up
from `Contents/Helpers/<helper>`. The app passes `FASTLIGHT_LANGUAGE`, so a
helper never disagrees with the panel around it, and dates inside a sentence
are formatted in that language too.

Only what they show is translated. What they understand stays English:
keywords (`define`, `cal`, `sys`…), units and date phrases ("10 km in mi",
"days until dec 25") and action names, so a query means the same whatever
the UI language. System actions also match their translated titles.

Manifests stay English and the format doesn't change. The app shows a
built-in's `name` and `description` through the `Extensions` table, keyed by
the English text; that lookup applies only to built-ins (`LoadedExtension.name`
and `summary`), so a third-party extension is shown exactly as its manifest
says, and works as before.

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
- Conversions: units, aliases and exact factors, parsing variants and
  locales, places and offsets, DST on fixed dates, date math against a fixed
  "now", strict global gating, and the boundary with the calculator.
- System Settings: discovery against fixture bundles (names per language,
  old `.strings`, code names, hidden and non-URL bundles, Battery or
  Energy, icons, pages only with their anchor), URLs, ranking and its
  negatives, the cache, plus a read-only pass over the installed panes.
- Shortcuts: `shortcuts list` parsing, folders, caching and staleness,
  input after a name, run commands and input files, through a fake runner.
- System: strict matching (with negatives), the confirmation state
  machine, and every command, through a fake executor.
- Contacts, Calendar and Reminders, against fake stores (never the real
  ones): matching and ranking, global gating, detail rows, every access
  state and that nothing asks or reads without access, URL construction,
  date formatting and the 14-day window with a fixed clock, time zone and
  locale, the background loader's staleness and time bounds.
- Dictionary: shaping real entries from several kinds of dictionary, the
  `dict://` links, protocol replies, and one lookup
  through the real DictionaryServices (skipped when no dictionary answers).
- Web: addresses and many file names and filters that aren't, query
  encoding, engines, settings parsing and its problems, protocol replies.
- The shipped manifests and examples load together without problems.

The UI is checked with `scripts/snapshot.sh`, which renders keyword mode,
global sections and the consent notice with the real built-in extensions
running through the real host. The System Settings, Shortcuts (with sample
shortcuts) and System scenes include the Confirm Shut Down? step, and
Contacts, Calendar and Reminders answer from sample data.

## Not in this version

- **URL install and updates** (`fastlight://install?source=…`): the manifest
  already has `id`, `version` and `source` for it.
- **A store / directory** of extensions.
- Per-extension preferences UI, multiple-action menus (⌘K), streaming or
  incremental results, sandboxing.
