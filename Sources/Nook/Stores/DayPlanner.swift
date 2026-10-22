import Foundation

/// Pure scheduling logic for time blocking: free slots, "Plan my day", "Push rest of day",
/// snapping and the side-by-side layout of overlapping blocks. No store access, easy to test.
struct DayPlanner {
    static let defaultMinutes = 30
    static let minimumMinutes = 5
    static let snapMinutes = 15
    static let bufferMinutes = 5

    var calendar: Calendar = .current
    /// Working hours, in minutes since midnight.
    var workStart = 9 * 60
    var workEnd = 18 * 60
    var buffer = DayPlanner.bufferMinutes

    struct PlannedBlock: Equatable, Identifiable {
        var id: TaskItem.ID
        var start: Date
        var minutes: Int
        var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    // MARK: - Blocks

    /// Block length: the estimate, or 30 min when unset.
    static func minutes(for task: TaskItem) -> Int {
        max(task.estimateMinutes ?? defaultMinutes, minimumMinutes)
    }

    static func end(of task: TaskItem) -> Date? {
        task.scheduledStart.map { $0.addingTimeInterval(TimeInterval(minutes(for: task) * 60)) }
    }

    /// True when the task has no block that still matters: never scheduled, or scheduled on a past day.
    func needsBlock(_ task: TaskItem, now: Date) -> Bool {
        guard task.isOpen else { return false }
        guard let start = task.scheduledStart else { return true }
        return start < calendar.startOfDay(for: now)
    }

    // MARK: - Snapping and windows

    /// Snaps to the 15 min grid (nearest by default, or up to the next gridline).
    func snapped(_ date: Date, up: Bool = false) -> Date {
        let origin = calendar.startOfDay(for: date)
        let step = TimeInterval(Self.snapMinutes * 60)
        let steps = (date.timeIntervalSince(origin) / step)
        return origin.addingTimeInterval((up ? steps.rounded(.up) : steps.rounded()) * step)
    }

    func window(on day: Date) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        return DateInterval(
            start: start.addingTimeInterval(TimeInterval(workStart * 60)),
            end: start.addingTimeInterval(TimeInterval(workEnd * 60))
        )
    }

    // MARK: - Free slots

    private func busy(on day: Date, events: [AgendaEvent], tasks: [TaskItem], excluding: Set<UUID>) -> [DateInterval] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        var result: [DateInterval] = []
        for event in events where !event.isAllDay && event.end > event.start && event.end > dayStart && event.start < dayEnd {
            result.append(DateInterval(start: event.start, end: event.end))
        }
        for task in tasks where task.isOpen && !excluding.contains(task.id) {
            guard let start = task.scheduledStart, calendar.isDate(start, inSameDayAs: dayStart), let end = Self.end(of: task) else { continue }
            result.append(DateInterval(start: start, end: end))
        }
        return result
    }

    /// Gaps inside the working hours of `day` that no event or block occupies. `buffer` keeps that many
    /// minutes clear around every occupied span; `after` ignores everything before it.
    func freeSlots(
        on day: Date, events: [AgendaEvent], tasks: [TaskItem], after: Date? = nil,
        buffer: Int = 0, excluding: Set<UUID> = [], extraBusy: [DateInterval] = []
    ) -> [DateInterval] {
        let window = window(on: day)
        let lower = max(window.start, after ?? window.start)
        guard lower < window.end else { return [] }
        let pad = TimeInterval(buffer * 60)
        let spans = (busy(on: day, events: events, tasks: tasks, excluding: excluding) + extraBusy)
            .map { DateInterval(start: $0.start.addingTimeInterval(-pad), end: $0.end.addingTimeInterval(pad)) }
            .sorted { $0.start < $1.start }

        var gaps: [DateInterval] = []
        var cursor = lower
        for span in spans {
            if span.end <= cursor { continue }
            if span.start > cursor {
                let end = min(span.start, window.end)
                if end > cursor { gaps.append(DateInterval(start: cursor, end: end)) }
            }
            cursor = max(cursor, span.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end { gaps.append(DateInterval(start: cursor, end: window.end)) }
        return gaps
    }

    /// First snapped start inside `gaps` where `minutes` fit.
    func firstFit(minutes: Int, in gaps: [DateInterval]) -> Date? {
        let length = TimeInterval(minutes * 60)
        for gap in gaps {
            let start = snapped(gap.start, up: true)
            if start.addingTimeInterval(length) <= gap.end { return start }
        }
        return nil
    }

    /// Where a block of `minutes` can go at or after `after`, looking at today's remaining hours and then
    /// the next days' working hours. Used by "Skip".
    func nextFreeSlot(
        after: Date, minutes: Int, events: [AgendaEvent], tasks: [TaskItem],
        excluding: Set<UUID> = [], searchDays: Int = 3
    ) -> Date? {
        let first = calendar.startOfDay(for: after)
        for offset in 0..<searchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let gaps = freeSlots(on: day, events: events, tasks: tasks, after: offset == 0 ? after : nil, buffer: buffer, excluding: excluding)
            if let start = firstFit(minutes: minutes, in: gaps) { return start }
        }
        return nil
    }

    // MARK: - Plan my day

    /// Packs open, unscheduled tasks due by `day` into the free gaps: highest priority first, then list order.
    /// Today only uses time after `now`. Tasks that don't fit anywhere are left out.
    func planDay(on day: Date, tasks: [TaskItem], events: [AgendaEvent], now: Date) -> [PlannedBlock] {
        let candidates = tasks
            .filter { needsBlock($0, now: now) && $0.isDue(onOrBefore: day, calendar: calendar) }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                if a.order != b.order { return a.order < b.order }
                return a.createdAt < b.createdAt
            }
        let after: Date? = calendar.isDate(now, inSameDayAs: day) ? now : nil
        var placed: [PlannedBlock] = []
        for task in candidates {
            let minutes = Self.minutes(for: task)
            let extra = placed.map { DateInterval(start: $0.start, end: $0.end) }
            let gaps = freeSlots(on: day, events: events, tasks: tasks, after: after, buffer: buffer, extraBusy: extra)
            guard let start = firstFit(minutes: minutes, in: gaps) else { continue }
            placed.append(PlannedBlock(id: task.id, start: start, minutes: minutes))
        }
        return placed.sorted { $0.start < $1.start }
    }

    // MARK: - Push rest of day

    /// New starts for every open block of `day` that starts at or after `from`, shifted by `minutes`.
    func pushRest(on day: Date, tasks: [TaskItem], from: Date, by minutes: Int) -> [TaskItem.ID: Date] {
        var result: [TaskItem.ID: Date] = [:]
        for task in tasks where task.isOpen {
            guard let start = task.scheduledStart, calendar.isDate(start, inSameDayAs: day), start >= from else { continue }
            result[task.id] = start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        return result
    }

    /// Rounds a late-running overrun up to a multiple of 5 minutes (at least 5).
    static func roundedOverrun(_ interval: TimeInterval) -> Int {
        let minutes = Int((max(interval, 0) / 60).rounded(.up))
        return max(((minutes + 4) / 5) * 5, 5)
    }
}

