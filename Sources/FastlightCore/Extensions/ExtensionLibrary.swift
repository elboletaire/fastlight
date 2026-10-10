import CryptoKit
import FastlightL10n
import Foundation

/// An extension that passed validation and can be started.
public struct LoadedExtension: Sendable, Hashable, Identifiable {
    public var manifest: ExtensionManifest
    public var directory: URL
    public var executable: URL
    public var arguments: [String]
    /// Shipped inside Fastlight.app: trusted, never asks for consent.
    public var builtIn: Bool
    /// SHA-256 of every file in the folder; what consent is given to.
    public var fingerprint: String

    public var id: String { manifest.id }
    /// Built-ins' names and descriptions are translated from the
    /// Extensions table, keyed by their English manifest text; anyone
    /// else's are shown as their manifest has them.
    public var name: String { builtIn ? Localizer.current.string(manifest.name, table: "Extensions") : manifest.name }
    public var summary: String? {
        guard let d = manifest.description else { return nil }
        return builtIn ? Localizer.current.string(d, table: "Extensions") : d
    }
    public var icon: ItemIcon? { manifest.icon?.resolved(in: directory) }

    public init(manifest: ExtensionManifest, directory: URL, executable: URL, arguments: [String],
                builtIn: Bool, fingerprint: String) {
        self.manifest = manifest
        self.directory = directory
        self.executable = executable
        self.arguments = arguments
        self.builtIn = builtIn
        self.fingerprint = fingerprint
    }
}

/// A folder that looked like an extension but couldn't be loaded.
public struct LoadIssue: Sendable, Hashable {
    public var folder: URL
    public var message: String

    public var description: String { "\(folder.lastPathComponent): \(message)" }
}

