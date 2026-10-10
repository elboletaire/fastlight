import Foundation
import Testing
@testable import FastlightConvert

/// The converted value of "<amount> in <target>".
func converted(_ q: String, decimal: Character = ".") throws -> Double {
    let u = try #require(UnitParser.parse(q, decimal: decimal), "\(q)")
    let t = try #require(u.target, "\(q)")
    return u.amount.unit.value(u.amount.value, in: t)
}

func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance * max(1, abs(b))
}

@Suite struct UnitTableTests {
    @Test func everyTargetExistsAndMatches() {
        for (symbol, u) in UnitTable.bySymbol {
            #expect(!u.targets.isEmpty, "\(symbol)")
            for t in u.targets {
                let target = UnitTable.bySymbol[t]
                #expect(target?.quantity == u.quantity, "\(symbol) → \(t)")
                #expect(t != symbol)
            }
        }
    }

    @Test func clashesAreDeliberate() {
        var owners: [String: Set<String>] = [:]
        for (a, s) in UnitTable.aliases { owners[a, default: []].insert(s) }
        let clashes = owners.filter { $0.value.count > 1 }.keys.sorted()
        // "mb" is MB, not mbar.
        #expect(clashes == ["mb"])
        #expect(UnitTable.byAlias["mb"] == "MB")
    }

    @Test func aliasesResolve() {
        let expected: [String: String] = [
            "c": "°C", "°c": "°C", "celsius": "°C", "f": "°F", "°f": "°F", "k": "K", "km": "km", "kilometres": "km",
            "mi": "mi", "miles": "mi", "in": "in", "inches": "in", "\"": "in", "'": "ft", "feet": "ft", "lbs": "lb",
            "gb": "GB", "gib": "GiB", "b": "B", "bit": "bit", "mbit": "Mbit", "m2": "m²", "sq ft": "ft²", "m/s": "m/s",
            "kmh": "km/h", "kph": "km/h", "l": "L", "fl oz": "fl oz", "cups": "cup", "tbsp": "tbsp", "acres": "acre",
            "ha": "ha", "min": "min", "h": "h", "hrs": "h", "days": "d", "ms": "ms", "us": "µs", "µs": "µs", "kwh": "kWh",
            "kcal": "kcal", "psi": "psi", "atm": "atm", "deg": "°", "rad": "rad", "mpg": "mpg", "l/100km": "L/100km",
            "um": "µm", "µm": "µm", "nm": "nm", "nmi": "nmi", "t": "t", "tonnes": "t", "tons": "ton", "pt": "pt",
            "hp": "hp", "w": "W", "kw": "kW", "hpa": "hPa", "mmhg": "mmHg", "light years": "ly",
        ]
        for (a, s) in expected { #expect(UnitTable.byAlias[a] == s, "\(a)") }
    }
}

@Suite struct UnitParserTests {
    @Test func parsesSpotlightStyleQueries() throws {
        #expect(close(try converted("10 km in mi"), 6.213_711_922_373_34))
        #expect(close(try converted("10km to miles"), 6.213_711_922_373_34))
        #expect(close(try converted("10 kilometers into miles"), 6.213_711_922_373_34))
        #expect(close(try converted("10 km = mi"), 6.213_711_922_373_34))
        #expect(close(try converted("10 km -> mi"), 6.213_711_922_373_34))
        #expect(close(try converted("10 km → mi"), 6.213_711_922_373_34))
        #expect(close(try converted("10 KM IN MI"), 6.213_711_922_373_34))
        #expect(close(try converted("10 km in mi?"), 6.213_711_922_373_34))
        #expect(close(try converted("10 km mi"), 6.213_711_922_373_34)) // no separator
        #expect(close(try converted("72f in c"), 22.222_222_222_222))
        #expect(close(try converted("72 °F to °C"), 22.222_222_222_222))
        #expect(close(try converted("72°F in celsius"), 22.222_222_222_222))
        #expect(close(try converted("100° F in C"), 37.777_777_777_777))
        #expect(close(try converted("-40 c in f"), -40))
        #expect(close(try converted("0 k in c"), -273.15))
        #expect(try converted("5 gb in mb") == 5000)
        #expect(try converted("1 GiB in MiB") == 1024)
        #expect(try converted("1 gib in bytes") == 1_073_741_824)
        #expect(try converted("8 bits in bytes") == 1)
        #expect(try converted("100 mbit in mb") == 12.5)
        #expect(close(try converted("3 ft 4 in in cm"), 101.6))
        #expect(close(try converted("5'11\" in cm"), 180.34))
        #expect(close(try converted("1 h 30 min in min"), 90))
        #expect(close(try converted("60 mph in km/h"), 96.560_64))
        #expect(close(try converted("100 km/h in mph"), 62.137_119_223_733_4))
        #expect(close(try converted("10 m/s to kph"), 36))
        #expect(close(try converted("2 cups in ml"), 473.176_473))
        #expect(close(try converted("1 tbsp in tsp"), 3))
        #expect(close(try converted("1 gal in l"), 3.785_411_784))
        #expect(close(try converted("1 imperial gallon in l"), 4.546_09))
        #expect(close(try converted("1 acre in m2"), 4046.856_422_4))
        #expect(close(try converted("1 acre in m²"), 4046.856_422_4))
        #expect(close(try converted("1 sq mi in acres"), 640))
        #expect(close(try converted("1 ha in m2"), 10_000))
        #expect(close(try converted("1 lb in kg"), 0.453_592_37))
        #expect(close(try converted("16 oz in lb"), 1))
        #expect(close(try converted("1 st in lb"), 14))
        #expect(close(try converted("1 kcal in kJ"), 4.184))
        #expect(close(try converted("1 kwh in mj"), 3.6))
        #expect(close(try converted("1 atm in psi"), 14.695_948_8, 1e-8))
        #expect(close(try converted("1 bar in kpa"), 100))
        #expect(close(try converted("180 deg in rad"), .pi))
        #expect(close(try converted("1 turn in degrees"), 360))
        #expect(close(try converted("60 arcmin in deg"), 1))
        #expect(close(try converted("1 hp in kw"), 0.745_699_871_582_270_22))
        #expect(close(try converted("30 mpg in l/100km"), 7.840_486_111, 1e-9))
        #expect(close(try converted("5 l/100km in km/l"), 20))
        #expect(close(try converted("1 day in hours"), 24))
        #expect(close(try converted("2 weeks in days"), 14))
        #expect(close(try converted("1 ly in km"), 9.460_730_472_580_8e12))
        #expect(close(try converted("1/2 cup in ml"), 118.294_118_25))
    }

