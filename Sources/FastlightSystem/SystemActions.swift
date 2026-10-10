import Foundation

/// What carrying out an action takes.
public enum SystemCommand: Equatable, Sendable {
    /// A program and its arguments.
    case process([String])
    /// The login framework's lock, the same as the Lock Screen menu item
    /// (no permission needed, unlike pressing ⌃⌘Q for the user).
    case lockScreen
}

/// Carries out commands. Behind a protocol so tests never lock, sleep or
/// shut down the machine running them.
public protocol SystemExecutor: Sendable {
    func execute(_ command: SystemCommand) throws
}

public struct LiveExecutor: SystemExecutor {
    public var runner: any CommandRunner

    public init(runner: any CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func execute(_ command: SystemCommand) throws {
        switch command {
        case .process(let argv):
            // Emptying a big Trash takes a while: catch quick failures
            // (a denied Automation permission), don't wait for the rest.
            try runner.launch(argv, grace: 1.5)
        case .lockScreen:
            try ScreenLock.lock()
        }
    }
}

/// SACLockScreenImmediate, from the private login framework, which is
/// what the Apple menu's Lock Screen uses.
public enum ScreenLock {
    static let framework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
    typealias Lock = @convention(c) () -> Int32

    static func symbol() -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(framework, RTLD_LAZY) else { return nil }
        return dlsym(handle, "SACLockScreenImmediate")
    }

    /// Whether this macOS has it (looked up, never called).
    public static var isAvailable: Bool { symbol() != nil }

    public static func lock() throws {
        guard let sym = symbol() else { throw RunError("Can't lock the screen on this version of macOS") }
        _ = unsafeBitCast(sym, to: Lock.self)()
    }
}

/// A mounted disk that can be ejected.
public struct Volume: Equatable, Sendable {
    public var name: String
    public var path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    /// External drives, disk images and network volumes: what Finder's
    /// eject button would take.
    public static func ejectable() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey,
                                      .volumeIsLocalKey, .volumeLocalizedNameKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true,
                  url.path.hasPrefix("/Volumes/") else { return nil }
            let ejectable = v.volumeIsEjectable == true || v.volumeIsRemovable == true
                || v.volumeIsInternal == false || v.volumeIsLocal == false
            return ejectable ? Volume(name: v.volumeLocalizedName ?? url.lastPathComponent, path: url.path) : nil
        }
    }
}

/// The actions, and what each takes.
public struct SystemAction: Sendable, Equatable {
    public enum ID: String, CaseIterable, Sendable {
        case lockScreen, sleep, sleepDisplays, screenSaver, toggleDarkMode, ejectAll, emptyTrash, logOut, restart, shutDown
    }

    public var id: ID
    public var title: String
    public var aliases: [String]
    public var symbol: String
    public var subtitle: String
    /// Disruptive or destructive: needs ↵ twice (see `Confirmation`).
    public var confirm: Bool
    /// "shut down", for "Press ↵ again to shut down".
    public var verb: String

    public static let all: [SystemAction] = [
        SystemAction(id: .lockScreen, title: "Lock Screen", aliases: ["lock", "lock mac", "lock computer"],
                     symbol: "lock", subtitle: "Locks the screen right away", confirm: false, verb: "lock the screen"),
        SystemAction(id: .sleep, title: "Sleep", aliases: ["sleep mac", "suspend"],
                     symbol: "moon.zzz", subtitle: "Puts the Mac to sleep", confirm: false, verb: "sleep"),
        SystemAction(id: .sleepDisplays, title: "Sleep Displays", aliases: ["display sleep", "screen off", "turn off displays", "turn off screen"],
                     symbol: "display", subtitle: "Turns the displays off; the Mac keeps running", confirm: false, verb: "sleep the displays"),
        SystemAction(id: .screenSaver, title: "Start Screen Saver", aliases: ["screen saver", "screensaver"],
                     symbol: "sparkles.tv", subtitle: "Starts the screen saver", confirm: false, verb: "start the screen saver"),
        SystemAction(id: .toggleDarkMode, title: "Toggle Dark Mode", aliases: ["dark mode", "light mode", "toggle appearance", "dark", "night mode"],
                     symbol: "circle.lefthalf.filled", subtitle: "", confirm: false, verb: "switch appearance"),
        SystemAction(id: .ejectAll, title: "Eject All Disks", aliases: ["eject", "eject disks", "eject all", "unmount"],
                     symbol: "eject", subtitle: "", confirm: false, verb: "eject"),
        SystemAction(id: .emptyTrash, title: "Empty Trash", aliases: ["empty bin", "empty the trash"],
                     symbol: "trash", subtitle: "Deletes everything in the Trash for good", confirm: true, verb: "empty the Trash"),
        SystemAction(id: .logOut, title: "Log Out", aliases: ["logout", "log off", "sign out"],
                     symbol: "rectangle.portrait.and.arrow.right", subtitle: "Quits all apps and logs you out", confirm: true, verb: "log out"),
        SystemAction(id: .restart, title: "Restart", aliases: ["reboot", "restart mac"],
                     symbol: "restart", subtitle: "Quits all apps and restarts the Mac", confirm: true, verb: "restart"),
        SystemAction(id: .shutDown, title: "Shut Down", aliases: ["shutdown", "power off", "turn off", "turn off mac"],
                     symbol: "power", subtitle: "Quits all apps and turns the Mac off", confirm: true, verb: "shut down"),
    ]

