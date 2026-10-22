import Foundation
import Testing
@testable import Nook

struct CaptureParserTests {
    // Wednesday 2025-01-15 10:00 in Sao Paulo.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        c.firstWeekday = 2
        return c
    }()
    static let now = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10, minute: 0))!

    func parse(_ text: String) -> [TaskItem] {
        CaptureParser.parse(text, now: Self.now, calendar: Self.calendar)
    }

    func one(_ text: String) -> TaskItem {
        let tasks = parse(text)
        #expect(tasks.count == 1)
        return tasks.first ?? TaskItem(title: "")
    }

    func date(_ d: Int, _ h: Int? = nil, _ m: Int = 0, month: Int = 1, year: Int = 2025) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: d, hour: h ?? 0, minute: m))!
    }

    @Test func plainTitle() {
        let t = one("Buy milk")
        #expect(t.title == "Buy milk")
        #expect(t.due == nil)
        #expect(!t.hasTime)
        #expect(t.priority == .none)
        #expect(t.tags.isEmpty)
    }

    @Test func fullExample() {
        let t = one("call Ana tomorrow 3pm !high #work")
        #expect(t.title == "call Ana")
        #expect(t.due == date(16, 15))
        #expect(t.hasTime)
        #expect(t.priority == .high)
        #expect(t.tags == ["work"])
    }

    @Test func priorities() {
        #expect(one("a !!!").priority == .high)
        #expect(one("a !high").priority == .high)
        #expect(one("a !!").priority == .medium)
        #expect(one("a !med").priority == .medium)
        #expect(one("a !low").priority == .low)
        #expect(one("a !").priority == .low)
        #expect(one("!high a").title == "a")
        // Exclamation inside a word is not a priority.
        let t = one("Call Ana!")
        #expect(t.priority == .none)
        #expect(t.title == "Call Ana!")
    }

    @Test func tagsLowercasedAndDeduped() {
        let t = one("Plan trip #Travel #fun #travel")
        #expect(t.tags == ["travel", "fun"])
        #expect(t.title == "Plan trip")
    }

    @Test func splitsOnNewlinesAndSemicolons() {
        let tasks = parse("Buy milk; call mom tomorrow\nwrite report !low\n\n  ")
        #expect(tasks.map(\.title) == ["Buy milk", "call mom", "write report"])
        #expect(tasks[1].due == date(16))
        #expect(tasks[2].priority == .low)
    }

    @Test func doesNotSplitOnCommas() {
        let tasks = parse("Buy eggs, milk, bread")
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Buy eggs, milk, bread")
    }

    @Test func stripsListMarkers() {
        let tasks = parse("- one\n* two\n1. three\n[ ] four")
        #expect(tasks.map(\.title) == ["one", "two", "three", "four"])
    }

    @Test func emptyInput() {
        #expect(parse("").isEmpty)
        #expect(parse("   \n ; ").isEmpty)
        #expect(parse("!high #work").isEmpty)
    }

    @Test func today() {
        let t = one("Pay rent today")
        #expect(t.title == "Pay rent")
        #expect(t.due == date(15))
        #expect(!t.hasTime)
    }

    @Test func hoje() {
        let t = one("Pagar aluguel hoje")
        #expect(t.title == "Pagar aluguel")
        #expect(t.due == date(15))
    }

    @Test func tomorrowAndAmanha() {
        #expect(one("Dentist tomorrow").due == date(16))
        #expect(one("Dentista amanhã").due == date(16))
        let t = one("Dentista amanha")
        #expect(t.due == date(16))
        #expect(t.title == "Dentista")
    }

    @Test func dayAfterTomorrow() {
        #expect(one("Trip day after tomorrow").due == date(17))
        #expect(one("Viagem depois de amanhã").due == date(17))
    }

    @Test func weekdaysEnglish() {
        // now is Wednesday the 15th
        #expect(one("Gym friday").due == date(17))
        #expect(one("Gym on mon").due == date(20))
        #expect(one("Gym next monday").due == date(20))
        #expect(one("Gym Thursday").due == date(16))
        // Same weekday -> next week.
        #expect(one("Review wed").due == date(22))
        #expect(one("Review wed").title == "Review")
        #expect(one("Hike sun").due == date(19))
        #expect(one("Hike saturday").due == date(18))
    }

    @Test func weekdaysPortuguese() {
        #expect(one("Reunião seg").due == date(20))
        #expect(one("Reunião na sexta").due == date(17))
        #expect(one("Reunião na sexta").title == "Reunião")
        #expect(one("Dentista terça-feira").due == date(21))
        #expect(one("Dentista quinta").due == date(16))
        #expect(one("Churrasco sábado").due == date(18))
        #expect(one("Almoço domingo").due == date(19))
        #expect(one("Aula qua").due == date(22))
    }

    @Test func portugueseTer() {
        // "ter" (to have) must not be treated as a weekday.
        let t = one("Preciso ter cuidado")
        #expect(t.due == nil)
        #expect(t.title == "Preciso ter cuidado")
    }

    @Test func timeAmPm() {
        let t = one("Standup at 9:30am tomorrow")
        #expect(t.due == date(16, 9, 30))
        #expect(t.hasTime)
        #expect(t.title == "Standup")
        #expect(one("Lunch tomorrow 12pm").due == date(16, 12))
        #expect(one("Sleep tomorrow 12am").due == date(16, 0))
        #expect(one("Call tomorrow 3 PM").due == date(16, 15))
    }

    @Test func time24h() {
        #expect(one("Reunião amanhã 15h").due == date(16, 15))
        #expect(one("Reunião amanhã às 15:30").due == date(16, 15, 30))
        #expect(one("Reunião amanhã 15h30").due == date(16, 15, 30))
        let t = one("Reunião hoje às 15h")
        #expect(t.title == "Reunião")
        #expect(t.hasTime)
        #expect(one("Meeting tomorrow at 14:05").due == date(16, 14, 5))
    }

    @Test func bareHourWithPreposition() {
        #expect(one("Reunião amanhã às 15").due == date(16, 15))
        #expect(one("Call Ana tomorrow at 3").due == date(16, 15))
        #expect(one("Call Ana tomorrow at 9").due == date(16, 9))
    }

    @Test func timeWithoutDayUsesNextOccurrence() {
        // now = 10:00
        let later = one("Call at 3pm")
        #expect(later.due == date(15, 15))
        #expect(later.hasTime)
        #expect(later.title == "Call")
        let passed = one("Call at 9am")
        #expect(passed.due == date(16, 9))
    }

    @Test func relativeHoursAndMinutes() {
        let h = one("Check oven in 2 hours")
        #expect(h.due == Self.now.addingTimeInterval(7200))
        #expect(h.hasTime)
        #expect(h.title == "Check oven")
        let pt = one("Tirar do forno em 30 minutos")
        #expect(pt.due == Self.now.addingTimeInterval(1800))
        #expect(pt.title == "Tirar do forno")
        #expect(one("Ligar em 2 horas").due == Self.now.addingTimeInterval(7200))
        #expect(one("Ping in 1h").due == Self.now.addingTimeInterval(3600))
        #expect(one("Ping in an hour").due == Self.now.addingTimeInterval(3600))
    }

    @Test func relativeDays() {
        let t = one("Follow up in 3 days")
        #expect(t.due == date(18))
        #expect(!t.hasTime)
        #expect(one("Revisar em 2 semanas").due == date(29))
        #expect(one("Follow up in 3 days at 4pm").due == date(18, 16))
    }

    @Test func explicitDateViaDetector() {
        let t = one("Renew passport December 25 2030")
        #expect(t.due == date(25, month: 12, year: 2030))
        #expect(!t.hasTime)
        #expect(t.title == "Renew passport")
        let timed = one("Party December 25 2030 at 8pm")
        #expect(timed.due == date(25, 20, month: 12, year: 2030))
        #expect(timed.hasTime)
    }

    @Test func danglingPrepositionsTrimmed() {
        #expect(one("Pay rent on friday").title == "Pay rent")
        #expect(one("Reunião às 15h hoje").title == "Reunião")
        #expect(one("Ligar para Ana de amanhã").title == "Ligar para Ana")
        #expect(one("Finish report by tomorrow").title == "Finish report")
        #expect(one("Finish report, tomorrow").title == "Finish report")
    }

    @Test func digitsInTitleAreLeftAlone() {
        let t = one("Buy 3 apples")
        #expect(t.title == "Buy 3 apples")
        #expect(t.due == nil)
    }

    @Test func wordsContainingKeywordsAreLeftAlone() {
        let t = one("Read about monopolies and sundaes")
        #expect(t.due == nil)
        #expect(t.title == "Read about monopolies and sundaes")
    }

    @Test func brainDumpWithEverything() {
        let tasks = parse("""
        email João amanhã 9h !med #work
        comprar pão; ligar pra mãe sexta !!! #família
        """)
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "email João")
        #expect(tasks[0].due == date(16, 9))
        #expect(tasks[0].priority == .medium)
        #expect(tasks[0].tags == ["work"])
        #expect(tasks[1].title == "comprar pão")
        #expect(tasks[2].title == "ligar pra mãe")
        #expect(tasks[2].due == date(17))
        #expect(tasks[2].priority == .high)
        #expect(tasks[2].tags == ["família"])
    }
}