    @Test func howManyQuestions() throws {
        #expect(close(try converted("how many ml in 2 cups"), 473.176_473))
        #expect(close(try converted("how many feet in a mile"), 5280))
        #expect(close(try converted("How many grams in an ounce?"), 28.349_523_125))
        #expect(UnitParser.parse("how many feet in a liter") == nil)
    }

    @Test func numbersFollowTheLocale() throws {
        #expect(close(try converted("1,5 km in m", decimal: ","), 1500))
        #expect(close(try converted("1.5 km in m", decimal: ","), 1500))
        #expect(close(try converted("1.000,5 m in km", decimal: ","), 1.0005))
        #expect(close(try converted("1,000 m in km"), 1))
        #expect(close(try converted("1.5 km in m"), 1500))
        #expect(close(try converted(".5 km in m"), 500))
        #expect(UnitParser.parse("1,00 m in km") == nil) // not grouping
    }

    @Test func noTargetOffersTheUsual() throws {
        let u = try #require(UnitParser.parse("10 km"))
        #expect(u.target == nil)
        #expect(u.amount.unit.targets.first == "mi")
        #expect(UnitParser.parse("100 °F")?.amount.unit.targets.first == "°C")
        #expect(UnitParser.parse("5 kg")?.amount.unit.targets.first == "lb")
    }

    @Test func refusesWhatIsntAConversion() {
        for q in ["", "km", "10", "10 km in kg", "10 km in", "10 km to the moon", "in km", "10 apples",
                  "3 ft 4 c", "4 in 3 ft", "10 c 5 f", "time machine", "ms word", "1 2 km", "10 km in mi please",
                  "1/0 km", "abc km in mi"] {
            #expect(UnitParser.parse(q) == nil, "\(q)")
        }
    }

