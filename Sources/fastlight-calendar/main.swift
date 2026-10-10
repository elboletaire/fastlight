// Calendar and Reminders, two Fastlight extensions served by one helper:
// JSON lines on stdin and stdout (see docs/extensions). It reads what's
// coming up once access is on, keeps it in memory, and only asks macOS for
// access when the user picks "Allow Access to Calendars…" (or Reminders).
//
//   fastlight-calendar events|reminders [--sample [access-file]]
//
// --sample answers from made-up events instead (for screenshots); the file,
// if given, holds the access state to pretend ("notDetermined", "denied"…).
import FastlightCalendar
import FastlightPIM
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())
guard let kind = args.first.flatMap(CalendarKind.init(rawValue:)) else {
    FileHandle.standardError.write(Data("usage: fastlight-calendar events|reminders [--sample [access-file]]\n".utf8))
    exit(2)
}
let source: CalendarSource
if let i = args.firstIndex(of: "--sample") {
    source = SampleCalendar(accessFile: args.indices.contains(i + 1) ? args[i + 1] : nil)
} else {
    source = SystemCalendar()
}
// Two extension types share the helper; each run serves one of them.
let handle: (String) -> String?
let start: () -> Void
if kind == .events {
    let ext = EventsExtension(source: source)
    (handle, start) = (ext.handle, ext.start)
} else {
    let ext = RemindersExtension(source: source)
    (handle, start) = (ext.handle, ext.start)
}

print(PIMReply.ready)
start()
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = handle(line) { print(reply) }
}
