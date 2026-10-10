import AppKit

let app = NSApplication.shared

// `--snapshot <dir> [--query q]...` renders the panel to PNGs and exits;
// each --query adds a scene with real results. See Snapshot.swift.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot") {
    let dir = args.indices.contains(i + 1) ? args[i + 1] : "build/snapshots"
    let live = args.indices.filter { args[$0] == "--query" && args.indices.contains($0 + 1) }.map { args[$0 + 1] }
    MainActor.assumeIsolated { Snapshot.run(into: URL(fileURLWithPath: dir), live: live) }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu. Info.plist sets LSUIElement too,
// this covers `swift run`.
app.setActivationPolicy(.accessory)
app.run()
