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
        .executable(name: "fastlight-dict", targets: ["fastlight-dict"]),
        .executable(name: "fastlight-web", targets: ["fastlight-web"]),
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
        .testTarget(name: "FastlightCoreTests", dependencies: ["FastlightCore"]),
        .testTarget(name: "FastlightEmojiTests", dependencies: ["FastlightEmoji"]),
        .testTarget(name: "FastlightCalcTests", dependencies: ["FastlightCalc"]),
        // The dictionary: DictionaryServices' text shaped into senses.
        .target(name: "FastlightDictionary"),
        .executableTarget(name: "fastlight-dict", dependencies: ["FastlightDictionary"]),
        .testTarget(name: "FastlightDictionaryTests", dependencies: ["FastlightDictionary"]),
        // Web addresses and web search: URL detection, engines, settings.
        .target(name: "FastlightWeb"),
        .executableTarget(name: "fastlight-web", dependencies: ["FastlightWeb"]),
        .testTarget(name: "FastlightWebTests", dependencies: ["FastlightWeb"]),
    ]
)
