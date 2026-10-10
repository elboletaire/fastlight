// Conversions, a Fastlight extension like any other: JSON lines on stdin
// and stdout (see docs/extensions). Units, time zones and dates are all
// in-process and offline, so it answers well within global search's budget.
import FastlightConvert
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let convert = ConvertExtension(locale: .current, timeZone: .current)
// Build the unit and place tables now, not on the first keystroke.
for q in ["1 km in mi", "time in utc", "days until jan 1"] { _ = convert.items(for: q, global: true) }
print(ConvertExtension.ready)
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = convert.handle(line) { print(reply) }
}
