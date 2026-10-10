import Foundation

/// What a unit measures. Only units of the same kind convert.
public enum Quantity: String, Sendable, CaseIterable {
    case length, mass, temperature, volume, area, speed, data, duration, energy, power, pressure, angle, fuel

    /// An SF Symbol for results.
    public var icon: String {
        switch self {
        case .length: "ruler"
        case .mass: "scalemass"
        case .temperature: "thermometer.medium"
        case .volume: "drop"
        case .area: "square.dashed"
        case .speed: "speedometer"
        case .data: "internaldrive"
        case .duration: "hourglass"
        case .energy: "bolt"
        case .power: "powerplug"
        case .pressure: "barometer"
        case .angle: "angle"
        case .fuel: "fuelpump"
        }
    }
}

/// A unit people type: its Foundation unit, how it's written back, and
/// where it converts to when no target is given.
public struct UnitInfo: Sendable {
    public let symbol: String
    /// Plural name, for the accessory: "miles".
    public let name: String
    public let quantity: Quantity
    public let unit: Dimension
    /// Targets offered with no target typed, best first ("10 km": mi).
    public let targets: [String]

    public func value(_ v: Double, in other: UnitInfo) -> Double {
        other.unit.converter.value(fromBaseUnitValue: unit.converter.baseUnitValue(fromValue: v))
    }
}

/// The units the converter knows, by every name they're typed with.
///
/// Foundation's own units are used where their factors are exact; some of
/// its customary ones are rounded to six digits (a pound is 0.453592 kg),
/// so those are redefined with the exact factor.
public enum UnitTable {
    static func linear(_ c: Double) -> UnitConverterLinear { UnitConverterLinear(coefficient: c) }

    // (symbol, plural name, unit, aliases, default targets). Aliases are
    // folded (lowercase, no diacritics); the symbol and name are added.
    private typealias Row = (String, String, Dimension, [String], [String])

