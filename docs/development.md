# Development

How to build, test and release Fastlight, how its translations work, and how it talks to fsearch. For using it, see the [README](../README.md).

## Build from source

You need the Swift 6 toolchain (the Command Line Tools are enough, no Xcode) and Rust 1.85+ to compile fsearch:

```sh
brew install rustup && "$(brew --prefix rustup)/bin/rustup" default stable
git clone --recursive https://github.com/elboletaire/fastlight.git && cd fastlight
make            # build/Fastlight.app, with fsearch embedded
```

| Command | Does |
|---|---|
| `make run` | Build and open the app |
| `make install` | Build, quit the running copy and replace `/Applications/Fastlight.app` |
| `make dmg` | Build `build/Fastlight-<version>.dmg` |
| `make test` | Run the test suite |
| `make clean` | Remove build output |

`make dmg` lays out the DMG window (background, icon positions) with [dmgbuild](https://github.com/dmgbuild/dmgbuild), which it runs through [uv](https://docs.astral.sh/uv/) (`brew install uv`) or Python 3.10+. Without either it builds a plain DMG and warns.

`UNIVERSAL=1 make dmg` builds for both Apple Silicon and Intel, and `CODESIGN_IDENTITY="Developer ID Application: …"` signs with a real identity and the hardened runtime. The [release workflow](../.github/workflows/release.yml) does both on `v*` tags, and notarizes when the secrets listed at its top are set. Run by hand from a branch, it only builds: the DMG is left as the run's artifact and no release is touched.

Releasing is merging a version bump: when `CFBundleShortVersionString` in `Resources/Info.plist` changes on `main` to a version with no tag yet, [`tag-release.yml`](../.github/workflows/tag-release.yml) tags it and runs the release workflow. Tags aren't pushed by hand. Once the release is published, the workflow points the Homebrew cask in [elboletaire/homebrew-tap](https://github.com/elboletaire/homebrew-tap) at the new DMG; see [packaging/homebrew](../packaging/homebrew/README.md).

The bundled fsearch keeps itself current: every Monday, [`fsearch.yml`](../.github/workflows/fsearch.yml) checks fsearch's `main`. If it has moved on, it opens a PR (branch `deps/fsearch`) that updates the submodule, bumps the patch version and lists the upstream changes. CI runs on it, and merging it releases the new version. Until then it keeps that PR current when upstream moves on again (or `main`'s version changes), but never rewrites the branch once someone else has pushed to it: it comments on the PR instead. `scripts/bump-fsearch.sh` does the same locally. The workflow can also be run from the Actions tab at any time.

> [!IMPORTANT]
> Local builds are signed ad hoc, and macOS ties Full Disk Access to the signature. Grant it again after each rebuild, or sign with a real identity.

`scripts/snapshot.sh` renders the panel with sample data to `build/snapshots/`, in light and dark, which is handy when working on the design. `--language ca` renders in another language (into `build/snapshots/ca/`) and `--only settings,about,convert` keeps the scenes whose names start with those.

## Translations

Fastlight speaks English, Catalan and Spanish: the app's own UI and what the built-in extensions show. It follows the order of languages in System Settings › General › Language & Region, and uses English when none of them is translated. What you type stays English: keywords, units, date phrases and search filters work the same in every language.

The strings live in `Resources/<lang>.lproj/`, one table per module (`App.strings`, `Core.strings`, `Convert.strings`…), with plurals in a matching `.stringsdict`, and permission prompts in `InfoPlist.strings`. The keys are the English text, so a missing translation shows English. Code looks them up with `L("…")` and `Lp("one", "other", count:)`, defined per module in `L10n.swift`, through `Sources/FastlightL10n`. No Xcode needed: there are no String Catalogs to compile, and `scripts/bundle.sh` copies the lproj folders into `Contents/Resources`.

- **The app and its helpers** find `Contents/Resources` from their own executable (`Contents/MacOS` or `Contents/Helpers`). The app tells its extensions which language it picked through `FASTLIGHT_LANGUAGE`.
- **Outside the bundle** (`swift run`, tests, snapshots) it's English, unless `FASTLIGHT_LANGUAGE` names a language, which is then read from the source tree. Tests can render a language with `Localizer.$override.withValue(Localizer.named("ca")) { … }`.
- **Built-in extensions' names and descriptions** are translated in `Extensions.strings`, keyed by the English in their `extension.json`. Third-party extensions are shown as their manifests say.
- **To add a language**, copy `Resources/en.lproj` to `Resources/<code>.lproj`, translate the values, add the code to `CFBundleLocalizations` in `Resources/Info.plist` and to `translations` in `Tests/FastlightL10nTests/CatalogTests.swift`. The tests check that every key the code uses is in each table, and that the format arguments and plural forms match; `plutil -lint Resources/*.lproj/*` catches syntax errors. A language with plural forms other than "one" and "other" needs its rule in `Localizer.category`.

