// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fastlight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Fastlight", targets: ["Fastlight"]),
        // The bundled emoji picker and calculator, extensions like any other.
        .executable(name: "fastlight-emoji", targets: ["fastlight-emoji"]),
        .executable(name: "fastlight-calc", targets: ["fastlight-calc"]),
        .executable(name: "fastlight-convert", targets: ["fastlight-convert"]),
        .executable(name: "fastlight-system", targets: ["fastlight-system"]),
        // Contacts, and Calendar + Reminders (one helper, two extensions).
        .executable(name: "fastlight-contacts", targets: ["fastlight-contacts"]),
        .executable(name: "fastlight-calendar", targets: ["fastlight-calendar"]),
        .executable(name: "fastlight-dict", targets: ["fastlight-dict"]),
        .executable(name: "fastlight-web", targets: ["fastlight-web"]),
    ],
    targets: [
        // Search providers, the fsearch client and the extension host. No
        // AppKit, so it can be tested on its own.
        // Strings in the user's language, for the app and the helpers.
        .target(name: "FastlightL10n"),
        .target(name: "FastlightCore", dependencies: ["FastlightL10n"]),
        .executableTarget(name: "Fastlight", dependencies: ["FastlightCore", "FastlightL10n"]),
        // The emoji extension's logic, apart from its stdin loop for tests.
        .target(name: "FastlightEmoji", dependencies: ["FastlightL10n"]),
        .executableTarget(name: "fastlight-emoji", dependencies: ["FastlightEmoji"]),
        // The bundled calculator: the expression parser, and its stdin loop.
        .target(name: "FastlightCalc", dependencies: ["FastlightL10n"]),
        .executableTarget(name: "fastlight-calc", dependencies: ["FastlightCalc"]),
        // Units, world clocks and date math; numbers formatted like the calculator's.
        .target(name: "FastlightConvert", dependencies: ["FastlightCalc", "FastlightL10n"]),
        .executableTarget(name: "fastlight-convert", dependencies: ["FastlightConvert"]),
        // System Settings panes, Shortcuts and system actions: three bundled
        // extensions served by one executable.
        .target(name: "FastlightSystem", dependencies: ["FastlightL10n"]),
        .executableTarget(name: "fastlight-system", dependencies: ["FastlightSystem"]),
        // Contacts, Calendar and Reminders: the logic in libraries behind a
        // store protocol (tested with fakes), the framework calls in the
        // executables. FastlightPIM is what they share: access states,
        // permission items, the background loader.
        .target(name: "FastlightPIM", dependencies: ["FastlightL10n"]),
        .target(name: "FastlightContacts", dependencies: ["FastlightPIM", "FastlightL10n"]),
        .executableTarget(name: "fastlight-contacts", dependencies: ["FastlightContacts", "FastlightPIM"]),
        .target(name: "FastlightCalendar", dependencies: ["FastlightPIM", "FastlightL10n"]),
        .executableTarget(name: "fastlight-calendar", dependencies: ["FastlightCalendar", "FastlightPIM"]),
        // The dictionary: DictionaryServices' text shaped into senses.
        .target(name: "FastlightDictionary", dependencies: ["FastlightL10n"]),
        .executableTarget(name: "fastlight-dict", dependencies: ["FastlightDictionary"]),
        // Web addresses and web search: URL detection, engines, settings.
        .target(name: "FastlightWeb", dependencies: ["FastlightL10n"]),
        .executableTarget(name: "fastlight-web", dependencies: ["FastlightWeb"]),
        .testTarget(name: "FastlightL10nTests", dependencies: ["FastlightL10n"]),
        .testTarget(name: "FastlightCoreTests", dependencies: ["FastlightCore", "FastlightL10n"]),
        .testTarget(name: "FastlightEmojiTests", dependencies: ["FastlightEmoji", "FastlightL10n"]),
        .testTarget(name: "FastlightCalcTests", dependencies: ["FastlightCalc", "FastlightL10n"]),
        .testTarget(name: "FastlightConvertTests", dependencies: ["FastlightConvert", "FastlightCalc", "FastlightL10n"]),
        .testTarget(name: "FastlightSystemTests", dependencies: ["FastlightSystem", "FastlightL10n"]),
        .testTarget(name: "FastlightContactsTests", dependencies: ["FastlightContacts", "FastlightPIM", "FastlightL10n"]),
        .testTarget(name: "FastlightCalendarTests", dependencies: ["FastlightCalendar", "FastlightPIM", "FastlightL10n"]),
        .testTarget(name: "FastlightDictionaryTests", dependencies: ["FastlightDictionary", "FastlightL10n"]),
        .testTarget(name: "FastlightWebTests", dependencies: ["FastlightWeb", "FastlightL10n"]),
    ]
)
