// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fastlight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Fastlight", targets: ["Fastlight"]),
        // The bundled emoji picker, an extension like any other.
        .executable(name: "fastlight-emoji", targets: ["fastlight-emoji"]),
    ],
    targets: [
        // Search providers, the fsearch client and the extension host. No
        // AppKit, so it can be tested on its own.
        .target(name: "FastlightCore"),
        .executableTarget(name: "Fastlight", dependencies: ["FastlightCore"]),
        // The emoji extension's logic, apart from its stdin loop for tests.
        .target(name: "FastlightEmoji"),
        .executableTarget(name: "fastlight-emoji", dependencies: ["FastlightEmoji"]),
        .testTarget(name: "FastlightCoreTests", dependencies: ["FastlightCore"]),
        .testTarget(name: "FastlightEmojiTests", dependencies: ["FastlightEmoji"]),
    ]
)
