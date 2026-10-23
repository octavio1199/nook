import SwiftUI

/// Block colors: priority, with a calm blue-gray for tasks that have none.
enum DayPalette {
    static func tint(_ priority: TaskItem.Priority) -> Color {
        priority == .none ? Color(red: 0.55, green: 0.62, blue: 0.82) : priority.tint
    }
    static let warning = Color(red: 1.0, green: 0.8, blue: 0.25)
}

/// The Day tab: unscheduled tasks on the left, the day's timeline on the right.
struct DayView: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(AgendaModel.self) private var agenda
    @Environment(NotchInteraction.self) private var notch
    @Environment(BlockWatcher.self) private var blocks
    @LocalState private var preview: [DayPlanner.PlannedBlock]?
    @LocalState private var notice: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: notch.dayOffset, to: calendar.startOfDay(for: now)) ?? now
        let dp = blocks.dayPlanner
        let unscheduled = planner.todayTasks(now: day).filter { dp.needsBlock($0, now: now) }
        let past = notch.dayOffset < 0
        let scheduled = past ? [] : planner.scheduledTasks(on: day)
        let sessions = past ? planner.sessions(on: day) : []

        return HStack(alignment: .top, spacing: 10) {
            if past {
                Card("Log time", symbol: "clock.arrow.circlepath") {
                    PastDayList(day: day, sessions: sessions)
                }
                .frame(width: 236)
            } else {
            Card("Unscheduled", symbol: "tray", trailing: AnyView(countBadge(unscheduled.count))) {
                VStack(spacing: 8) {
                    UnscheduledList(tasks: unscheduled, preview: preview ?? [])
                    PlanControls(
                        preview: preview, notice: notice, offset: notch.dayOffset,
                        canPlan: !unscheduled.isEmpty,
                        plan: { makePlan(day: day, now: now) },
                        apply: apply,
                        cancel: { withAnimation(Motion.navigate) { preview = nil } }
                    )
                }
            }
            .frame(width: 236)
            }

            Card(title(for: day), symbol: past ? "clock.arrow.circlepath" : "calendar.day.timeline.left",
                 trailing: AnyView(DayNav(summary: past ? loggedSummary(sessions) : summary(scheduled)))) {
                DayTimeline(
                    day: day, now: now,
                    events: agenda.access == .granted && !past ? agenda.events : [],
                    tasks: scheduled, preview: preview ?? [], dayPlanner: dp,
                    sessions: sessions, logging: past
                )
            }
        }
        .onChange(of: notch.dayOffset) { _, _ in preview = nil; notice = nil }
        .onAppear { if DayDemo.autoPlan, preview == nil { makePlan(day: day, now: now) } }
    }

    private func title(for day: Date) -> String {
        let name = switch notch.dayOffset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: day.formatted(.dateTime.weekday(.wide))
        }
        return "\(name) · \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private func summary(_ scheduled: [TaskItem]) -> String? {
        guard !scheduled.isEmpty else { return nil }
        let minutes = scheduled.reduce(0) { $0 + DayPlanner.minutes(for: $1) }
        return "\(TaskTime.text(TimeInterval(minutes * 60))) planned"
    }

    private func loggedSummary(_ sessions: [FocusSession]) -> String? {
        let total = sessions.reduce(0) { $0 + $1.duration }
        guard total >= 60 else { return nil }
        return TaskTime.text(total)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)").font(Typography.micro).foregroundStyle(Color.textTertiary)
    }

    private func makePlan(day: Date, now: Date) {
        let plan = blocks.dayPlanner.planDay(on: day, tasks: planner.tasks, events: agenda.access == .granted ? agenda.events : [], now: now)
        guard !plan.isEmpty else {
            notice = "Nothing fits in the free time left"
            Task {
                try? await Task.sleep(for: .seconds(3))
                notice = nil
            }
            return
        }
        notice = nil
        withAnimation(Motion.navigate) { preview = plan }
    }

    private func apply() {
        guard let plan = preview else { return }
        let starts = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, Date?.some($0.start)) })
        withAnimation(Motion.navigate) {
            planner.applySchedule(starts, action: "Plan My Day")
            preview = nil
        }
    }
}

private struct DayNav: View {
    var summary: String?
    @Environment(NotchInteraction.self) private var notch

    var body: some View {
        HStack(spacing: 6) {
            if notch.dayOffset < 0 {
                Label("Logging past day", systemImage: "pencil")
                    .font(Typography.micro)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.accent.opacity(0.14)))
                    .fixedSize()
            }
            if let summary {
                Text(summary).font(Typography.micro).foregroundStyle(Color.textTertiary)
            }
            if notch.dayOffset != 0 {
                Button { notch.shiftDay(by: -notch.dayOffset) } label: {
                    Text("Today")
                        .font(Typography.micro)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.surfaceRaised))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            button("chevron.left", enabled: notch.dayOffset > NotchInteraction.minDayOffset, help: "Previous day (←)") { notch.shiftDay(by: -1) }
            button("chevron.right", enabled: notch.dayOffset < NotchInteraction.maxDayOffset, help: "Next day (→)") { notch.shiftDay(by: 1) }
        }
    }

    private func button(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Color.textPrimary : Color.textTertiary)
                .frame(width: 22, height: 20)
                .background(Capsule().fill(Color.surfaceRaised))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Unscheduled list

