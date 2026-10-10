cask "fastlight" do
  version "0.4.0"
  sha256 "09eab62e96170f409d489baf95662b1ccb27e012ac43eb2ab40595dec19e3c18"

  url "https://github.com/elboletaire/fastlight/releases/download/v#{version}/Fastlight-#{version}.dmg"
  name "Fastlight"
  desc "Spotlight-style launcher for apps and files with fast full-disk search"
  homepage "https://elboletaire.github.io/fastlight/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Fastlight.app"

  # Quitting Fastlight leaves its bundled fsearch daemon running (it outlives
  # the app on purpose). Stop that one, matched by its path inside this
  # bundle, and leave any other fsearch alone.
  uninstall quit:   "com.elboletaire.fastlight",
            script: {
              executable:   "/usr/bin/pkill",
              args:         ["-f", "^#{appdir}/Fastlight.app/Contents/Helpers/fsearch serve"],
              must_succeed: false,
            }

  # ~/Library/Application Support/FSearch is fsearch's own data dir (index,
  # socket, log), shared with a standalone fsearch. It's only removed when no
  # standalone fsearch is installed.
  zap script: {
        executable:   "/bin/sh",
        args:         [
          "-c",
          'for f in "$HOME/.local/bin/fsearch" /opt/homebrew/bin/fsearch /usr/local/bin/fsearch ' \
          '"$HOME/Library/LaunchAgents/mt.nd.fsearch.plist"; do [ -e "$f" ] && exit 0; done; ' \
          'rm -rf "$HOME/Library/Application Support/FSearch"',
        ],
        must_succeed: false,
      },
      trash:  [
        # Not ~/Library/Application Support/Fastlight/Extensions: those are
        # extensions the user installed, which zap shouldn't delete.
        "~/Library/Application Support/Fastlight/ExtensionData",
        "~/Library/Caches/com.elboletaire.fastlight",
        "~/Library/HTTPStorages/com.elboletaire.fastlight",
        "~/Library/Logs/Fastlight",
        "~/Library/Preferences/com.elboletaire.fastlight.plist",
        "~/Library/Saved Application State/com.elboletaire.fastlight.savedState",
      ]

  caveats <<~EOS
    Fastlight is not notarized yet, so macOS blocks it the first time it opens.
    Go to System Settings > Privacy & Security and click "Open Anyway".

    To find files in Desktop, Documents and other protected folders, give
    #{appdir}/Fastlight.app Full Disk Access in
    System Settings > Privacy & Security > Full Disk Access.

    Builds are signed ad hoc, so macOS drops that grant on every update:
    remove Fastlight from the Full Disk Access list and add it again.
  EOS
end