## How it works

Fastlight is a menu-bar app in Swift. It registers a global hotkey and shows a floating panel. Apps come from its own index of `/Applications`, `/System/Applications`, `~/Applications` and a few system folders, ranked by name match and by how often you open them. Files come from fsearch: Fastlight starts the bundled daemon at `Fastlight.app/Contents/Helpers/fsearch` and talks to it as JSON lines over `~/Library/Application Support/FSearch/fsearch.sock`.

| Path | What's there |
|---|---|
| `Sources/FastlightCore` | Search providers, fsearch client, app index and ranking, file result filter, extension host. No AppKit, covered by unit tests. |
| `Sources/Fastlight` | Menu-bar app, hotkey, panel and results UI. |
| `Sources/FastlightEmoji`, `Sources/fastlight-emoji` | The bundled emoji picker extension. Its data is in `Extensions/emoji`, regenerated by `scripts/generate-emoji.swift`. |
| `Sources/FastlightCalc`, `Sources/fastlight-calc` | The bundled calculator extension: its own expression parser, no `bc`. |
| `Sources/FastlightConvert`, `Sources/fastlight-convert` | The bundled conversions extension: units, time zones and dates. |
| `Sources/FastlightSystem`, `Sources/fastlight-system` | The bundled System Settings, Shortcuts and System extensions: one helper, three manifests in `Extensions/settings`, `shortcuts` and `system`. |
| `Sources/FastlightContacts`, `Sources/fastlight-contacts` | The bundled Contacts extension: search and actions, and the Contacts framework behind a protocol. |
| `Sources/FastlightCalendar`, `Sources/fastlight-calendar` | The bundled Calendar and Reminders extensions, one EventKit helper for both. `Sources/FastlightPIM` is what they share with Contacts: access states, permission items, the background loader. |
| `Sources/FastlightDictionary`, `Sources/fastlight-dict` | The bundled dictionary extension, on DictionaryServices. |
| `Sources/FastlightWeb`, `Sources/fastlight-web` | The bundled web extension: address detection and web search. |
| `examples/extensions` | Example extensions in sh and Python. |
| `third_party/fsearch` | fsearch, as a git submodule pinned to a known commit, moved forward weekly by a PR. |
| `scripts/` | Build, bundle, DMG, test and snapshot scripts, driven by the `Makefile`. |
| `assets/brand` | Logo, icons and the [brand guide](../assets/brand/BRAND.md). |

Fastlight starts the fsearch daemon as its own child process, so the Full Disk Access you give Fastlight covers it. fsearch decides whether it has that access when it starts, so Fastlight keeps an eye on both sides:

- **Only its own daemon.** Before connecting, Fastlight reads the daemon's pid from `socket.lock` and its executable from the system. A daemon started by another binary (a standalone `fsearch`, or a Fastlight elsewhere on disk that has quit) runs under someone else's permissions, so Fastlight stops it and starts the bundled one. So does a daemon older than the bundled binary, left over from before an update. There are two exceptions. fsearch's own login agent (`fsearch install --login`): launchd would restart it straight away, so Fastlight uses it as is, and Full Disk Access has to be granted to `~/.local/bin/fsearch` instead. And the daemon of another copy of Fastlight that is still running (an installed one next to a development build, say): replacing it would only have the two copies take turns stopping each other's daemon, so it's used as is, with that copy's Full Disk Access, until that copy quits.
- **Access granted later.** When Fastlight has Full Disk Access but its daemon reports none, it restarts the daemon, which then scans the folders it skipped. It checks at launch and each time the panel opens, and gives up after a few tries rather than loop.
- **Quitting.** The daemon keeps running after Fastlight quits, so the next launch answers at once and changes keep being tracked. That's safe now that a daemon that isn't Fastlight's, or is outdated, gets replaced.

## Website

The project site lives in `site/`: plain HTML, CSS and a little vanilla JavaScript, with no build step. [`pages.yml`](../.github/workflows/pages.yml) publishes it to <https://elboletaire.github.io/fastlight/> on every push to `main` that touches `site/`. To preview it locally:

```sh
python3 -m http.server -d site    # then open http://localhost:8000
```

The social card `site/og.png` is rendered from `site/og/og.html`; see `site/og/README.txt`.
