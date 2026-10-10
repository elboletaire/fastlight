// Web addresses and web search, a Fastlight extension like any other: JSON
// lines on stdin and stdout (see docs/extensions). It makes no requests
// itself; the default browser opens what it offers.
import FastlightWeb
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let env = ProcessInfo.processInfo.environment
let settings = env["FASTLIGHT_DATA_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent(WebSettings.fileName) }
let web = WebExtension(settingsFile: settings)
print(WebExtension.ready)
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = web.handle(line) { print(reply) }
}
