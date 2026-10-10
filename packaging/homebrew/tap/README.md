# elboletaire/homebrew-tap

Homebrew casks for [Fastlight](https://elboletaire.github.io/fastlight/), a Spotlight-style launcher for macOS.

```sh
brew install --cask elboletaire/tap/fastlight
```

Installing by its full name trusts only that cask, as Homebrew 6 and later require for third-party taps. Then:

- `brew upgrade --cask fastlight` updates it (it quits and reopens Fastlight).
- `brew uninstall --cask fastlight` removes it and stops its search daemon.
- `brew uninstall --zap --cask fastlight` also deletes its settings, logs and extension data (extensions you installed stay), and fsearch's index in `~/Library/Application Support/FSearch` unless a standalone fsearch is installed.

Fastlight isn't notarized yet: the first time it opens, macOS blocks it. Go to System Settings › Privacy & Security and click **Open Anyway**. See the [Fastlight README](https://github.com/elboletaire/fastlight#install) for Full Disk Access.

The cask is updated by Fastlight's release workflow. Its source is [`packaging/homebrew/tap`](https://github.com/elboletaire/fastlight/tree/main/packaging/homebrew/tap) in the Fastlight repository: change it there, not here.