    private static let rows: [(Quantity, [Row])] = [
        (.length, [
            ("km", "kilometers", UnitLength.kilometers, ["kilometre", "kilometres", "kilometer", "kms"], ["mi", "m", "ft"]),
            ("m", "meters", UnitLength.meters, ["meter", "metre", "metres", "mtr"], ["ft", "yd", "in", "cm"]),
            ("cm", "centimeters", UnitLength.centimeters, ["centimeter", "centimetre", "centimetres"], ["in", "mm", "ft"]),
            ("mm", "millimeters", UnitLength.millimeters, ["millimeter", "millimetre", "millimetres"], ["in", "cm"]),
            ("µm", "micrometers", UnitLength.micrometers, ["um", "micrometer", "micrometre", "micrometres", "micron", "microns"], ["mm", "in"]),
            ("nm", "nanometers", UnitLength.nanometers, ["nanometer", "nanometre", "nanometres"], ["µm", "m"]),
            ("pm", "picometers", UnitLength.picometers, ["picometer", "picometre", "picometres"], ["nm"]),
            ("mi", "miles", UnitLength.miles, ["mile"], ["km", "m", "ft"]),
            ("yd", "yards", UnitLength.yards, ["yard", "yds"], ["m", "ft"]),
            ("ft", "feet", UnitLength.feet, ["foot", "'", "′"], ["m", "cm", "in"]),
            ("in", "inches", UnitLength.inches, ["inch", "\"", "″"], ["cm", "mm", "ft"]),
            ("nmi", "nautical miles", UnitLength.nauticalMiles, ["nautical mile"], ["km", "mi"]),
            ("ly", "light-years", UnitLength.lightyears, ["light year", "light years", "light-year", "lightyear", "lightyears"], ["km", "au"]),
            ("au", "astronomical units", UnitLength.astronomicalUnits, ["astronomical unit"], ["km", "mi"]),
        ]),
        (.mass, [
            ("kg", "kilograms", UnitMass.kilograms, ["kilogram", "kilo", "kilos", "kgs"], ["lb", "g"]),
            ("g", "grams", UnitMass.grams, ["gram", "gr", "gramme", "grammes"], ["oz", "mg"]),
            ("mg", "milligrams", UnitMass.milligrams, ["milligram"], ["g", "oz"]),
            ("µg", "micrograms", UnitMass.micrograms, ["ug", "mcg", "microgram"], ["mg"]),
            ("t", "metric tons", UnitMass.metricTons, ["tonne", "tonnes", "metric ton", "metric tons"], ["ton", "kg", "lb"]),
            ("lb", "pounds", UnitMass(symbol: "lb", converter: linear(0.453_592_37)), ["lbs", "pound", "#"], ["kg", "g"]),
            ("oz", "ounces", UnitMass(symbol: "oz", converter: linear(0.028_349_523_125)), ["ounce"], ["g", "lb"]),
            ("st", "stone", UnitMass(symbol: "st", converter: linear(6.350_293_18)), ["stone", "stones"], ["kg", "lb"]),
            ("ton", "short tons", UnitMass(symbol: "ton", converter: linear(907.184_74)), ["tons", "short ton", "short tons"], ["t", "kg"]),
        ]),
        (.temperature, [
            ("°C", "degrees Celsius", UnitTemperature.celsius, ["c", "celsius", "centigrade", "degc", "degrees celsius", "degree celsius", "ºc"], ["°F", "K"]),
            ("°F", "degrees Fahrenheit", UnitTemperature.fahrenheit, ["f", "fahrenheit", "degf", "degrees fahrenheit", "degree fahrenheit", "ºf"], ["°C", "K"]),
            ("K", "kelvin", UnitTemperature.kelvin, ["k", "kelvins", "degrees kelvin"], ["°C", "°F"]),
        ]),
        (.volume, [
            ("L", "liters", UnitVolume.liters, ["l", "liter", "litre", "litres", "ltr"], ["gal", "qt", "ml"]),
            ("ml", "milliliters", UnitVolume.milliliters, ["milliliter", "millilitre", "millilitres", "mls"], ["fl oz", "tsp", "cup"]),
            ("cl", "centiliters", UnitVolume.centiliters, ["centiliter", "centilitre", "centilitres"], ["ml", "fl oz"]),
            ("dl", "deciliters", UnitVolume.deciliters, ["deciliter", "decilitre", "decilitres"], ["ml", "cup"]),
            ("m³", "cubic meters", UnitVolume.cubicMeters, ["m3", "cubic meter", "cubic metre", "cubic metres", "cu m"], ["L", "ft³"]),
            ("cm³", "cubic centimeters", UnitVolume.cubicCentimeters, ["cm3", "cc", "cubic centimeter", "cubic centimetre", "cubic centimetres"], ["ml", "in³"]),
            ("ft³", "cubic feet", UnitVolume(symbol: "ft³", converter: linear(28.316_846_592)), ["ft3", "cubic foot", "cubic feet", "cu ft"], ["m³", "L"]),
            ("in³", "cubic inches", UnitVolume(symbol: "in³", converter: linear(0.016_387_064)), ["in3", "cubic inch", "cubic inches", "cu in"], ["cm³", "ml"]),
            // US customary, exactly.
            ("gal", "gallons", UnitVolume(symbol: "gal", converter: linear(3.785_411_784)), ["gallon", "gallons", "us gal", "us gallon", "us gallons"], ["L", "qt"]),
            ("qt", "quarts", UnitVolume(symbol: "qt", converter: linear(0.946_352_946)), ["quart", "quarts"], ["L", "pt"]),
            ("pt", "pints", UnitVolume(symbol: "pt", converter: linear(0.473_176_473)), ["pint", "pints"], ["ml", "L", "cup"]),
            ("cup", "cups", UnitVolume(symbol: "cup", converter: linear(0.236_588_236_5)), ["cups"], ["ml", "fl oz", "tbsp"]),
            ("fl oz", "fluid ounces", UnitVolume(symbol: "fl oz", converter: linear(0.029_573_529_562_5)), ["floz", "fl. oz", "fl.oz", "fluid ounce", "fluid ounces"], ["ml", "cup"]),
            ("tbsp", "tablespoons", UnitVolume(symbol: "tbsp", converter: linear(0.014_786_764_781_25)), ["tablespoon", "tablespoons", "tbs", "tbl"], ["ml", "tsp"]),
            ("tsp", "teaspoons", UnitVolume(symbol: "tsp", converter: linear(0.004_928_921_593_75)), ["teaspoon", "teaspoons"], ["ml", "tbsp"]),
            ("imp gal", "imperial gallons", UnitVolume.imperialGallons, ["imperial gallon", "imperial gallons", "uk gallon", "uk gallons", "uk gal"], ["L", "gal"]),
            ("imp pt", "imperial pints", UnitVolume(symbol: "imp pt", converter: linear(0.568_261_25)), ["imperial pint", "imperial pints", "uk pint", "uk pints", "uk pt"], ["ml", "pt"]),
        ]),
        (.area, [
            ("m²", "square meters", UnitArea.squareMeters, ["m2", "sqm", "sq m", "square meter", "square metre", "square metres"], ["ft²", "yd²"]),
            ("km²", "square kilometers", UnitArea.squareKilometers, ["km2", "sq km", "square kilometer", "square kilometre", "square kilometres"], ["mi²", "ha"]),
            ("cm²", "square centimeters", UnitArea.squareCentimeters, ["cm2", "sq cm", "square centimeter", "square centimetre", "square centimetres"], ["in²"]),
            ("mm²", "square millimeters", UnitArea.squareMillimeters, ["mm2", "sq mm", "square millimeter", "square millimetre", "square millimetres"], ["in²", "cm²"]),
            ("ha", "hectares", UnitArea.hectares, ["hectare", "hectares"], ["acre", "m²"]),
            ("acre", "acres", UnitArea.acres, ["acres", "ac"], ["m²", "ha", "ft²"]),
            ("ft²", "square feet", UnitArea.squareFeet, ["ft2", "sq ft", "sqft", "square foot", "square feet"], ["m²"]),
            ("in²", "square inches", UnitArea.squareInches, ["in2", "sq in", "square inch", "square inches"], ["cm²"]),
            ("yd²", "square yards", UnitArea(symbol: "yd²", converter: linear(0.836_127_36)), ["yd2", "sq yd", "square yard", "square yards"], ["m²"]),
            ("mi²", "square miles", UnitArea.squareMiles, ["mi2", "sq mi", "square mile", "square miles"], ["km²", "acre"]),
        ]),
        (.speed, [
            ("km/h", "kilometers per hour", UnitSpeed(symbol: "km/h", converter: linear(1 / 3.6)), ["kmh", "kph", "km per hour", "kilometers per hour", "kilometres per hour", "km/hr"], ["mph", "m/s"]),
            ("mph", "miles per hour", UnitSpeed.milesPerHour, ["mi/h", "miles per hour", "mile per hour"], ["km/h", "m/s"]),
            ("m/s", "meters per second", UnitSpeed.metersPerSecond, ["meters per second", "metres per second", "mps"], ["km/h", "mph"]),
            ("ft/s", "feet per second", UnitSpeed(symbol: "ft/s", converter: linear(0.3048)), ["feet per second"], ["m/s", "mph"]),
            ("kn", "knots", UnitSpeed(symbol: "kn", converter: linear(1852.0 / 3600)), ["knot", "knots", "kt", "kts"], ["km/h", "mph"]),
        ]),
        (.data, [
            ("bit", "bits", UnitInformationStorage.bits, ["bits"], ["B"]),
            ("B", "bytes", UnitInformationStorage.bytes, ["byte", "bytes", "b"], ["KB", "bit"]),
            ("KB", "kilobytes", UnitInformationStorage.kilobytes, ["kb", "kilobyte", "kilobytes", "kbyte"], ["KiB", "B"]),
            ("MB", "megabytes", UnitInformationStorage.megabytes, ["mb", "megabyte", "megabytes", "mbyte"], ["MiB", "KB"]),
            ("GB", "gigabytes", UnitInformationStorage.gigabytes, ["gb", "gigabyte", "gigabytes", "gig", "gigs"], ["GiB", "MB"]),
            ("TB", "terabytes", UnitInformationStorage.terabytes, ["tb", "terabyte", "terabytes"], ["TiB", "GB"]),
            ("PB", "petabytes", UnitInformationStorage.petabytes, ["pb", "petabyte", "petabytes"], ["PiB", "TB"]),
            ("KiB", "kibibytes", UnitInformationStorage.kibibytes, ["kib", "kibibyte", "kibibytes"], ["KB", "B"]),
            ("MiB", "mebibytes", UnitInformationStorage.mebibytes, ["mib", "mebibyte", "mebibytes"], ["MB", "KiB"]),
            ("GiB", "gibibytes", UnitInformationStorage.gibibytes, ["gib", "gibibyte", "gibibytes"], ["GB", "MiB"]),
            ("TiB", "tebibytes", UnitInformationStorage.tebibytes, ["tib", "tebibyte", "tebibytes"], ["TB", "GiB"]),
            ("PiB", "pebibytes", UnitInformationStorage.pebibytes, ["pib", "pebibyte", "pebibytes"], ["PB", "TiB"]),
            ("kbit", "kilobits", UnitInformationStorage.kilobits, ["kilobit", "kilobits", "kbits"], ["KB", "bit"]),
            ("Mbit", "megabits", UnitInformationStorage.megabits, ["mbit", "megabit", "megabits", "mbits"], ["MB", "kbit"]),
            ("Gbit", "gigabits", UnitInformationStorage.gigabits, ["gbit", "gigabit", "gigabits", "gbits"], ["GB", "Mbit"]),
        ]),
        (.duration, [
            ("ns", "nanoseconds", UnitDuration.nanoseconds, ["nanosecond", "nanoseconds"], ["µs", "ms"]),
            ("µs", "microseconds", UnitDuration.microseconds, ["us", "microsecond", "microseconds"], ["ms", "ns"]),
            ("ms", "milliseconds", UnitDuration.milliseconds, ["millisecond", "milliseconds", "msec"], ["s", "µs"]),
            ("s", "seconds", UnitDuration.seconds, ["sec", "secs", "second", "seconds"], ["min", "ms", "h"]),
            ("min", "minutes", UnitDuration.minutes, ["mins", "minute", "minutes"], ["h", "s"]),
            ("h", "hours", UnitDuration.hours, ["hr", "hrs", "hour", "hours"], ["min", "d", "s"]),
            ("d", "days", UnitDuration(symbol: "d", converter: linear(86_400)), ["day", "days"], ["h", "wk", "min"]),
            ("wk", "weeks", UnitDuration(symbol: "wk", converter: linear(604_800)), ["week", "weeks", "wks"], ["d", "h"]),
            // Average Gregorian month and year.
            ("mo", "months", UnitDuration(symbol: "mo", converter: linear(2_629_746)), ["month", "months"], ["d", "wk"]),
            ("yr", "years", UnitDuration(symbol: "yr", converter: linear(31_556_952)), ["year", "years", "yrs", "y"], ["d", "mo", "h"]),
        ]),
        (.energy, [
            ("J", "joules", UnitEnergy.joules, ["j", "joule", "joules"], ["cal", "kJ"]),
            ("kJ", "kilojoules", UnitEnergy.kilojoules, ["kj", "kilojoule", "kilojoules"], ["kcal", "J"]),
            ("cal", "calories", UnitEnergy.calories, ["calorie", "calories"], ["J", "kcal"]),
            ("kcal", "kilocalories", UnitEnergy.kilocalories, ["kilocalorie", "kilocalories", "kcals"], ["kJ", "cal"]),
            ("Wh", "watt-hours", UnitEnergy(symbol: "Wh", converter: linear(3600)), ["wh", "watt hour", "watt hours", "watt-hour", "watt-hours"], ["kWh", "J"]),
            ("kWh", "kilowatt-hours", UnitEnergy.kilowattHours, ["kwh", "kilowatt hour", "kilowatt hours", "kilowatt-hour", "kilowatt-hours"], ["MJ", "kcal"]),
            ("MJ", "megajoules", UnitEnergy(symbol: "MJ", converter: linear(1e6)), ["mj", "megajoule", "megajoules"], ["kWh", "kcal"]),
            ("BTU", "British thermal units", UnitEnergy(symbol: "BTU", converter: linear(1055.055_852_62)), ["btu", "btus"], ["kJ", "kWh"]),
            ("eV", "electronvolts", UnitEnergy(symbol: "eV", converter: linear(1.602_176_634e-19)), ["ev", "electronvolt", "electronvolts", "electron volt", "electron volts"], ["J"]),
        ]),
        (.power, [
            ("W", "watts", UnitPower.watts, ["w", "watt", "watts"], ["kW", "hp"]),
            ("kW", "kilowatts", UnitPower.kilowatts, ["kw", "kilowatt", "kilowatts"], ["hp", "W"]),
            ("MW", "megawatts", UnitPower.megawatts, ["mw", "megawatt", "megawatts"], ["kW", "hp"]),
            // Mechanical horsepower.
            ("hp", "horsepower", UnitPower(symbol: "hp", converter: linear(745.699_871_582_270_22)), ["horsepower", "bhp"], ["kW", "W"]),
        ]),
        (.pressure, [
            ("Pa", "pascals", UnitPressure.newtonsPerMetersSquared, ["pa", "pascal", "pascals"], ["kPa", "psi"]),
            ("hPa", "hectopascals", UnitPressure.hectopascals, ["hpa", "hectopascal", "hectopascals"], ["inHg", "mmHg"]),
            ("kPa", "kilopascals", UnitPressure.kilopascals, ["kpa", "kilopascal", "kilopascals"], ["psi", "bar"]),
            ("MPa", "megapascals", UnitPressure.megapascals, ["mpa", "megapascal", "megapascals"], ["psi", "bar"]),
            ("bar", "bar", UnitPressure.bars, ["bars"], ["psi", "kPa"]),
            ("mbar", "millibars", UnitPressure.millibars, ["millibar", "millibars", "mb"], ["hPa", "inHg"]),
            ("psi", "pounds per square inch", UnitPressure(symbol: "psi", converter: linear(6894.757_293_168)), ["pounds per square inch"], ["bar", "kPa"]),
            ("atm", "atmospheres", UnitPressure(symbol: "atm", converter: linear(101_325)), ["atmosphere", "atmospheres"], ["bar", "kPa", "psi"]),
            ("mmHg", "millimeters of mercury", UnitPressure(symbol: "mmHg", converter: linear(133.322_387_415)), ["mmhg", "torr"], ["kPa", "inHg"]),
            ("inHg", "inches of mercury", UnitPressure(symbol: "inHg", converter: linear(3386.389)), ["inhg"], ["hPa", "mmHg"]),
        ]),
        (.angle, [
            ("°", "degrees", UnitAngle.degrees, ["deg", "degree", "degrees", "º"], ["rad", "turn"]),
            ("rad", "radians", UnitAngle(symbol: "rad", converter: linear(180 / .pi)), ["radian", "radians", "rads"], ["°"]),
            ("grad", "gradians", UnitAngle(symbol: "grad", converter: linear(0.9)), ["gradian", "gradians", "gon"], ["°"]),
            ("turn", "turns", UnitAngle(symbol: "turn", converter: linear(360)), ["turns", "rev", "revs", "revolution", "revolutions"], ["°", "rad"]),
            ("arcmin", "arcminutes", UnitAngle(symbol: "arcmin", converter: linear(1.0 / 60)), ["arcminute", "arcminutes"], ["°", "arcsec"]),
            ("arcsec", "arcseconds", UnitAngle(symbol: "arcsec", converter: linear(1.0 / 3600)), ["arcsecond", "arcseconds"], ["°", "arcmin"]),
        ]),
        (.fuel, [
            // Foundation's mpg rounds 235.2146 to 235.215.
            ("mpg", "miles per gallon", UnitFuelEfficiency(symbol: "mpg", converter: ReciprocalConverter(235.214_583_333_333_3)),
             ["miles per gallon", "us mpg"], ["L/100km", "km/L"]),
            ("L/100km", "liters per 100 km", UnitFuelEfficiency.litersPer100Kilometers,
             ["l/100km", "l/100 km", "liters per 100 km", "litres per 100 km", "l per 100 km", "l per 100km"], ["mpg", "km/L"]),
            // Foundation has no km/L; it's the reciprocal of L/100km, times 100.
            ("km/L", "kilometers per liter", UnitFuelEfficiency(symbol: "km/L", converter: ReciprocalConverter(100)),
             ["km/l", "kmpl", "kilometers per liter", "kilometres per litre"], ["L/100km", "mpg"]),
        ]),
    ]