    public static func action(_ id: ID) -> SystemAction { all.first { $0.id == id }! }

    /// The least-privileged way to do each. Apple events need Fastlight to
    /// be allowed to control the target app (Automation), asked once.
    public static func commands(for id: ID, volumes: [Volume]) -> [SystemCommand] {
        func script(_ s: String) -> SystemCommand { .process(["/usr/bin/osascript", "-e", s]) }
        switch id {
        case .lockScreen: return [.lockScreen]
        case .sleep: return [.process(["/usr/bin/pmset", "sleepnow"])]
        case .sleepDisplays: return [.process(["/usr/bin/pmset", "displaysleepnow"])]
        case .screenSaver: return [.process(["/usr/bin/open", "-b", "com.apple.ScreenSaver.Engine"])]
        // Automation: System Events.
        case .toggleDarkMode:
            return [script("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")]
        case .ejectAll: return volumes.map { .process(["/usr/sbin/diskutil", "eject", $0.path]) }
        // Automation: Finder. Finder empties every volume's Trash, as its menu does.
        case .emptyTrash: return [script("tell application \"Finder\" to empty trash")]
        // Automation: loginwindow. The "really" events skip loginwindow's own
        // dialog (Fastlight already asked); apps can still cancel to save work.
        case .logOut: return [script("tell application \"loginwindow\" to «event aevtrlgo»")]
        case .restart: return [script("tell application \"loginwindow\" to «event aevtrrst»")]
        case .shutDown: return [script("tell application \"loginwindow\" to «event aevtrsdn»")]
        }
    }
}

/// The second ↵ for disruptive actions.
///
/// Picking "Restart" arms it, and the list is searched again: the item
/// has become "Confirm Restart?", first in the list (the Top Hit in
/// normal search). Only picking that within `window` seconds restarts.
/// Anything else, a different action armed, or the time running out,
/// leaves the Mac alone.
public struct Confirmation: Sendable {
    public static let window: TimeInterval = 5

    private var armed: (id: SystemAction.ID, at: Date)?

    public init() {}

    public mutating func arm(_ id: SystemAction.ID, now: Date) {
        armed = (id, now)
    }

    public func isArmed(_ id: SystemAction.ID, now: Date) -> Bool {
        guard let a = armed, a.id == id else { return false }
        let age = now.timeIntervalSince(a.at)
        return age >= 0 && age <= Self.window
    }

    /// Whether `id` may run now. Either way, the arming is used up.
    public mutating func confirm(_ id: SystemAction.ID, now: Date) -> Bool {
        defer { armed = nil }
        return isArmed(id, now: now)
    }

    public mutating func disarm() {
        armed = nil
    }
}

/// The System extension: lock, sleep, restart and friends.
public final class SystemActionsExtension: LineHandler, @unchecked Sendable {
    let executor: any SystemExecutor
    let now: @Sendable () -> Date
    let isDark: @Sendable () -> Bool
    let volumes: @Sendable () -> [Volume]
    private let lock = NSLock()
    private var confirmation = Confirmation()

    public init(executor: any SystemExecutor = LiveExecutor(), now: @escaping @Sendable () -> Date = { Date() },
                isDark: @escaping @Sendable () -> Bool = SystemActionsExtension.darkModeIsOn,
                volumes: @escaping @Sendable () -> [Volume] = Volume.ejectable) {
        self.executor = executor
        self.now = now
        self.isDark = isDark
        self.volumes = volumes
    }