/// Finds and validates extensions: the built-ins in the app bundle and the
/// user's folder. Rescanning is cheap: folders whose files (paths, sizes,
/// dates) didn't change aren't read or hashed again.
public final class ExtensionLibrary {
    public static var defaultUserRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Fastlight/Extensions", isDirectory: true)
    }

    /// Fastlight.app/Contents/Resources/Extensions.
    public static func builtInRoot(bundle: URL = Bundle.main.bundleURL) -> URL {
        bundle.appendingPathComponent("Contents/Resources/Extensions", isDirectory: true)
    }

    public let builtInRoot: URL?
    public let userRoot: URL
    /// Where built-ins' executables live (Contents/Helpers, or next to the
    /// binary when running from `swift build`).
    public let helperDirs: [URL]
    public let appVersion: String

    public private(set) var extensions: [LoadedExtension] = []
    public private(set) var issues: [LoadIssue] = []

    private enum Loaded {
        case ok(LoadedExtension)
        case issue(String)
    }

    private var cache: [URL: (stamp: String, loaded: Loaded)] = [:]

    public static let maxFiles = 5000
    public static let maxBytes: UInt64 = 100 << 20

    public init(builtInRoot: URL?, userRoot: URL = ExtensionLibrary.defaultUserRoot, helperDirs: [URL] = [],
                appVersion: String) {
        self.builtInRoot = builtInRoot
        self.userRoot = userRoot
        self.helperDirs = helperDirs
        self.appVersion = appVersion
    }

    public func `extension`(id: String) -> LoadedExtension? {
        extensions.first { $0.id == id }
    }

    /// Keywords of the given extensions (in library order) to their ids.
    /// Conflicts are reported in `issues` by `refresh`.
    public func router(including ids: Set<String>) -> KeywordRouter {
        KeywordRouter(extensions.filter { ids.contains($0.id) }.map { ($0.id, $0.manifest.keywords) })
    }

    /// Rescans both roots. Returns whether anything changed.
    @discardableResult
    public func refresh(force: Bool = false) -> Bool {
        if force { cache = [:] }
        var found: [(URL, Bool)] = []
        if let builtInRoot { found += Self.folders(in: builtInRoot).map { ($0, true) } }
        found += Self.folders(in: userRoot).map { ($0, false) }

        var nextCache: [URL: (stamp: String, loaded: Loaded)] = [:]
        var exts: [LoadedExtension] = []
        var problems: [LoadIssue] = []
        var owners: [String: URL] = [:]
        for (dir, builtIn) in found {
            let stamp = Self.stamp(of: dir)
            let loaded: Loaded
            if let c = cache[dir], c.stamp == stamp {
                loaded = c.loaded
            } else {
                do {
                    loaded = .ok(try load(dir, builtIn: builtIn))
                } catch {
                    loaded = .issue(error.localizedDescription)
                }
            }
            nextCache[dir] = (stamp, loaded)
            switch loaded {
            case .ok(let e):
                if let owner = owners[e.id] {
                    problems.append(LoadIssue(folder: dir, message: "id \(e.id) is already used by \(owner.lastPathComponent)"))
                    continue
                }
                owners[e.id] = dir
                exts.append(e)
            case .issue(let msg):
                problems.append(LoadIssue(folder: dir, message: msg))
            }
        }
        for c in KeywordRouter(exts.map { ($0.id, $0.manifest.keywords) }).conflicts {
            let dir = exts.first { $0.id == c.id }?.directory ?? userRoot
            let owner = exts.first { $0.id == c.owner }?.name ?? c.owner
            problems.append(LoadIssue(folder: dir, message: "keyword \"\(c.keyword)\" is already used by \(owner)"))
        }
        cache = nextCache
        let changed = exts != extensions || problems != issues
        extensions = exts
        issues = problems
        return changed
    }

    /// Subfolders with an extension.json, sorted by name.
    static func folders(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.sorted().compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            let dir = root.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return dir
        }
    }

    func load(_ dir: URL, builtIn: Bool) throws -> LoadedExtension {
        let file = dir.appendingPathComponent(ExtensionManifest.fileName)
        guard let data = try? Data(contentsOf: file) else {
            throw ValidationError("", "no \(ExtensionManifest.fileName) in this folder")
        }
        let manifest: ExtensionManifest
        do {
            manifest = try ExtensionManifest.parse(data, appVersion: appVersion)
        } catch let e as ValidationError {
            throw ValidationError(e.path.isEmpty ? ExtensionManifest.fileName : "\(ExtensionManifest.fileName): \(e.path)", e.message)
        }
        let exe = try resolveExecutable(manifest.command[0], in: dir, builtIn: builtIn)
        let fingerprint = builtIn ? "builtin" : try Self.fingerprint(of: dir)
        return LoadedExtension(manifest: manifest, directory: dir, executable: exe,
                               arguments: Array(manifest.command.dropFirst()), builtIn: builtIn, fingerprint: fingerprint)
    }

    private func resolveExecutable(_ exe: String, in dir: URL, builtIn: Bool) throws -> URL {
        let fm = FileManager.default
        let where_ = "\(ExtensionManifest.fileName): command[0]"
        if exe.hasPrefix("/") {
            guard fm.isExecutableFile(atPath: exe) else { throw ValidationError(where_, "\(exe) doesn't exist or isn't executable") }
            return URL(fileURLWithPath: exe)
        }
        var candidates = [dir.appendingPathComponent(exe)]
        if builtIn { candidates += helperDirs.map { $0.appendingPathComponent(exe) } }
        for c in candidates where fm.fileExists(atPath: c.path) {
            if !builtIn {
                // Symlinks out of the folder would run code the fingerprint
                // doesn't cover.
                let real = c.resolvingSymlinksInPath().path
                let root = dir.resolvingSymlinksInPath().path + "/"
                guard real.hasPrefix(root) else { throw ValidationError(where_, "\(exe) points outside the extension folder") }
            }
            guard fm.isExecutableFile(atPath: c.path) else {
                throw ValidationError(where_, "\(exe) isn't executable (chmod +x \(exe))")
            }
            return c.standardizedFileURL
        }
        throw ValidationError(where_, "\(exe) not found in the extension folder")
    }

    // MARK: Fingerprints

    private static func files(in dir: URL) -> [(rel: String, url: URL, values: URLResourceValues)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey,
                                      .contentModificationDateKey, .attributeModificationDateKey]
        // An extension folder may be a symlink (to a working copy, say); the
        // enumerator lists nothing through one, which would hash nothing.
        let real = dir.resolvingSymlinksInPath()
        guard let e = FileManager.default.enumerator(at: real, includingPropertiesForKeys: keys) else { return [] }
        let base = real.standardizedFileURL.path
        var out: [(String, URL, URLResourceValues)] = []
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            // Finder's view settings, rewritten whenever the folder is
            // looked at. Everything else counts, .git included: code can run
            // from anywhere in the folder.
            if url.lastPathComponent == ".DS_Store" { continue }
            guard v.isRegularFile == true || v.isSymbolicLink == true else { continue }
            let full = url.standardizedFileURL.path
            let rel = full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
            out.append((rel, url, v))
            if out.count > maxFiles { break }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Paths, sizes and dates: changes whenever a file does, without reading.
    /// The change time (ctime) is in there because, unlike the modification
    /// time, it can't be set back by hand.
    static func stamp(of dir: URL) -> String {
        files(in: dir).map { f in
            let m = f.values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let c = f.values.attributeModificationDate?.timeIntervalSince1970 ?? 0
            return "\(f.rel)|\(f.values.fileSize ?? -1)|\(m)|\(c)"
        }.joined(separator: "\n")
    }

    /// SHA-256 over each file's relative path and contents (a symlink's
    /// target instead of contents), in path order, every field prefixed
    /// with its length so no two folders can produce the same input.
    public static func fingerprint(of dir: URL) throws -> String {
        let list = files(in: dir)
        if list.count > maxFiles { throw ValidationError("", "has more than \(maxFiles) files") }
        var total: UInt64 = 0
        var hash = SHA256()
        func field(_ kind: UInt8, _ data: Data) {
            var n = UInt64(data.count).bigEndian
            hash.update(data: Data([kind]))
            hash.update(data: withUnsafeBytes(of: &n) { Data($0) })
            hash.update(data: data)
        }
        for f in list {
            field(0, Data(f.rel.utf8))
            if f.values.isSymbolicLink == true {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: f.url.path)) ?? ""
                field(1, Data(target.utf8))
            } else {
                total += UInt64(f.values.fileSize ?? 0)
                if total > maxBytes { throw ValidationError("", "is larger than \(maxBytes >> 20) MB") }
                guard let data = try? Data(contentsOf: f.url, options: .mappedIfSafe) else {
                    throw ValidationError("", "can't read \(f.rel)")
                }
                field(2, data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Consent

/// Which extensions the user approved (by fingerprint) or turned off.
public final class ConsentStore: @unchecked Sendable {
    public enum Need: Equatable, Sendable {
        case new
        /// Approved before, but its files changed since.
        case changed(approvedVersion: String)
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let approvedKey = "fastlight.extensions.approved"
    private let disabledKey = "fastlight.extensions.disabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var approved: [String: [String: String]] {
        defaults.dictionary(forKey: approvedKey) as? [String: [String: String]] ?? [:]
    }

    /// Nil when the extension may run as far as consent goes.
    public func need(_ ext: LoadedExtension) -> Need? {
        if ext.builtIn { return nil }
        guard let a = lock.withLock({ approved[ext.id] }) else { return .new }
        if a["fingerprint"] == ext.fingerprint { return nil }
        return .changed(approvedVersion: a["version"] ?? "?")
    }

    public func approve(_ ext: LoadedExtension) {
        lock.withLock {
            var all = approved
            all[ext.id] = ["fingerprint": ext.fingerprint, "version": ext.manifest.version]
            defaults.set(all, forKey: approvedKey)
        }
    }

    public func revoke(_ id: String) {
        lock.withLock {
            var all = approved
            all[id] = nil
            defaults.set(all, forKey: approvedKey)
        }
    }

    public func isDisabled(_ id: String) -> Bool {
        lock.withLock { (defaults.stringArray(forKey: disabledKey) ?? []).contains(id) }
    }

    public func setDisabled(_ id: String, _ disabled: Bool) {
        lock.withLock {
            var ids = Set(defaults.stringArray(forKey: disabledKey) ?? [])
            if disabled { ids.insert(id) } else { ids.remove(id) }
            defaults.set(ids.sorted(), forKey: disabledKey)
        }
    }

    /// Enabled and approved: allowed to start.
    public func mayRun(_ ext: LoadedExtension) -> Bool {
        !isDisabled(ext.id) && need(ext) == nil
    }
}
