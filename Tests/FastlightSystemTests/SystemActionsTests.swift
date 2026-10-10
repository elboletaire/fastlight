import Foundation
import Testing
@testable import FastlightSystem

@Suite struct ConfirmationTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func armedForAFewSeconds() {
        var c = Confirmation()
        #expect(!c.isArmed(.restart, now: t0))
        c.arm(.restart, now: t0)
        #expect(c.isArmed(.restart, now: t0))
        #expect(c.isArmed(.restart, now: t0.addingTimeInterval(Confirmation.window)))
        #expect(!c.isArmed(.restart, now: t0.addingTimeInterval(Confirmation.window + 0.1)))
        #expect(!c.isArmed(.shutDown, now: t0))
        // A clock that went backwards doesn't count.
        #expect(!c.isArmed(.restart, now: t0.addingTimeInterval(-1)))
    }

    @Test func confirmingUsesItUp() {
        var c = Confirmation()
        c.arm(.shutDown, now: t0)
        let ok1 = c.confirm(.shutDown, now: t0.addingTimeInterval(2))
        #expect(ok1 == .confirmed)
        let ok2 = c.confirm(.shutDown, now: t0.addingTimeInterval(2))
        #expect(ok2 == .notArmed)
    }

    @Test func onlyTheArmedActionAndNotTooLate() {
        var c = Confirmation()
        c.arm(.logOut, now: t0)
        let ok3 = c.confirm(.restart, now: t0)
        #expect(ok3 == .notArmed)
        // The wrong guess disarmed it too.
        let ok4 = c.confirm(.logOut, now: t0)
        #expect(ok4 == .notArmed)

        c.arm(.logOut, now: t0)
        let ok5 = c.confirm(.logOut, now: t0.addingTimeInterval(6))
        #expect(ok5 == .notArmed)

        c.arm(.logOut, now: t0)
        c.arm(.emptyTrash, now: t0) // arming another replaces it
        #expect(!c.isArmed(.logOut, now: t0))
        c.disarm()
        #expect(!c.isArmed(.emptyTrash, now: t0))
    }

    /// A held ↵ arms, then its auto-repeat lands on "Confirm Restart?".
    @Test func tooQuickIsNotASecondPress() {
        var c = Confirmation()
        c.arm(.restart, now: t0)
        let quick = c.confirm(.restart, now: t0.addingTimeInterval(Confirmation.minimum - 0.05))
        #expect(quick == .tooSoon)
        // Used up: a held key can't try again.
        let again = c.confirm(.restart, now: t0.addingTimeInterval(Confirmation.minimum + 0.1))
        #expect(again == .notArmed)

        c.arm(.restart, now: t0)
        let deliberate = c.confirm(.restart, now: t0.addingTimeInterval(Confirmation.minimum + 0.01))
        #expect(deliberate == .confirmed)
    }
}

@Suite struct SystemActionsTests {
    static let disk = Volume(name: "Backup", path: "/Volumes/Backup")

    func ext(volumes: [Volume] = [], dark: Bool = false, clock: Clock = Clock()) -> (SystemActionsExtension, FakeExecutor) {
        let x = FakeExecutor()
        return (SystemActionsExtension(executor: x, now: { clock.now }, isDark: { dark }, volumes: { volumes }), x)
    }

    func ids(_ e: SystemActionsExtension, _ q: String, global: Bool = true) -> [String] {
        e.items(for: q, global: global, limit: 10).compactMap { $0["id"] as? String }
    }

    @Test func normalSearchIsStrict() {
        let (e, _) = ext(volumes: [Self.disk])
        #expect(ids(e, "sleep") == ["sleep", "sleepDisplays"])
        #expect(ids(e, "Sleep") == ["sleep", "sleepDisplays"])
        #expect(ids(e, "lock") == ["lockScreen"])
        #expect(ids(e, "lock screen") == ["lockScreen"])
        #expect(ids(e, "restart") == ["restart"])
        #expect(ids(e, "reboot") == ["restart"])
        #expect(ids(e, "rest") == ["restart"])
        #expect(ids(e, "shut down") == ["shutDown"])
        #expect(ids(e, "shutdown") == ["shutDown"])
        #expect(ids(e, "log out") == ["logOut"])
        #expect(ids(e, "empty trash") == ["emptyTrash"])
        #expect(ids(e, "dark mode") == ["toggleDarkMode"])
        #expect(ids(e, "eject") == ["ejectAll"])
        #expect(ids(e, "screen saver") == ["screenSaver"])
        // The start of a name, from four letters on.
        #expect(ids(e, "shut") == ["shutDown"])
        #expect(ids(e, "power") == ["shutDown"])

        for q in ["sleep.txt", "sleep.", "sleeping beauty", "sleeping", "restart.log", "restarting", "res", "log",
                  "lock-screen.png", "trash", "shu", "~/sleep", "deep sleep", "the restart", ""] {
            #expect(ids(e, q).isEmpty, "\(q)")
        }
    }

