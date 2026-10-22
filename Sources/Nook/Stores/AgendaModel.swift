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
    @ObservationIgnored private var alerted: Set<String> = []
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var changeObserver: Any?

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
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func reload() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                AgendaEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.map { Color(nsColor: $0.color) } ?? .accent,
                    location: event.location,
                    url: event.url
                )
            }
        tick()
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
        now = date
        let lead = TimeInterval(alertMinutes() * 60)
        for event in events where !event.isAllDay && !alerted.contains(event.id) {
            let until = event.start.timeIntervalSince(date)
            guard until > 0, until <= lead else { continue }
            alerted.insert(event.id)
            let minutes = max(Int((until / 60).rounded()), 1)
            onAlert?(NotchAlert(
                kind: .eventSoon, symbol: "calendar", tint: event.color,
                headline: event.title, detail: "Starts in \(minutes) min" + (event.location.map { " · \($0)" } ?? "")
            ))
        }
    }
}
