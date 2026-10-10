import FastlightPIM
import Foundation
import Testing

/// A clock the test moves by hand.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { t } }

    func advance(_ s: TimeInterval) {
        lock.withLock { t = t.addingTimeInterval(s) }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var fail = false

    func next() -> Int? {
        lock.withLock {
            if fail { return nil }
            n += 1
            return n
        }
    }
}

@Suite struct LoaderTests {
    @Test func readsOnceAndAgainWhenStale() {
        let clock = ManualClock()
        let counter = Counter()
        let loader = Loader(now: { clock.now }) { counter.next() }
        #expect(loader.cached == nil)
        #expect(loader.get(maxAge: 60, wait: 2) == 1)
        #expect(loader.get(maxAge: 60, wait: 2) == 1) // fresh: not read again
        clock.advance(61)
        #expect(loader.get(maxAge: 60, wait: 2) == 2)
    }

    @Test func keepsTheOldValueWhenAReadFails() {
        let clock = ManualClock()
        let counter = Counter()
        let loader = Loader(now: { clock.now }) { counter.next() }
        #expect(loader.get(maxAge: 60, wait: 2) == 1)
        counter.fail = true
        clock.advance(120)
        #expect(loader.get(maxAge: 60, wait: 2) == 1)
        loader.reset()
        #expect(loader.cached == nil)
        #expect(loader.get(maxAge: 60, wait: 2) == nil)
    }

    /// The read is held until the test lets it go, so returning at all
    /// means the wait ran out, however slow the machine.
    @Test func waitsNoLongerThanAsked() {
        let release = DispatchSemaphore(value: 0)
        let loader = Loader<Int> {
            _ = release.wait(timeout: .now() + 30)
            return 1
        }
        let started = Date()
        #expect(loader.get(maxAge: 60, wait: 0.02) == nil)
        // Nowhere near the read's 30 s, on any load.
        #expect(Date().timeIntervalSince(started) < 10)
        // The read goes on in the background.
        release.signal()
        #expect(loader.get(maxAge: 60, wait: 30) == 1)
    }
}

@Suite struct PIMTests {
    @Test func foldsCaseAccentsAndJoinedWords() {
        #expect(Fold.text("José MÜLLER") == "jose muller")
        #expect(Fold.words("Jean-Luc O'Brien") == ["jean", "luc", "jeanluc", "o", "brien", "obrien"])
        #expect(Fold.words("  ") == [])
    }

    @Test func settingsPanes() {
        #expect(PIMDomain.contacts.settingsURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")
        #expect(PIMDomain.calendars.settingsURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #expect(PIMDomain.reminders.settingsURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
    }

    @Test func accessItems() {
        let d = PIMDomain.calendars
        #expect(d.accessItem(for: .authorized) == nil)
        #expect(d.accessItem(for: .notDetermined)?["title"] as? String == "Allow Access to Calendars…")
        #expect(d.accessItem(for: .denied)?["title"] as? String == "Access to Calendars Is Off")
        #expect(d.accessItem(for: .writeOnly)?["title"] as? String == "Fastlight Can't Read Calendars")
        #expect(d.accessItem(for: .restricted)?["title"] as? String == "Access to Calendars Is Restricted")
        for a in Access.allCases where a != .authorized {
            #expect(d.accessItem(for: a)?["actions"] != nil)
        }
    }

    @Test func sampleAccessComesFromAFile() throws {
        #expect(SampleAccess(file: nil).access == .authorized)
        #expect(SampleAccess(file: "/nonexistent").access == .authorized)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("access-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try "denied\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(SampleAccess(file: file.path).access == .denied)
        try "bogus".write(to: file, atomically: true, encoding: .utf8)
        #expect(SampleAccess(file: file.path).access == .authorized)
    }

    @Test func requests() throws {
        let r = try #require(PIMRequest(#"{"id":1,"type":"search","query":"x","mode":"global","limit":900}"#))
        #expect(r.id == 1)
        #expect(r.global)
        #expect(r.limit == 200)
        #expect(PIMRequest(#"{"type":"picked"}"#)?.id == nil)
        #expect(PIMRequest("[1]") == nil)
    }
}