// MARK: - Overlap layout

extension DayPlanner {
    struct Span: Identifiable, Equatable {
        var id: String
        var start: Date
        var end: Date
    }

    struct Placement: Equatable {
        var column: Int
        var columns: Int
    }

    /// Splits overlapping spans into side-by-side columns (like a calendar day view).
    static func columns(for spans: [Span]) -> [String: Placement] {
        var result: [String: Placement] = [:]
        var cluster: [(span: Span, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            for entry in cluster { result[entry.span.id] = Placement(column: entry.column, columns: max(columnEnds.count, 1)) }
            cluster = []
            columnEnds = []
        }

        for span in spans.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if span.start >= clusterEnd { flush() }
            let column = columnEnds.firstIndex { $0 <= span.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(span.end) } else { columnEnds[column] = span.end }
            cluster.append((span, column))
            clusterEnd = max(clusterEnd, span.end)
        }
        flush()
        return result
    }

    /// Ids of spans that overlap another span.
    static func overlapping(_ spans: [Span]) -> Set<String> {
        var result: Set<String> = []
        let sorted = spans.sorted { $0.start < $1.start }
        for (index, a) in sorted.enumerated() {
            for b in sorted[(index + 1)...] {
                if b.start >= a.end { break }
                result.insert(a.id)
                result.insert(b.id)
            }
        }
        return result
    }
}

// MARK: - Up next

struct UpNextItem: Identifiable, Equatable {
    var id: String
    var start: Date
    var end: Date
    var event: AgendaEvent?
    var task: TaskItem?

    func isCurrent(at now: Date) -> Bool { start <= now && end > now }

    /// The block in progress (if any) followed by the next `limit` events and task blocks.
    static func list(events: [AgendaEvent], blocks: [TaskItem], now: Date, limit: Int = 3) -> [UpNextItem] {
        var items: [UpNextItem] = []
        for event in events where !event.isAllDay && event.end > now {
            items.append(UpNextItem(id: "event-" + event.id, start: event.start, end: event.end, event: event, task: nil))
        }
        for task in blocks where task.isOpen {
            guard let start = task.scheduledStart, let end = DayPlanner.end(of: task), end > now else { continue }
            items.append(UpNextItem(id: "task-" + task.id.uuidString, start: start, end: end, event: nil, task: task))
        }
        items.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        let current = items.first { $0.isCurrent(at: now) && $0.task != nil } ?? items.first { $0.isCurrent(at: now) }
        let upcoming = items.filter { $0.start > now }.prefix(limit)
        return (current.map { [$0] } ?? []) + upcoming
    }
}
