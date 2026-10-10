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
    ],
    targets: [
        // Search providers, the fsearch client and the extension host. No
        // AppKit, so it can be tested on its own.
        .target(name: "FastlightCore"),
        .executableTarget(name: "Fastlight", dependencies: ["FastlightCore"]),
        // The emoji extension's logic, apart from its stdin loop for tests.
        .target(name: "FastlightEmoji"),
        .executableTarget(name: "fastlight-emoji", dependencies: ["FastlightEmoji"]),
        // The bundled calculator: the expression parser, and its stdin loop.
        .target(name: "FastlightCalc"),
        .executableTarget(name: "fastlight-calc", dependencies: ["FastlightCalc"]),
        // Units, world clocks and date math; numbers formatted like the calculator's.
        .target(name: "FastlightConvert", dependencies: ["FastlightCalc"]),
        .executableTarget(name: "fastlight-convert", dependencies: ["FastlightConvert"]),
        // System Settings panes, Shortcuts and system actions: three bundled
        // extensions served by one executable.
        .target(name: "FastlightSystem"),
        .executableTarget(name: "fastlight-system", dependencies: ["FastlightSystem"]),
        // Contacts, Calendar and Reminders: the logic in libraries behind a
        // store protocol (tested with fakes), the framework calls in the
        // executables. FastlightPIM is what they share: access states,
        // permission items, the background loader.
        .target(name: "FastlightPIM"),
        .target(name: "FastlightContacts", dependencies: ["FastlightPIM"]),
        .executableTarget(name: "fastlight-contacts", dependencies: ["FastlightContacts", "FastlightPIM"]),
        .target(name: "FastlightCalendar", dependencies: ["FastlightPIM"]),
        .executableTarget(name: "fastlight-calendar", dependencies: ["FastlightCalendar", "FastlightPIM"]),
        .testTarget(name: "FastlightCoreTests", dependencies: ["FastlightCore"]),
        .testTarget(name: "FastlightEmojiTests", dependencies: ["FastlightEmoji"]),
        .testTarget(name: "FastlightCalcTests", dependencies: ["FastlightCalc"]),
        .testTarget(name: "FastlightConvertTests", dependencies: ["FastlightConvert", "FastlightCalc"]),
        .testTarget(name: "FastlightSystemTests", dependencies: ["FastlightSystem"]),
        .testTarget(name: "FastlightContactsTests", dependencies: ["FastlightContacts", "FastlightPIM"]),
        .testTarget(name: "FastlightCalendarTests", dependencies: ["FastlightCalendar", "FastlightPIM"]),
    ]
)
