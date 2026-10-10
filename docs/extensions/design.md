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
   the bundled emoji picker: a normal protocol-1 extension
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
extension (registry order, built-ins first), Files. Extension items never
become the Top Hit, so an extension can't hijack ↵ for app launching.

## Extension folder and manifest

```text
~/Library/Application Support/Fastlight/Extensions/
  calculator/                 # folder name is free; the id is in the manifest
    extension.json
    calc.sh
```

`extension.json`:

```json
{
  "id": "com.example.calculator",
  "name": "Calculator",
  "version": "1.0.0",
  "description": "Evaluates arithmetic with bc.",
  "author": "Jane Doe",
  "homepage": "https://example.com/calculator",
  "source": "https://github.com/example/fastlight-calculator",
  "icon": "plus.forwardslash.minus",
  "keywords": ["="],
  "command": ["/bin/sh", "calc.sh"],
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

The UI is checked with `scripts/snapshot.sh`, which renders keyword mode,
global sections and the consent notice with the real emoji extension running
through the real host.

## Not in this version

- **URL install and updates** (`fastlight://install?source=…`): the manifest
  already has `id`, `version` and `source` for it.
- **A store / directory** of extensions.
- Per-extension preferences UI, multiple-action menus (⌘K), streaming or
  incremental results, sandboxing.
