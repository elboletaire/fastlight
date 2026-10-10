// The calculator, a Fastlight extension like any other: JSON lines on
// stdin and stdout (see docs/extensions). All math is in-process, so it
// answers well within global search's time budget.
import FastlightCalc
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let calc = CalculatorExtension(locale: .current)
print(CalculatorExtension.ready)
// EOF means Fastlight is gone (or wants us gone): exit.
while let line = readLine() {
    if let reply = calc.handle(line) { print(reply) }
}
