import AppKit
import FastlightCore
import FastlightL10n

let app = NSApplication.shared
// A write to a pipe or socket whose reader is gone fails instead of
// killing the app; see BrokenPipes.
BrokenPipes.ignore()

// `--snapshot <dir> [--query q]...` renders the panel to PNGs and exits;
// each --query adds a scene with real results. See Snapshot.swift.
// `--language ca` renders in that language; `--only settings,about,convert`
// renders just the scenes whose names start with one of those.
let args = CommandLine.arguments
func values(_ flag: String) -> [String] {
    args.indices.filter { args[$0] == flag && args.indices.contains($0 + 1) }.map { args[$0 + 1] }
}
if let i = args.firstIndex(of: "--snapshot") {
    let dir = args.indices.contains(i + 1) ? args[i + 1] : "build/snapshots"
    if let language = values("--language").last {
        // Before any string is looked up; the extensions inherit it.
        setenv(Localizer.environmentKey, language, 1)
        // AppKit's own strings (file kinds, buttons) follow too.
        UserDefaults.standard.setVolatileDomain(["AppleLanguages": [language]], forName: UserDefaults.argumentDomain)
    }
    let only = values("--only").flatMap { $0.split(separator: ",").map(String.init) }
    MainActor.assumeIsolated { Snapshot.run(into: URL(fileURLWithPath: dir), live: values("--query"), only: only) }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu. Info.plist sets LSUIElement too,
// this covers `swift run`.
app.setActivationPolicy(.accessory)
app.run()