    @Test func keywordModeIsLooser() {
        let (e, _) = ext(volumes: [Self.disk])
        #expect(ids(e, "", global: false).count == SystemAction.all.count)
        #expect(ids(e, "trash", global: false) == ["emptyTrash"])
        #expect(ids(e, "res", global: false) == ["restart"])
        #expect(ids(e, "off", global: false).contains("shutDown"))
    }

    @Test func disruptiveActionsOnlyArm() throws {
        let (e, x) = ext()
        let item = try #require(e.items(for: "restart", global: true, limit: 3).first)
        #expect(item["title"] as? String == "Restart…")
        let action = try #require((item["actions"] as? [[String: Any]])?.first)
        #expect(action["name"] as? String == "arm" && action["then"] as? String == "refresh")
        #expect(item["topHit"] == nil)
        #expect(e.handle(#"{"id":1,"type":"run","name":"arm","item":"restart","data":"restart","query":"restart"}"#) == #"{"id":1}"#)
        #expect(x.executed.isEmpty)
        // Nor can "perform" skip the second step.
        let r = try #require(e.handle(#"{"id":2,"type":"run","name":"perform","item":"restart","data":"restart","query":"restart"}"#))
        #expect(r.contains("needs confirming"))
        #expect(x.executed.isEmpty)
    }

    @Test func armedItemComesFirstAndConfirms() throws {
        let clock = Clock()
        let (e, x) = ext(clock: clock)
        try e.run("arm", item: "shutDown")
        // Keyword mode: first, whatever else matches.
        let list = e.items(for: "", global: false, limit: 20)
        #expect(list.first?["id"] as? String == "shutDown")
        #expect(list.first?["title"] as? String == "Confirm Shut Down?")
        #expect(list.first?["subtitle"] as? String == "Press ↵ again within 5 seconds to shut down")
        let actions = try #require(list.first?["actions"] as? [[String: Any]])
        #expect(actions.map { $0["name"] as? String } == ["confirm", "disarm"])
        #expect(actions[0]["then"] == nil) // closes
        #expect(list.first?["topHit"] == nil)
        // Normal search: the Top Hit, so ↵ lands on it after the refresh.
        let global = try #require(e.items(for: "shut down", global: true, limit: 3).first)
        #expect(global["topHit"] as? Bool == true)

        clock.advance(3)
        try e.run("confirm", item: "shutDown")
        #expect(x.executed == [.process(["/usr/bin/osascript", "-e", "tell application \"loginwindow\" to «event aevtrsdn»"])])
        // Used up.
        #expect(e.items(for: "shut down", global: true, limit: 3).first?["title"] as? String == "Shut Down…")
        #expect(throws: RunError.self) { try e.run("confirm", item: "shutDown") }
        #expect(x.executed.count == 1)
    }

    @Test func tooLateOrTheWrongOneDoesNothing() throws {
        let clock = Clock()
        let (e, x) = ext(clock: clock)
        try e.run("arm", item: "emptyTrash")
        clock.advance(5.5)
        #expect(e.items(for: "empty trash", global: true, limit: 3).first?["title"] as? String == "Empty Trash…")
        let r = try #require(e.handle(#"{"id":3,"type":"run","name":"confirm","item":"emptyTrash","data":"emptyTrash"}"#))
        #expect(r.contains("Not confirmed in time"))

        try e.run("arm", item: "logOut")
        #expect(throws: RunError.self) { try e.run("confirm", item: "restart") }
        try e.run("arm", item: "logOut")
        try e.run("disarm", item: "logOut")
        #expect(throws: RunError.self) { try e.run("confirm", item: "logOut") }

        // Straight after arming: a held ↵, not a decision.
        try e.run("arm", item: "restart")
        clock.advance(0.1)
        let q = try #require(e.handle(#"{"id":4,"type":"run","name":"confirm","item":"restart","data":"restart"}"#))
        #expect(q.contains("Confirmed too quickly"))
        #expect(x.executed.isEmpty)
        // Arming is for disruptive actions only, confirming too.
        #expect(throws: RunError.self) { try e.run("arm", item: "sleep") }
        #expect(throws: RunError.self) { try e.run("confirm", item: "sleep") }
        #expect(throws: RunError.self) { try e.run("perform", item: "frobnicate") }
        #expect(x.executed.isEmpty)
    }