    @Test func clearOnlyWhenUnmistakable() {
        // Global search answers these on their own…
        for q in ["10 km", "100 °F", "72°f", "5 gb", "2 cups", "1 acre", "60 mph", "3 ft", "5 kg", "3 ft 4 in",
                  "1 gallon", "250 ml", "30 mpg"] {
            #expect(UnitParser.parse(q)?.clear == true, "\(q)")
        }
        // …but not these, which need a target ("3 in in cm").
        for q in ["3 in", "5 m", "12 pt", "1 hp", "2 l", "3 days", "10 min", "8 bit", "72f", "90°", "90 degrees",
                  "1 ton", "5 pounds", "3 st", "100 c", "1 h"] {
            #expect(UnitParser.parse(q)?.clear == false, "\(q)")
        }
        #expect(UnitParser.parse("3 in in cm")?.clear == true)
    }
}

extension UnitQuery: Equatable {
    public static func == (a: UnitQuery, b: UnitQuery) -> Bool {
        a.amount.value == b.amount.value && a.amount.unit.symbol == b.amount.unit.symbol
            && a.target?.symbol == b.target?.symbol && a.clear == b.clear
    }
}

@Suite struct TextTests {
    @Test func splitsNumbersFromUnits() {
        #expect(Text.words("10km to Miles") == ["10", "km", "to", "miles"])
        #expect(Text.words("72°F") == ["72", "°f"])
        #expect(Text.words("100° F") == ["100", "°f"])
        #expect(Text.words("5'11\"") == ["5", "'", "11", "\""])
        #expect(Text.words("10km=mi") == ["10", "km", "=", "mi"])
        #expect(Text.words("10 km->mi") == ["10", "km", "->", "mi"])
        #expect(Text.words("1 m² in ft²") == ["1", "m2", "in", "ft2"])
        #expect(Text.words("−5 °C") == ["-5", "°c"])
        #expect(Text.words("5 μm") == ["5", "µm"])
    }

    @Test func numbers() {
        #expect(Text.number("10") == 10)
        #expect(Text.number("-3.5") == -3.5)
        #expect(Text.number("1,000,000") == 1_000_000)
        #expect(Text.number("1,5", decimal: ",") == 1.5)
        #expect(Text.number("1/4") == 0.25)
        #expect(Text.number("1/0") == nil)
        #expect(Text.number("1,5") == nil)
        #expect(Text.number("1.2.3") == nil)
        #expect(Text.number("km") == nil)
    }

    /// Where "," is the decimal separator, "1.000" is a thousand, as
    /// "1.000,5" already was a thousand and a half; it used to read as 1,
    /// three orders of magnitude off. Where "." is, "1.000,5" is nothing,
    /// not 1.0005.
    @Test func dotsGroupWhereCommaIsDecimal() throws {
        #expect(Text.number("1.000", decimal: ",") == 1000)
        #expect(Text.number("12.345.678", decimal: ",") == 12_345_678)
        #expect(Text.number("1.000,5", decimal: ",") == 1000.5)
        #expect(Text.number("-1.000", decimal: ",") == -1000)
        #expect(Text.number("1.5", decimal: ",") == 1.5)
        #expect(Text.number("0.125", decimal: ",") == 0.125)
        #expect(Text.number("1234.5", decimal: ",") == 1234.5)
        #expect(Text.number("1.00,5", decimal: ",") == nil)
        #expect(Text.number("1,000.5") == 1000.5)
        #expect(Text.number("1.000") == 1)
        #expect(Text.number("1.000,5") == nil)
        #expect(Text.number("1.5,3") == nil)
        #expect(try converted("1.000 m in km", decimal: ",") == 1)
        #expect(UnitParser.parse("1.000,5 m in cm") == nil)
    }
}

@Suite struct ReciprocalTests {
    @Test func zeroIsNotDividedBy() {
        let c = ReciprocalConverter(100)
        #expect(c.baseUnitValue(fromValue: 0).isNaN)
        #expect(c.value(fromBaseUnitValue: 0).isNaN)
        #expect(c.baseUnitValue(fromValue: 4) == 25)
        #expect(UnitParser.parse("0 mpg") == nil)
        #expect(UnitParser.parse("how many mpg in 0 l/100km") == nil)
    }
}

@Suite struct AbsoluteZeroTests {
    @Test func nothingIsColderThanAbsoluteZero() throws {
        for q in ["-300 c in k", "-274 c", "-460 f in c", "-1 k in c", "-0.01 k"] {
            #expect(UnitParser.parse(q) == nil, "\(q)")
        }
        #expect(abs(try converted("-273.15 c in k")) < 1e-9)
        #expect(abs(try converted("-459.67 f in k")) < 1e-9)
        #expect(try converted("0 k in c") == -273.15)
        #expect(close(try converted("-40 c in f"), -40))
    }
}
