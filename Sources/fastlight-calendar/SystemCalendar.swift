import EventKit
import FastlightCalendar
import FastlightPIM
import Foundation

/// Calendar and Reminders through EventKit. Read-only: nothing here saves,
/// removes or commits.
///
/// This process is started by Fastlight, so macOS attributes the access to
/// Fastlight (the "responsible" app): the prompts name Fastlight, use its
/// NSCalendarsFullAccessUsageDescription and
/// NSRemindersFullAccessUsageDescription, and the switches are Fastlight's in
/// System Settings › Privacy & Security.
final class SystemCalendar: CalendarSource, @unchecked Sendable {
    private let lock = NSLock()
    /// Made only once access is on: a store made before the grant doesn't
    /// see anything, even afterwards.
    private var store: EKEventStore?
    private var storeAccess: [EKEntityType: Bool] = [:]

    static func entity(_ kind: CalendarKind) -> EKEntityType { kind == .events ? .event : .reminder }

    func access(_ kind: CalendarKind) -> Access {
        switch EKEventStore.authorizationStatus(for: Self.entity(kind)) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .authorized
        @unknown default: .denied
        }
    }

    func requestAccess(_ kind: CalendarKind, _ done: @escaping @Sendable (Bool) -> Void) {
        let s = EKEventStore()
        let finish: @Sendable (Bool, Error?) -> Void = { [weak self] granted, error in
            if let error { FileHandle.standardError.write(Data("fastlight-calendar: \(error.localizedDescription)\n".utf8)) }
            // Start over with a store that sees what was just allowed.
            if granted { self?.lock.withLock { self?.store = nil } }
            done(granted)
        }
        if kind == .events {
            s.requestFullAccessToEvents(completion: finish)
        } else {
            s.requestFullAccessToReminders(completion: finish)
        }
    }

    private func eventStore() -> EKEventStore {
        lock.withLock {
            if let store { return store }
            let s = EKEventStore()
            store = s
            return s
        }
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        let store = eventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { e in
            CalendarEvent(id: e.calendarItemIdentifier,
                          title: e.title ?? "",
                          start: e.startDate,
                          end: e.endDate,
                          isAllDay: e.isAllDay,
                          location: e.location ?? "",
                          calendar: e.calendar?.title ?? "",
                          notes: e.notes ?? "",
                          recurring: e.hasRecurrenceRules)
        }
    }

    func reminders() throws -> [Reminder] {
        let store = eventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: predicate) { found in
            box.list = (found ?? []).map { r in
                let comps = r.dueDateComponents
                return Reminder(id: r.calendarItemIdentifier,
                                title: r.title ?? "",
                                due: comps.flatMap { c in (c.calendar ?? Calendar.current).date(from: c) },
                                dueHasTime: comps?.hour != nil,
                                priority: r.priority,
                                list: r.calendar?.title ?? "",
                                notes: r.notes ?? "",
                                created: r.creationDate)
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + 5) == .success else { throw CocoaError(.fileReadUnknown) }
        return box.list
    }

    private final class Box: @unchecked Sendable {
        var list: [Reminder] = []
    }
}
