import Charts
import SwiftUI

struct InsightsView: View {
    @Environment(PlannerStore.self) private var planner
    /// nil = automatic: "Planned vs actual" whenever today has time blocks.
    @LocalState private var showPlan: Bool?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let summary = InsightsSummary(tasks: planner.tasks, sessions: planner.sessions, now: context.date)
            let plan = PlannedVsActual(tasks: planner.tasks, sessions: planner.sessions, now: context.date)
            let planMode = showPlan ?? !plan.rows.isEmpty
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(symbol: "checkmark.circle.fill", tint: .rest, value: "\(summary.tasksDoneToday)", label: "Tasks done today")
                    StatTile(symbol: "timer", tint: .focus, value: "\(summary.focusMinutesToday)", unit: "min", label: "Focus today")
                    StatTile(symbol: "flame.fill", tint: .accent, value: "\(summary.streak)", unit: summary.streak == 1 ? "day" : "days", label: "Current streak")
                    StatTile(symbol: "clock.fill", tint: .focus, value: Self.hours(summary.focusHoursThisWeek), unit: "h", label: "Focus, last 7 days")
                }
                .frame(height: 78)

                HStack(spacing: 10) {
                    Card("Last 7 days", symbol: "chart.bar.xaxis", trailing: AnyView(Legend())) {
                        HStack(alignment: .top, spacing: 14) {
                            WeekChart(days: summary.days)
                            VStack(alignment: .leading, spacing: 10) {
                                Highlight(symbol: "star.fill", title: "Best day", value: Self.bestDay(summary))
                                Highlight(symbol: "sun.max.fill", title: "Most focused hour", value: Self.hour(summary.mostFocusedHour))
                            }
                            .frame(width: 150, alignment: .leading)
                        }
                    }
                    Card(planMode ? "Planned today" : "Time per task", symbol: planMode ? "calendar.day.timeline.left" : "stopwatch",
                         trailing: AnyView(modeToggle(planMode))) {
                        if planMode {
                            PlannedVsActualList(plan: plan)
                        } else {
                            TaskTimeList(totals: summary.taskTimes)
                        }
                    }
                    .frame(width: 270)
                }
            }
        }
    }

    private func modeToggle(_ planMode: Bool) -> some View {
        HStack(spacing: 2) {
            toggleButton("stopwatch", selected: !planMode, help: "Time per task, last 7 days") { showPlan = false }
            toggleButton("calendar.day.timeline.left", selected: planMode, help: "Planned vs actual, today") { showPlan = true }
        }
    }

    private func toggleButton(_ symbol: String, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(selected ? Color.textPrimary : Color.textTertiary)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(selected ? Color.surfaceRaised : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func hours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 && value.truncatingRemainder(dividingBy: 1) != 0 ? 1 : 0)))
    }

    static func bestDay(_ summary: InsightsSummary) -> String {
        guard let day = summary.bestDay else { return "No activity yet" }
        let name = day.date.formatted(.dateTime.weekday(.wide))
        return "\(name) · \(day.focusMinutes) min, \(day.tasksDone) \(day.tasksDone == 1 ? "task" : "tasks")"
    }

    static func hour(_ hour: Int?) -> String {
        guard let hour else { return "No focus sessions yet" }
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        let end = start.addingTimeInterval(3600)
        let format = Date.FormatStyle.dateTime.hour()
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }
}

private struct StatTile: View {
    var symbol: String
    var tint: Color
    var value: String
    var unit: String?
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Color.textPrimary)
                if let unit { Text(unit).font(Typography.caption).foregroundStyle(Color.textSecondary) }
            }
            Text(label).font(Typography.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline))
        .accessibilityElement(children: .combine)
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            item(.focus, "Focus min")
            item(.rest, "Tasks done")
        }
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(Typography.micro).foregroundStyle(Color.textSecondary)
        }
    }
}

private struct Highlight: View {
    var symbol: String
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title.uppercased(), systemImage: symbol)
                .font(Typography.micro).tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text(value).font(Typography.body).foregroundStyle(Color.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WeekChart: View {
    var days: [InsightsSummary.Day]

    private struct Point: Identifiable {
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
        var date: Date
        var series: String
        var value: Int
    }

    private var points: [Point] {
        days.flatMap { [Point(date: $0.date, series: "Focus min", value: $0.focusMinutes), Point(date: $0.date, series: "Tasks done", value: $0.tasksDone)] }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                .foregroundStyle(by: .value("Series", point.series))
                .position(by: .value("Series", point.series))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(["Focus min": Color.focus, "Tasks done": Color.rest])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(Color.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel().foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Top tasks of the week by focus time: title, duration and a bar relative to the longest.
struct TaskTimeList: View {
    var totals: [InsightsSummary.TaskTotal]

    var body: some View {
        if totals.isEmpty {
            Text("Focus on a task and its time shows up here.")
                .font(Typography.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let longest = max(totals.map(\.duration).max() ?? 1, 1)
            VStack(spacing: 7) {
                ForEach(totals) { total in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(total.title)
                                .font(Typography.caption)
                                .foregroundStyle(total.done ? Color.textSecondary : Color.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(TaskTime.text(total.duration))
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color.textSecondary)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Color.focus.opacity(total.done ? 0.45 : 0.85))
                                .frame(width: max(proxy.size.width * total.duration / longest, 3))
                        }
                        .frame(height: 3)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
