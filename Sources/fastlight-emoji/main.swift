// The emoji picker, a Fastlight extension like any other: JSON lines on
// stdin and stdout (see docs/extensions). Fastlight starts it in its
// extension folder, next to emoji.tsv.
import FastlightEmoji
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let env = ProcessInfo.processInfo.environment
let dataPath = CommandLine.arguments.dropFirst().first ?? "emoji.tsv"
guard let tsv = try? String(contentsOfFile: dataPath, encoding: .utf8) else {
    FileHandle.standardError.write(Data("fastlight-emoji: can't read \(dataPath)\n".utf8))
    exit(1)
}
let store = EmojiStore(file: env["FASTLIGHT_DATA_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent("state.json") })
let ext = EmojiExtension(index: EmojiIndex(tsv: tsv, maxVersion: EmojiExtension.supportedVersion()), store: store)

print(EmojiExtension.ready)
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = ext.handle(line) { print(reply) }
}
