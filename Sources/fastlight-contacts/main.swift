// Contacts, a Fastlight extension like any other: JSON lines on stdin and
// stdout (see docs/extensions). It reads the address book once access is on,
// keeps it in memory, and only asks macOS for access when the user picks
// "Allow Access to Contacts…".
//
//   fastlight-contacts [--sample [access-file]]
//
// --sample answers from made-up cards instead (for screenshots); the file,
// if given, holds the access state to pretend ("notDetermined", "denied"…).
import FastlightContacts
import FastlightPIM
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())
let source: ContactSource
if let i = args.firstIndex(of: "--sample") {
    source = SampleContacts(accessFile: args.indices.contains(i + 1) ? args[i + 1] : nil)
} else {
    source = SystemContacts()
}
let ext = ContactsExtension(source: source)

print(ContactsExtension.ready)
ext.start()
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = ext.handle(line) { print(reply) }
}
