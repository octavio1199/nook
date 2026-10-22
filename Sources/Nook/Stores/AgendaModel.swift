import EventKit
import Observation
import SwiftUI

@Observable
final class AgendaModel {
    enum Access: Equatable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var events: [AgendaEvent] = []
    private(set) var now = Date()

    @ObservationIgnored var onAlert: ((NotchAlert) -> Void)?
    @ObservationIgnored var alertMinutes: () -> Int = { 5 }

    @ObservationIgnored private let store = EKEventStore()
    /// Occurrence key -> occurrence start. Keyed per occurrence so a recurring event alerts every time.
    @ObservationIgnored private var alerted: [String: Date] = [:]
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: Any)] = []
    @ObservationIgnored private var loadedDay = Date()

    init() {
        access = Self.currentAccess
        if access == .granted { start() }
    }

    private static var currentAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    /// Ask lazily, the first time the user opts in from the Agenda card.
    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            if granted { start() }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func start() {
        reload()
        func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil) {
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
            observers.append((center, token))
        }
        observe(.default, .EKEventStoreChanged, object: store)
        observe(.default, .NSCalendarDayChanged)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func reload() {
        load()
        tick()
    }

    private func load() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        loadedDay = start
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { Self.isVisible($0) }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                AgendaEvent(
                    id: Self.occurrenceID(event.eventIdentifier ?? "\(event.title ?? "")", start: event.startDate),
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.map { Color(nsColor: $0.color) } ?? .accent,
                    location: event.location,
                    url: event.url,
                    joinURL: AgendaEvent.meetingLink(in: [event.url?.absoluteString, event.location, event.notes])
                )
            }
    }

    /// Cancelled events and ones the user declined never show up or alert.
    private static func isVisible(_ event: EKEvent) -> Bool {
        if event.status == .canceled { return false }
        let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        return !declined
    }

    /// Recurring events share one `eventIdentifier`; the start date makes each occurrence unique.
    nonisolated static func occurrenceID(_ identifier: String, start: Date) -> String {
        "\(identifier)|\(Int(start.timeIntervalSince1970))"
    }

    var today: [AgendaEvent] {
        events.filter { Calendar.current.isDateInToday($0.start) || ($0.start < now && $0.end > now) }
    }

    var tomorrow: [AgendaEvent] {
        events.filter { Calendar.current.isDateInTomorrow($0.start) }
    }

    /// The next timed event starting within 10 minutes, for the live activity wing.
    var startingSoon: AgendaEvent? {
        events.first { !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= 600 }
    }

    func tick(at date: Date = Date()) {
        if access == .granted, !Calendar.current.isDate(date, inSameDayAs: loadedDay), Calendar.current.isDate(Date(), inSameDayAs: date) {
            load() // the day rolled over (or the Mac slept through midnight)
        }
        now = date
        alerted = alerted.filter { $0.value > date.addingTimeInterval(-86_400) }
        let lead = TimeInterval(alertMinutes() * 60)
        for event in events where !event.isAllDay && alerted[event.id] == nil {
            let until = event.start.timeIntervalSince(date)
            guard until > 0, until <= lead else { continue }
            alerted[event.id] = event.start
            let minutes = max(Int((until / 60).rounded()), 1)
            onAlert?(NotchAlert(
                kind: .eventSoon, symbol: "calendar", tint: event.color,
                headline: event.title, detail: "Starts in \(minutes) min" + (event.location.map { " · \($0)" } ?? "")
            ))
        }
    }
}
