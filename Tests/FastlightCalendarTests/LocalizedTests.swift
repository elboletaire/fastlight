import FastlightL10n
import FastlightPIM
import Foundation
import Testing
@testable import FastlightCalendar

/// The same dates and rows in Catalan and Spanish: whole phrases per
/// language, dates in that language, lowercase relative days inside them.
@Suite struct LocalizedCalendarTests {
    func cal(_ id: String) -> Calendar {
        var c = madrid
        c.locale = Locale(identifier: id)
        return c
    }

    func e(_ s: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: "x", title: "X", start: s, end: end, isAllDay: allDay)
    }

    @Test func catalan() {
        Localizer.$override.withValue(Localizer.named("ca")) {
            let t = DateText(calendar: cal("ca_ES"), now: nine)
            #expect(t.when(e(at(9, 0), at(10, 0), allDay: true)) == "Avui, tot el dia")
            #expect(t.when(e(at(9, 8, 30), at(9, 9, 15))) == "Ara, fins a les 9:15")
            #expect(t.when(e(at(8, 20), at(10, 8))) == "Ara, fins a demà, a les 8:00")
            #expect(t.when(e(at(7, 0), at(11, 0), allDay: true)) == "Fins a demà")
            // A named day takes the article; today and tomorrow don't.
            #expect(t.when(e(at(7, 0), at(13, 0), allDay: true)) == "Fins al dilluns")
            #expect(t.when(e(at(7, 0), at(10, 0), allDay: true)) == "Fins avui")
            #expect(t.when(e(at(8, 20), at(12, 10))) == "Ara, fins al dilluns, a les 10:00")
            #expect(t.when(e(at(12, 0), at(15, 0), allDay: true)) == "Dilluns – dimecres")
            #expect(t.due(Reminder(id: "a", title: "A", due: at(8, 0))) == "Vençut · Ahir")
            let none = RemindersExtension(source: FakeCalendar(), clock: fixedClock).items(for: "", global: false, limit: 5)
            #expect(titles(none) == ["No hi ha recordatoris"])
            let events = EventsExtension(source: FakeCalendar(), clock: fixedClock).items(for: "", global: false, limit: 5)
            #expect(subtitles(events) == ["No tens res als calendaris els pròxims 14 dies"])
            #expect(PIMDomain.reminders.accessItem(for: .notDetermined)?["title"] as? String == "Permet l’accés als recordatoris…")
        }
    }

    @Test func spanish() {
        Localizer.$override.withValue(Localizer.named("es")) {
            let t = DateText(calendar: cal("es_ES"), now: nine)
            #expect(t.when(e(at(10, 0), at(11, 0), allDay: true)) == "Mañana, todo el día")
            #expect(t.when(e(at(7, 0), at(11, 0), allDay: true)) == "Hasta mañana")
            #expect(t.when(e(at(7, 0), at(13, 0), allDay: true)) == "Hasta el lunes")
            #expect(t.when(e(at(7, 0), at(10, 0), allDay: true)) == "Hasta hoy")
            #expect(t.when(e(at(8, 20), at(10, 8))) == "Ahora, hasta mañana, a las 8:00")
            #expect(t.when(e(at(8, 20), at(12, 10))) == "Ahora, hasta el lunes, a las 10:00")
            #expect(t.due(Reminder(id: "a", title: "A", due: at(9, 8), dueHasTime: true)) == "Atrasado · Hoy, 8:00")
            #expect(PIMDomain.calendars.accessItem(for: .denied)?["subtitle"] as? String
                == "Activa Fastlight en Ajustes del Sistema › Privacidad y seguridad › Calendarios")
        }
    }

    @Test func datesSpeakFastlightsLanguage() {
        #expect(Clock.system(madrid, locale: Locale(identifier: "en_GB"), language: "ca").locale?.language.languageCode == "ca")
        let cal = Clock.system(madrid, locale: Locale(identifier: "ca_ES"), language: "en")
        #expect(cal.locale?.language.languageCode == .english)
        #expect(cal.locale?.region == "ES")
    }
}
