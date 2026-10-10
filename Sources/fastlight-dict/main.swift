// The dictionary, a Fastlight extension like any other: JSON lines on stdin
// and stdout (see docs/extensions). Definitions come from the dictionaries
// macOS ships, offline.
import FastlightDictionary
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let dictionary = DictionaryExtension()
print(DictionaryExtension.ready)
// Fastlight starts global extensions when the panel opens, before the
// first keystroke: load the dictionaries now, not on the user's time.
dictionary.warmUp()
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = dictionary.handle(line) { print(reply) }
}
