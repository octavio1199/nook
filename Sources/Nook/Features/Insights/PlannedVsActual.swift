import SwiftUI

/// Today's plan against what actually happened: per scheduled task, estimate vs tracked focus time.
struct PlannedVsActual: Equatable {
    struct Row: Identifiable, Equatable {
        var id: UUID
        var title: String
        var plannedMinutes: Int
        var actual: TimeInterval
        var done: Bool
        var overran: Bool { actual > TimeInterval(plannedMinutes * 60) + 60 }
    }

    var rows: [Row] = []

    init(tasks: [TaskItem], sessions: [FocusSession], now: Date = Date(), calendar: Calendar = .current) {
        var actualByTask: [UUID: TimeInterval] = [:]
        for session in sessions where calendar.isDate(session.start, inSameDayAs: now) {
            guard let id = session.taskID else { continue }
            actualByTask[id, default: 0] += session.duration
        }
        rows = tasks
            .filter { $0.archivedAt == nil && $0.scheduledStart.map { calendar.isDate($0, inSameDayAs: now) } == true }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
            .map { Row(id: $0.id, title: $0.title, plannedMinutes: DayPlanner.minutes(for: $0), actual: actualByTask[$0.id] ?? 0, done: $0.done) }
    }

    var plannedTotal: Int { rows.reduce(0) { $0 + $1.plannedMinutes } }
    var actualTotal: TimeInterval { rows.reduce(0) { $0 + $1.actual } }
}

struct PlannedVsActualList: View {
    var plan: PlannedVsActual

    var body: some View {
        if plan.rows.isEmpty {
            Text("Give tasks a time in the Day tab and compare them with your focus here.")
                .font(Typography.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let scale = max(plan.rows.map { max(TimeInterval($0.plannedMinutes * 60), $0.actual) }.max() ?? 1, 1)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 7) {
                    ForEach(plan.rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(row.title)
                                    .font(Typography.caption)
                                    .foregroundStyle(row.done ? Color.textSecondary : Color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(TaskTime.text(TimeInterval(row.plannedMinutes * 60))) → \(row.actual >= TaskTime.minimum ? TaskTime.text(row.actual) : "–")")
                                    .font(Typography.micro)
                                    .monospacedDigit()
                                    .foregroundStyle(row.overran ? Color.accent : Color.textSecondary)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.surfaceRaised)
                                        .frame(width: max(proxy.size.width * TimeInterval(row.plannedMinutes * 60) / scale, 3))
                                    Capsule().fill(row.overran ? Color.accent : Color.focus.opacity(row.done ? 0.5 : 0.85))
                                        .frame(width: row.actual > 0 ? max(proxy.size.width * row.actual / scale, 3) : 0)
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
