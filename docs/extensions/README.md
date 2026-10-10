# Writing Fastlight extensions

An extension adds results to Fastlight. It is a folder with an
`extension.json` and a program in any language (shell, Python, Go, Node,
Swift…) that reads requests on stdin and writes replies on stdout, one JSON
object per line.

- **Keyword mode:** type the extension's keyword (`bc `, `go `) and it owns the
  result list. Backspace past the keyword to go back to normal search.
- **Global mode (opt-in):** a few results in the extension's own section,
  next to Applications and Files, when it answers within 80 ms.

Fastlight ships with two, built the same way:

- **Emoji.** Type `:` and a name or keyword (`:joy`, `:thumbs`, `:tada:`), or
  `emoji ` and the same. ↵ pastes into the app you were using, ⌘↵ copies.
  Queries of 3+ letters also show the top 3 emoji in normal search. `:tone`
  picks a skin tone.
- **Calculator.** Type math in normal search (`1920*1080`, `2^10`,
  `(3+4)/2`, `sqrt(2)`, `15% of 80`) and the answer is the Top Hit; or type
  `=` first to always get an answer or the reason there's none. ↵ copies the
  answer (without thousands separators, so it pastes cleanly), ⌘↵ pastes it.
  It knows `+ − × ÷` (also `*`, `/`, `x` between numbers), `^` or `**`,
  parentheses, `%` (`80 + 10%` is 88), `!`, `pi`, `e`, `tau` and `sqrt`,
  `cbrt`, `abs`, `round`, `floor`, `ceil`, `ln`, `log`, `log2`, `exp`,
  `sin`/`cos`/`tan` and their inverses (radians), `deg` and `rad`. Decimals
  take `.`, and `,` too where that's the decimal separator. Division by zero
  has no result.

<img src="images/emoji-keyword-light.jpg" width="640" alt="Keyword mode: the Emoji pill in the search bar, results for “joy”, and an action bar naming Paste Emoji and Copy Emoji">

How it works inside is in [design.md](design.md).

## Quickstart: bc in 30 lines of sh

This wraps the `bc` command (the built-in calculator doesn't need it; it's a
small, real example).

1. Make a folder in `~/Library/Application Support/Fastlight/Extensions/`
   (menu bar icon › Extensions › Open Extensions Folder):

   ```sh
   cp -R examples/extensions/bc ~/Library/Application\ Support/Fastlight/Extensions/
   ```

2. `extension.json` says what it is and how to run it:

   ```json
   {
     "id": "com.example.bc",
     "name": "bc",
     "version": "1.0.0",
     "icon": "terminal",
     "keywords": ["bc"],
     "command": ["/bin/sh", "bc.sh"]
   }
   ```

3. The program prints a handshake, then answers each request line
   ([full script](../../examples/extensions/bc/bc.sh)):

   ```sh
   echo '{"type":"ready","protocol":1}'
   while IFS= read -r line; do
     id=$(printf '%s\n' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
     [ -n "$id" ] || continue # notifications have no id
     expr=$(printf '%s\n' "$line" | sed -n 's/.*"query":"\([^"]*\)".*/\1/p')
     result=$(printf '%s\n' "$expr" | bc -l)
     printf '{"id":%s,"items":[{"id":"r","title":"%s","actions":[{"type":"copy","text":"%s"}]}]}\n' \
       "$id" "$result" "$result"
   done
   ```

4. Open Fastlight and type `bc 2*21`. The first time, Fastlight asks whether
   to allow it, showing what it will run. Then the result shows up; ↵ copies.

There is also a Python example, [quicklinks](../../examples/extensions/quicklinks)
(`go gh` opens GitHub). It needs `python3`, which macOS only has once the
Xcode Command Line Tools are installed; prefer `/bin/sh`, `/bin/zsh`,
`osascript` or a compiled binary for extensions you share.

Fastlight rescans the folder every time the panel opens, so editing or
dropping in an extension needs no restart. Any change to its files asks for
approval again. Problems show up in the menu (Extensions › ⚠︎ …), and each
extension's stderr goes to `~/Library/Logs/Fastlight/Extensions/<id>.log`
(Extensions › Show Extension Logs).

## Manifest reference