    @Test func harmlessActionsRunStraightAway() throws {
        let (e, x) = ext(volumes: [Self.disk, Volume(name: "Stick", path: "/Volumes/Stick")])
        for id in ["lockScreen", "sleep", "sleepDisplays", "screenSaver", "toggleDarkMode", "ejectAll"] {
            try e.run("perform", item: id)
        }
        #expect(x.executed == [
            .lockScreen,
            .process(["/usr/bin/pmset", "sleepnow"]),
            .process(["/usr/bin/pmset", "displaysleepnow"]),
            .process(["/usr/bin/open", "-b", "com.apple.ScreenSaver.Engine"]),
            .process(["/usr/bin/osascript", "-e",
                      "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"]),
            .eject(Self.disk),
            .eject(Volume(name: "Stick", path: "/Volumes/Stick")),
        ])
    }

    /// `diskutil eject` takes every volume of the disk: the second volume
    /// of one already ejected is done, not "Couldn't eject".
    @Test func ejectingADiskTakesItsOtherVolumes() throws {
        final class Mounts: @unchecked Sendable {
            let runner: FakeRunner
            init(_ runner: FakeRunner) { self.runner = runner }
            var now: Set<String> {
                var m: Set<String> = ["/", "/Volumes/Data", "/Volumes/Photos", "/Volumes/Stick", "/Volumes/Share"]
                if runner.outputs.contains(["/usr/sbin/diskutil", "eject", "/Volumes/Data"]) { m.subtract(["/Volumes/Data", "/Volumes/Photos"]) }
                return m
            }
        }
        let runner = FakeRunner()
        for argv in [["eject", "/Volumes/Data"], ["eject", "/Volumes/Stick"], ["unmount", "/Volumes/Share"]] {
            runner.replies[(["/usr/sbin/diskutil"] + argv).joined(separator: " ")] = ""
        }
        let mounts = Mounts(runner)
        let volumes = [Volume(name: "Data", path: "/Volumes/Data"), Volume(name: "Photos", path: "/Volumes/Photos"),
                       Volume(name: "Stick", path: "/Volumes/Stick"), Volume(name: "Share", path: "/Volumes/Share", network: true)]
        let e = SystemActionsExtension(executor: LiveExecutor(runner: runner, mounted: { mounts.now }), now: { Date() },
                                       isDark: { false }, volumes: { volumes })
        try e.run("perform", item: "ejectAll")
        #expect(runner.outputs == [["/usr/sbin/diskutil", "eject", "/Volumes/Data"],
                                   ["/usr/sbin/diskutil", "eject", "/Volumes/Stick"],
                                   ["/usr/sbin/diskutil", "unmount", "/Volumes/Share"]])
        #expect(runner.launched.isEmpty)

        // A real failure still says so.
        runner.replies["/usr/sbin/diskutil eject /Volumes/Stick"] = nil
        #expect(throws: RunError.self) { try e.run("perform", item: "ejectAll") }
    }

    @Test func everyDisruptiveCommand() {
        func script(_ id: SystemAction.ID) -> [SystemCommand] { SystemAction.commands(for: id, volumes: []) }
        #expect(script(.emptyTrash) == [.process(["/usr/bin/osascript", "-e", "tell application \"Finder\" to empty trash"])])
        #expect(script(.logOut) == [.process(["/usr/bin/osascript", "-e", "tell application \"loginwindow\" to «event aevtrlgo»"])])
        #expect(script(.restart) == [.process(["/usr/bin/osascript", "-e", "tell application \"loginwindow\" to «event aevtrrst»"])])
        #expect(SystemAction.all.filter(\.confirm).map(\.id) == [.emptyTrash, .logOut, .restart, .shutDown])
    }

    @Test func failuresAreReported() throws {
        let (e, x) = ext()
        x.fail = "Not authorized to send Apple events to System Events."
        let r = try #require(e.handle(#"{"id":4,"type":"run","name":"perform","item":"toggleDarkMode","data":"toggleDarkMode"}"#))
        #expect(r.contains("Couldn't switch appearance: Not authorized to send Apple events to System Events."))
    }

    @Test func darkModeAndDisksSayWhatTheyWouldDo() {
        let (light, _) = ext()
        #expect(light.items(for: "dark mode", global: true, limit: 1).first?["subtitle"] as? String == "Dark Mode is off: switch to Dark")
        let (dark, _) = ext(dark: true)
        #expect(dark.items(for: "dark mode", global: true, limit: 1).first?["subtitle"] as? String == "Dark Mode is on: switch to Light")

        // Nothing to eject: quiet in normal search, said in keyword mode.
        #expect(light.items(for: "eject", global: true, limit: 3).isEmpty)
        let none = light.items(for: "eject", global: false, limit: 3).first
        #expect(none?["subtitle"] as? String == "No disks to eject")
        #expect(none?["actions"] == nil)
        #expect(throws: RunError.self) { try light.run("perform", item: "ejectAll") }
        let (disks, _) = ext(volumes: [Self.disk, Volume(name: "Stick", path: "/Volumes/Stick")])
        #expect(disks.items(for: "eject", global: true, limit: 3).first?["subtitle"] as? String == "Ejects Backup, Stick")
    }

    @Test func protocolReplies() throws {
        let (e, _) = ext()
        let out = try #require(e.handle(#"{"id":5,"type":"search","query":"lock","mode":"global","limit":3}"#))
        let o = try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        #expect(o["id"] as? Int == 5)
        let item = try #require((o["items"] as? [[String: Any]])?.first)
        #expect(item["icon"] as? String == "lock")
        #expect(try #require(e.handle(#"{"id":6,"type":"nope"}"#)).contains("unknown request type nope"))
        #expect(e.handle(#"{"type":"picked","item":"sleep","action":"run"}"#) == nil)
    }

    /// Looked up only: calling it would lock this Mac.
    @Test func theLockIsThere() {
        #expect(ScreenLock.isAvailable)
    }
}