    /// Every unit by symbol.
    public static let bySymbol: [String: UnitInfo] = {
        var out: [String: UnitInfo] = [:]
        for (q, list) in rows {
            for r in list {
                out[r.0] = UnitInfo(symbol: r.0, name: r.1, quantity: q, unit: r.2, targets: r.4)
            }
        }
        return out
    }()

    /// Folded alias to symbol. Case matters for no alias (`Mb` is a
    /// megabyte, as most people mean it); bits are spelled out.
    public static let byAlias: [String: String] = {
        var out: [String: String] = [:]
        for (a, s) in aliases where out[a] == nil { out[a] = s }
        return out
    }()

    /// Every (alias, symbol), in table order: the first one wins a clash.
    static var aliases: [(String, String)] {
        // "mb" is a megabyte, not a millibar.
        var out = [("mb", "MB")]
        for (_, list) in rows {
            for r in list {
                out += ([r.0, r.1] + r.3).map { (Text.fold($0), r.0) }
            }
        }
        return out
    }

    /// The longest alias, in words, so the parser knows how far to look.
    static let maxAliasWords = byAlias.keys.map { $0.split(separator: " ").count }.max() ?? 1

    /// Aliases too ambiguous to answer on their own in normal search: "3 in",
    /// "5 m", "12 pt", "1 hp". With a target ("5 m in ft") they're fine.
    static let ambiguousAlone: Set<String> = [
        "in", "\"", "″", "'", "′", "pm", "nm", "ms", "us", "ns", "hp", "st", "pt", "qt", "au", "ly", "cal", "bit", "bits",
        "bar", "bars", "atm", "rad", "rads", "deg", "grad", "gon", "rev", "revs", "turn", "turns", "degree", "degrees",
        "°", "º", "kn", "kt", "kts", "pa", "ev", "mo", "gr", "gig", "gigs", "ton", "tons", "cc", "ac", "mw", "mpa",
        "mps", "tbl", "#", "kilo", "kilos", "stone", "stones", "pound", "pounds",
    ]