    public static func darkModeIsOn() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        return style == "Dark"
    }

    public func handle(_ line: String) -> String? {
        guard let r = Request(line), let id = r.id else { return nil }
        switch r.type {
        case "search":
            return Reply.items(id, items(for: r.query, global: r.global, limit: r.limit))
        case "run":
            do {
                try run(r.name, item: r.data as? String ?? r.item)
                return Reply.done(id)
            } catch {
                return Reply.error(id, (error as? RunError)?.message ?? error.localizedDescription)
            }
        default:
            return Reply.error(id, "unknown request type \(r.type)")
        }
    }

    /// Normal search is strict: the query must be a name or alias, or the
    /// start of one (4+ letters), and only plain words: "sleep" and "rest"
    /// offer, "sleep.txt" and "sleeping beauty" don't.
    static func matches(_ a: SystemAction, _ query: String, global: Bool) -> MatchKind? {
        let q = TextMatch.words(query)
        guard !q.isEmpty else { return nil }
        let names = [a.title] + a.aliases
        if global {
            let plain = query.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "'" || $0 == "’" }
            guard plain else { return nil }
            let kinds = names.compactMap { TextMatch.match(q, TextMatch.words($0)) }
            if kinds.contains(.exact) { return .exact }
            if kinds.contains(.prefix), q.joined(separator: " ").count >= 4 { return .prefix }
            return nil
        }
        return TextMatch.best(q, names)
    }

    public func items(for query: String, global: Bool, limit: Int) -> [[String: Any]] {
        let t = now()
        let empty = TextMatch.words(query).isEmpty
        guard !(global && empty) else { return [] }
        let found = SystemAction.all.enumerated().compactMap { (i, a) -> (SystemAction, Int, Bool)? in
            let armed = lock.withLock { confirmation.isArmed(a.id, now: t) }
            if empty { return (a, 0, armed) }
            guard let k = Self.matches(a, query, global: global) else { return nil }
            return (a, k.rawValue, armed)
        }
        // An armed action goes first, so the next ↵ is the confirmation.
        let sorted = found.enumerated().sorted { x, y in
            if x.element.2 != y.element.2 { return x.element.2 }
            if x.element.1 != y.element.1 { return x.element.1 > y.element.1 }
            return x.offset < y.offset
        }.map(\.element)
        var out: [[String: Any]] = []
        for (a, _, armed) in sorted {
            guard let item = item(a, armed: armed, global: global) else { continue }
            out.append(item)
        }
        return Array(out.prefix(limit))
    }

    func item(_ a: SystemAction, armed: Bool, global: Bool) -> [String: Any]? {
        var item: [String: Any] = ["id": a.id.rawValue, "icon": a.symbol]
        let id = a.id.rawValue
        if a.confirm {
            if armed {
                item["title"] = "Confirm \(a.title)?"
                item["subtitle"] = "Press ↵ again within \(Int(Confirmation.window)) seconds to \(a.verb)"
                item["icon"] = "exclamationmark.triangle"
                item["actions"] = [
                    ["type": "run", "name": "confirm", "data": id, "title": a.title],
                    ["type": "run", "name": "disarm", "data": id, "then": "refresh", "title": "Cancel"],
                ]
                // Built-ins may take the Top Hit: there, ↵ confirms in
                // normal search too.
                if global { item["topHit"] = true }
            } else {
                item["title"] = a.title + "…"
                item["subtitle"] = a.subtitle + " (asks first)"
                item["actions"] = [["type": "run", "name": "arm", "data": id, "then": "refresh", "title": a.title + "…"]]
            }
            return item
        }
        item["title"] = a.title
        item["subtitle"] = a.subtitle
        switch a.id {
        case .toggleDarkMode:
            item["subtitle"] = isDark() ? "Dark Mode is on: switch to Light" : "Dark Mode is off: switch to Dark"
        case .ejectAll:
            let v = volumes()
            if v.isEmpty {
                // Nothing to eject: say so in keyword mode, stay quiet otherwise.
                guard !global else { return nil }
                item["subtitle"] = "No disks to eject"
                return item
            }
            item["subtitle"] = v.map(\.name).joined(separator: ", ")
        default:
            break
        }
        item["actions"] = [["type": "run", "name": "perform", "data": id, "title": a.title]]
        return item
    }

    public func run(_ name: String, item: String) throws {
        guard let id = SystemAction.ID(rawValue: item) else { throw RunError("unknown action") }
        let action = SystemAction.action(id)
        let t = now()
        switch name {
        case "perform":
            // Never a way around the confirmation.
            guard !action.confirm else { throw RunError("\(action.title) needs confirming") }
        case "arm":
            guard action.confirm else { throw RunError("unknown action") }
            lock.withLock { confirmation.arm(id, now: t) }
            return
        case "disarm":
            lock.withLock { confirmation.disarm() }
            return
        case "confirm":
            guard action.confirm else { throw RunError("unknown action") }
            let ok = lock.withLock { confirmation.confirm(id, now: t) }
            guard ok else {
                throw RunError("Not confirmed in time, so the Mac didn't \(action.verb). Try again.")
            }
        default:
            throw RunError("unknown action")
        }
        let commands = SystemAction.commands(for: id, volumes: id == .ejectAll ? volumes() : [])
        guard !commands.isEmpty else { throw RunError("No disks to eject") }
        var failures: [String] = []
        for c in commands {
            do {
                try executor.execute(c)
            } catch {
                failures.append((error as? RunError)?.message ?? error.localizedDescription)
            }
        }
        if let first = failures.first { throw RunError("Couldn't \(action.verb): \(first)") }
    }
}
