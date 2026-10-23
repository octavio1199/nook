import SwiftUI

/// The Focus tab: while a focus runs, only the current task (timer, sub-tasks, notes);
/// otherwise a task picker to start one.
struct FocusTabView: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        if focus.isActive {
            CurrentFocusView(task: planner.task(focus.taskID))
        } else {
            IdleFocusView()
        }
    }
}

// MARK: - Idle

private struct IdleFocusView: View {
    @Environment(WorkspaceState.self) private var workspace

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            FocusPickerContent(title: "What are you focusing on?")
                .padding(14)
                .frame(width: 440)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
            Spacer(minLength: 0)
        }
        .onAppear {
            workspace.focusQuery = ""
            workspace.focusSelection = 0
        }
    }
}

// MARK: - Running

private struct CurrentFocusView: View {
    let task: TaskItem?
    @Environment(FocusTimer.self) private var focus
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TimerColumn(task: task)
                .frame(width: 230)
            if let task {
                VStack(alignment: .leading, spacing: 10) {
                    header(task)
                    HStack(alignment: .top, spacing: 10) {
                        Card("Sub-tasks", symbol: "checklist") {
                            SubtaskList(taskID: task.id, roomy: true)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        Card("Notes", symbol: "note.text") {
                            TaskNotesEditor(text: Binding(
                                get: { planner.task(task.id)?.notes ?? "" },
                                set: { planner.setNotes($0, for: task.id) }
                            ))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else {
                // A focus without a task: pick one (or keep going without).
                FocusPickerContent(title: "Focus on a task?")
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
            }
        }
    }

    private func header(_ task: TaskItem) -> some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 5) {
            Text(task.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            HStack(spacing: 5) {
                if task.priority != .none {
                    Chip(text: task.priority.title, symbol: "flag.fill", tint: task.priority.tint)
                }
                if task.due != nil {
                    Chip(text: TaskFormat.dueText(task, now: now), symbol: task.hasTime ? "clock" : "calendar",
                         tint: task.isOverdue(now: now) ? .red : .textSecondary)
                }
                if let estimate = task.estimateMinutes {
                    let tracked = TaskActions.trackedTime(for: task.id, planner: planner, focus: focus)
                    Chip(text: TaskTime.ofText(tracked: tracked, estimate: estimate), symbol: "stopwatch",
                         tint: TaskTime.isOver(tracked: tracked, estimate: estimate) ? .accent : .focus)
                }
                ForEach(task.tags, id: \.self) { Chip(text: "#\($0)", tint: .textTertiary) }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Big ring, phase, controls; the check-in buttons when the time is up.
private struct TimerColumn: View {
    let task: TaskItem?
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        let tint = focus.phase?.tint ?? .focus
        VStack(spacing: 12) {
            Text(focus.awaitingDecision ? "Time's up" : (focus.phase?.title ?? "Focus"))
                .font(Typography.title)
                .foregroundStyle(focus.awaitingDecision ? Color.accent : tint)
            ring(tint: tint)
            if focus.awaitingDecision {
                CheckInActions(style: .large)
            } else {
                if focus.phase?.isBreak == true {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(BreakTips.tip(at: context.date, long: focus.phase == .longBreak).text)
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                controls(tint: tint)
                if task != nil, focus.phase?.countsAsFocus == true {
                    Button {
                        withAnimation(Motion.navigate) { focus.finishTask() }
                    } label: {
                        Label("Task done", systemImage: "checkmark")
                            .font(Typography.caption)
                            .foregroundStyle(Color.black.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(Capsule().fill(Color.rest))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Finish the task and end this focus")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.22)))
    }

    private func ring(tint: Color) -> some View {
        let value = focus.phase == .stopwatch ? focus.elapsed.truncatingRemainder(dividingBy: 60) / 60 : focus.progress
        return ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(value, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: value)
            Text(focus.displayText)
                .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.textPrimary.opacity(focus.isPaused ? 0.5 : 1))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 14)
        }
        .frame(width: 140, height: 140)
    }

    private func controls(tint: Color) -> some View {
        HStack(spacing: 6) {
            RoundButton(symbol: focus.isPaused ? "play.fill" : "pause.fill", tint: tint, prominent: true) { focus.togglePause() }
                .help(focus.isPaused ? "Resume" : "Pause")
            if focus.phase != .stopwatch {
                RoundButton(text: "+5") { focus.addFiveMinutes() }.help("Add 5 minutes")
            }
            if focus.phase == .focus || focus.phase?.isBreak == true {
                RoundButton(symbol: "forward.end.fill") { focus.skip() }.help("Skip")
            }
            RoundButton(symbol: "stop.fill") { focus.stop() }.help("Stop")
        }
        .frame(height: 28)
    }
}