    /// Whether "<number> <alias>" alone is clearly a conversion.
    static func answersAlone(_ alias: String, _ info: UnitInfo) -> Bool {
        info.quantity != .duration && alias.count >= 2 && !ambiguousAlone.contains(alias)
    }
}

/// Fuel efficiency's base unit is L/100km; distance per volume is its
/// reciprocal, times `k`.
final class ReciprocalConverter: UnitConverter, @unchecked Sendable {
    let k: Double
    init(_ k: Double) {
        self.k = k
        super.init()
    }

    override func baseUnitValue(fromValue value: Double) -> Double { k / value }
    override func value(fromBaseUnitValue baseUnitValue: Double) -> Double { k / baseUnitValue }
}

/// "10 km", "3 ft 4 in": an amount in one kind of unit.
public struct Amount: Sendable {
    public var terms: [(value: Double, unit: UnitInfo)]
    public var quantity: Quantity { terms[0].unit.quantity }

    /// The whole amount in the last term's unit: 3 ft 4 in is 40 in.
    public var value: Double {
        let last = terms[terms.count - 1].unit
        return terms.reduce(0) { $0 + $1.unit.value($1.value, in: last) }
    }

    public var unit: UnitInfo { terms[terms.count - 1].unit }
}

/// A parsed conversion: what to convert, and to what (nil: the usual).
public struct UnitQuery: Sendable {
    public var amount: Amount
    public var target: UnitInfo?
    /// Normal search may answer it: there's a target, or the unit alone is
    /// unmistakable ("10 km", not "3 in").
    public var clear: Bool
}