| Key | Required | Rules |
|---|---|---|
| `id` | yes | Lowercase reverse-DNS, like `com.example.bc`. Unique. |
| `name` | yes | Up to 40 characters. Shown on the pill, the section and the menu. |
| `version` | yes | Semantic version, like `1.0.0` or `1.1.0-beta.1`. |
| `keywords` | yes | 1–5 keywords. One ending in a letter or digit needs a space after it (`go gh`); one ending in a symbol doesn't (`:joy`). A keyword a built-in already uses (`:`, `emoji`, `=`) stays the built-in's. Can't start with `'` `^` `!` `.` `/` `~`, or be a search filter like `ext:`. |
| `command` | yes | Executable and arguments. Relative paths are inside the folder (and must be executable: `chmod +x`); absolute ones are for interpreters (`/bin/sh`, `/usr/bin/osascript`). Runs with the folder as working directory. |
| `description` | | Up to 200 characters; shown when asking for approval. |
| `author` | | Up to 100 characters. |
| `homepage`, `source` | | `http(s)` URLs. `source` is where the code lives; future one-click installs and updates will use it. |
| `icon` | | See [Icons](#icons). |
| `global` | | Opt in to normal search: `{"maxResults": 1–5 (3), "minQueryLength": 1–10 (2)}`. |
| `minFastlightVersion` | | The oldest Fastlight that can run it. |

Unknown keys are an error, so typos don't go unnoticed.

## Protocol reference (version 1)

Every line is one JSON object. Write a line per message and flush it (most
languages buffer stdout when it isn't a terminal: `flush=True` in Python,
`setvbuf`/`fflush` in C, `print` is fine in sh).

### Environment

| Variable | |
|---|---|
| `FASTLIGHT_PROTOCOL` | `1` |
| `FASTLIGHT_VERSION` | Fastlight's version. |
| `FASTLIGHT_EXTENSION_ID` | Your id. |
| `FASTLIGHT_DATA_DIR` | A folder for your settings and caches. Don't write into your own folder: that changes it and asks the user for approval again. |

`PATH` is `/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin`.

### Handshake

Your first line, within 5 seconds of starting:

```json
{"type":"ready","protocol":1}
```

### search

```json
{"id":3,"limit":50,"mode":"keyword","query":"joy","type":"search"}
```

`mode` is `keyword` or `global`; `query` is what follows the keyword (maybe
empty: show something useful) or the whole query in global mode. Reply with
up to `limit` items:

```json
{"id":3,"items":[{"id":"1f602","title":"Face with Tears of Joy","subtitle":"laugh, lol",
  "icon":{"emoji":"😂"},"accessory":":joy:",
  "actions":[{"type":"paste","text":"😂","title":"Paste Emoji"},{"type":"copy","text":"😂"}]}]}
```

or `{"id":3,"error":"what went wrong"}`, which the user sees.

Keys are sorted and there's no extra whitespace, which makes `sed` usable in
shell scripts, but use a real JSON parser when you can.

### run

Sent when the user picks a `run` action:

```json
{"data":3,"id":4,"item":"tone-3","name":"setTone","query":"tone","type":"run"}
```

Reply `{"id":4}` when done, or `{"id":4,"error":"…"}`.

### Notifications

No `id`, no reply. Ignore types you don't know.

```json
{"action":"paste","item":"1f602","type":"picked"}
```

`picked` says the user used one of your items (not sent for `run`, which you
see anyway). Use it for recents or ranking.

### Items

| Key | |
|---|---|
| `id` | Required, unique in the reply. |
| `title` | Required. |
| `subtitle` | Smaller, under the title. |
| `accessory` | Right-aligned text. |
| `icon` | See below. Defaults to your extension's icon. |
| `actions` | ↵ runs the first, ⌘↵ the second. |
| `topHit` | `true` asks to be the Top Hit in normal search. Only built-in extensions get it (the calculator's answer); it's ignored for others, so no extension can take ↵ away from apps and files. |

### Actions

| Action | Does |
|---|---|
| `{"type":"open","target":"https://…"}` | Opens a URL or a path (`~` works). |
| `{"type":"copy","text":"…"}` | Copies and closes. |
| `{"type":"paste","text":"…"}` | Pastes into the app the user was in. Needs Accessibility permission for Fastlight; without it, Fastlight copies and tells the user to press ⌘V. |
| `{"type":"reveal","path":"…"}` | Shows a file in Finder. |
| `{"type":"run","name":"…","data":…,"then":"close"}` | Sends you a `run` request. `then`: `close` (default), `refresh` (search again and stay), `stay`. |

Any action can have a `"title"`, shown in the action bar.

### Icons

| Form | Shorthand |
|---|---|
| `{"emoji":"😂"}` | `"😂"` (no ASCII letters) |
| `{"symbol":"globe"}` (an [SF Symbol](https://developer.apple.com/sf-symbols/)) | `"globe"` |
| `{"path":"icon.png"}` (an image, or any file for its Finder icon; relative to your folder) | `"./icon.png"`, `"/abs"`, `"~/x"` |
| `{"app":"com.apple.Safari"}` (an app's icon) | |

### Rules of the road

- Answer every request with its `id`; replies may come in any order.
- Keep going until stdin closes, then exit.
- Fastlight keeps at most one search in flight and skips queries typed
  meanwhile, so a slow extension sees fewer, newer queries.
- In global mode you have 80 ms per keystroke, process start included (it
  starts when the panel opens). Later answers are dropped.
- Keyword searches time out after 3 s, `run` after 10 s. Three timeouts in a
  row restart you; crashing three times in a minute turns you off until
  Extensions › Reload Extensions.
- Up to 20 lines that aren't protocol messages are tolerated (and logged), and
  no line may exceed 1 MiB. Log to stderr instead.
- Idle for 5 minutes, you're stopped; you're started again on next use.

## Security

Extensions run with Fastlight's permissions, which can include Full Disk
Access. Fastlight runs nothing from the extensions folder until the user
approves it, and asks again whenever any file in the extension's folder
changes (a SHA-256 over all of them, `.git` included, checked again right
before each start). Any extension can be turned off in the
Extensions menu. Only install extensions you trust, as you would any
command-line tool.
