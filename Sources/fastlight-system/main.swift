// The System Settings, Shortcuts and System extensions, Fastlight
// extensions like any other: JSON lines on stdin and stdout (see
// docs/extensions). One binary, three manifests; the first argument says
// which one this process is.
import FastlightSystem
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let env = ProcessInfo.processInfo.environment
let data = env["FASTLIGHT_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
let handler: any LineHandler
var start: () -> Void = {}
switch CommandLine.arguments.dropFirst().first {
case "settings":
    let ext = SettingsExtension(scanner: SettingsScanner(), cacheFile: data?.appendingPathComponent("settings.json"))
    handler = ext
    start = ext.start
case "shortcuts":
    let ext = ShortcutsExtension(cacheFile: data?.appendingPathComponent("shortcuts.json"))
    handler = ext
    start = ext.start
case "actions":
    handler = SystemActionsExtension()
default:
    FileHandle.standardError.write(Data("usage: fastlight-system settings|shortcuts|actions\n".utf8))
    exit(2)
}

print(Reply.ready)
// After the handshake, so slow scans never delay it.
start()
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = handler.handle(line) { print(reply) }
}