public enum UnitParser {
    static let separators: Set<String> = ["in", "to", "into", "as", "=", "->", "→", ">"]

    /// "10 km in mi", "10km to miles", "72f in c", "100 °F", "3 ft 4 in in cm",
    /// "how many ml in 2 cups". Nil unless the whole query is a conversion.
    public static func parse(_ query: String, decimal: Character = ".") -> UnitQuery? {
        let words = Text.words(query, decimal: decimal)
        guard !words.isEmpty else { return nil }
        // "how many ml in 2 cups", "how many feet in a mile".
        if words.count >= 5, words[0] == "how", words[1] == "many" {
            var rest = Array(words.dropFirst(2))
            guard let (target, used) = unit(at: 0, in: rest), used < rest.count, rest[used] == "in" else { return nil }
            rest.removeFirst(used + 1)
            if rest.first == "a" || rest.first == "an" || rest.first == "one" { rest[0] = "1" }
            guard let (amount, n) = amount(rest, decimal: decimal), n == rest.count,
                  amount.quantity == target.1.quantity else { return nil }
            return UnitQuery(amount: amount, target: target.1, clear: true)
        }
        guard let (amount, used) = amount(words, decimal: decimal) else { return nil }
        var i = used
        if i == words.count {
            let alias = words[used - 1]
            let clear = amount.terms.count > 1 || UnitTable.answersAlone(alias, amount.unit)
            return UnitQuery(amount: amount, target: nil, clear: clear)
        }
        // "in" doubles as inches: "3 in in cm" got here with the first one
        // taken as the unit.
        if separators.contains(words[i]) { i += 1 }
        guard i < words.count, let (target, n) = unit(at: i, in: words), i + n == words.count,
              target.1.quantity == amount.quantity else { return nil }
        return UnitQuery(amount: amount, target: target.1, clear: true)
    }