private struct UnscheduledList: View {
    var tasks: [TaskItem]
    var preview: [DayPlanner.PlannedBlock]

    var body: some View {
        if tasks.isEmpty {
            Text("Every open task for this day has a time.")
                .font(Typography.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(tasks) { task in
                        UnscheduledRow(task: task, plannedStart: preview.first { $0.id == task.id }?.start)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct UnscheduledRow: View {
    let task: TaskItem
    var plannedStart: Date?
    @Environment(PlannerStore.self) private var planner

    private static let options = [15, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: 7) {
            Capsule().fill(DayPalette.tint(task.priority)).frame(width: 3, height: 16)
            Text(task.title)
                .font(Typography.caption)
                .foregroundStyle(plannedStart == nil ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let plannedStart {
                Text(plannedStart.formatted(.dateTime.hour().minute()))
                    .font(Typography.micro).monospacedDigit()
                    .foregroundStyle(Color.accent)
            } else {
                estimateMenu
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(plannedStart == nil ? Color.hairline : Color.accent.opacity(0.5)))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .draggable(task.id.uuidString) { DragChip(title: task.title, minutes: DayPlanner.minutes(for: task)) }
        .help("Drag onto the timeline to give it a time")
    }

    private var estimateMenu: some View {
        Menu {
            ForEach(Self.options, id: \.self) { minutes in
                Button(TaskTime.text(TimeInterval(minutes * 60))) { planner.setEstimate(minutes, for: task.id) }
            }
            if task.estimateMinutes != nil {
                Divider()
                Button("Clear estimate") { planner.setEstimate(nil, for: task.id) }
            }
        } label: {
            Text(TaskTime.text(TimeInterval(DayPlanner.minutes(for: task) * 60)))
                .font(Typography.micro).monospacedDigit()
                .foregroundStyle(task.estimateMinutes == nil ? Color.textTertiary : Color.textPrimary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.surfaceRaised))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Estimate: sets the block length")
    }
}

private struct DragChip: View {
    var title: String
    var minutes: Int

    var body: some View {
        Text("\(title) · \(TaskTime.text(TimeInterval(minutes * 60)))")
            .font(Typography.caption)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.accent.opacity(0.9)))
    }
}

// MARK: - Plan my day

private struct PlanControls: View {
    var preview: [DayPlanner.PlannedBlock]?
    var notice: String?
    var offset: Int
    var canPlan: Bool
    var plan: () -> Void
    var apply: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let preview {
                let minutes = preview.reduce(0) { $0 + $1.minutes }
                Text("\(preview.count) \(preview.count == 1 ? "block" : "blocks") · \(TaskTime.text(TimeInterval(minutes * 60)))")
                    .font(Typography.caption).foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    pill("Cancel", filled: false, action: cancel)
                    pill("Apply", filled: true, action: apply)
                }
            } else {
                if let notice {
                    Text(notice).font(Typography.micro).foregroundStyle(Color.textTertiary)
                }
                Button(action: plan) {
                    Label(offset == 0 ? "Plan my day" : "Plan tomorrow", systemImage: "wand.and.stars")
                        .font(Typography.caption)
                        .foregroundStyle(canPlan ? Color.black.opacity(0.85) : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Capsule().fill(canPlan ? Color.accent : Color.surface))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canPlan)
            }
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(filled ? Color.black.opacity(0.85) : Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Capsule().fill(filled ? Color.accent : Color.surfaceRaised))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Past days

/// Tasks you can log time against on a past day: what was done that day, then what's still open.
enum PastDay {
    static func candidates(tasks: [TaskItem], day: Date, calendar: Calendar = .current) -> [TaskItem] {
        let doneThatDay = tasks.filter { task in
            task.done && task.archivedAt == nil && task.completedAt.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
        let open = tasks.filter(\.isOpen).sorted { $0.order < $1.order }
        return doneThatDay + open
    }

    /// Focus logged against each task that day (timer and manual), for the list.
    static func minutes(on sessions: [FocusSession]) -> [UUID: TimeInterval] {
        sessions.reduce(into: [:]) { totals, session in
            guard let id = session.taskID else { return }
            totals[id, default: 0] += session.duration
        }
    }
}

private struct PastDayList: View {
    let day: Date
    let sessions: [FocusSession]
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        let tasks = PastDay.candidates(tasks: planner.tasks, day: day)
        let logged = PastDay.minutes(on: sessions)
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag a task onto the timeline to log time you didn't track.")
                .font(Typography.micro)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(tasks) { task in
                        HStack(spacing: 7) {
                            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(task.done ? Color.rest : DayPalette.tint(task.priority))
                            Text(task.title)
                                .font(Typography.caption)
                                .foregroundStyle(task.done ? Color.textSecondary : Color.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let time = logged[task.id], time >= 60 {
                                Text(TaskTime.text(time)).font(Typography.micro).monospacedDigit().foregroundStyle(Color.focus)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.surface))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .draggable(task.id.uuidString) {
                            Text(task.title).font(Typography.caption).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Color.focus.opacity(0.9)))
                        }
                        .help("Drag onto the timeline to log time")
                    }
                }
            }
        }
    }
}
