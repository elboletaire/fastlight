import Foundation
@testable import FastlightSystem

/// Records what would run; answers `output` from a table.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _outputs: [[String]] = []
    private var _launched: [[String]] = []
    var replies: [String: String] = [:]
    var failLaunch: String?
    /// Exit status handed to `onExit` right away (nil: never exits).
    var exitStatus: Int32? = 0

    var outputs: [[String]] { lock.withLock { _outputs } }
    var launched: [[String]] { lock.withLock { _launched } }

    func output(_ argv: [String], timeout: TimeInterval) throws -> String {
        lock.withLock { _outputs.append(argv) }
        guard let r = replies[argv.joined(separator: " ")] else { throw RunError("no reply for \(argv)") }
        return r
    }

    func launch(_ argv: [String], grace: TimeInterval, onExit: (@Sendable (Int32) -> Void)?) throws {
        lock.withLock { _launched.append(argv) }
        if let failLaunch {
            onExit?(1)
            throw RunError(failLaunch)
        }
        if let exitStatus { onExit?(exitStatus) }
    }
}

final class FakeExecutor: SystemExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var _executed: [SystemCommand] = []
    var fail: String?

    var executed: [SystemCommand] { lock.withLock { _executed } }

    func execute(_ command: SystemCommand) throws {
        lock.withLock { _executed.append(command) }
        if let fail { throw RunError(fail) }
    }
}

/// A settable clock.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)

    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
}

enum Fixture {
    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fastlight-system-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ plist: Any, to url: URL, binary: Bool = true) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: binary ? .binary : .xml, options: 0)
        try data.write(to: url)
    }

    /// A settings extension bundle like the ones in /System/Library/ExtensionKit/Extensions.
    @discardableResult
    static func appex(in root: URL, _ name: String, id: String, displayName: String? = nil,
                      point: String = SettingsScanner.extensionPoint, urlScheme: Bool = true,
                      graphicIcon: Bool = true, names: [String: String] = [:], localizable: [String: [String: String]] = [:],
                      searchTermsFile: String? = nil, searchTerms: [String: [String: [(title: String, index: String)]]] = [:]) throws -> URL {
        let appex = root.appendingPathComponent("\(name).appex")
        var settings: [String: Any] = ["legacyBundleIdentifier": "com.apple.preference.x"]
        if urlScheme { settings["allowsXAppleSystemPreferencesURLScheme"] = true }
        if let searchTermsFile { settings["searchTermsFileName"] = searchTermsFile }
        var info: [String: Any] = [
            "CFBundleIdentifier": id,
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": point, "SettingsExtensionAttributes": settings],
        ]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        if graphicIcon { info["CFBundleIcons"] = ["ISGraphicIconConfiguration": ["ISSymbolName": "wifi"]] }
        let contents = appex.appendingPathComponent("Contents")
        try write(info, to: contents.appendingPathComponent("Info.plist"), binary: false)
        let resources = contents.appendingPathComponent("Resources")
        if !names.isEmpty {
            try write(names.mapValues { ["CFBundleDisplayName": $0] }, to: resources.appendingPathComponent("InfoPlist.loctable"))
        }
        if !localizable.isEmpty {
            try write(localizable, to: resources.appendingPathComponent("Localizable.loctable"))
        }
        if let searchTermsFile {
            for (lang, groups) in searchTerms {
                let plist = groups.mapValues { strings in
                    ["localizableStrings": strings.map { ["title": $0.title, "index": $0.index, "comments": "x"] }]
                }
                try write(plist, to: resources.appendingPathComponent("\(lang).lproj/\(searchTermsFile).searchTerms"))
            }
        }
        return appex
    }
}