    /// Number-unit pairs from the start; at least one.
    static func amount(_ words: [String], decimal: Character) -> (Amount, Int)? {
        var terms: [(Double, UnitInfo)] = []
        var i = 0
        while i < words.count, let v = Text.number(words[i], decimal: decimal) {
            guard let (u, n) = unit(at: i + 1, in: words) else { break }
            if let q = terms.first?.1.quantity, q != u.1.quantity || [.temperature, .fuel].contains(q) { break }
            // Each unit once, largest first: "3 ft 4 in", not "4 in 3 ft".
            if let prev = terms.last?.1, u.1.value(1, in: prev) >= 1 { break }
            terms.append((v, u.1))
            i += 1 + n
        }
        guard !terms.isEmpty else { return nil }
        return (Amount(terms: terms), i)
    }

    /// The longest alias starting at `i`: ((alias, unit), words used).
    static func unit(at i: Int, in words: [String]) -> ((String, UnitInfo), Int)? {
        guard i < words.count else { return nil }
        for n in stride(from: min(UnitTable.maxAliasWords, words.count - i), through: 1, by: -1) {
            let phrase = words[i..<(i + n)].joined(separator: " ")
            if let s = UnitTable.byAlias[phrase], let u = UnitTable.bySymbol[s] { return ((phrase, u), n) }
        }
        return nil
    }
}
