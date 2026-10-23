import SwiftUI

struct FocusCard: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        Card("Focus", symbol: "timer", trailing: focus.isActive || focus.awaitingDecision ? AnyView(statusDot) : nil) {
            ZStack {
                if focus.awaitingDecision {
                    CheckInView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if focus.isActive {
                    ActiveFocusView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    idleView
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.navigate, value: focus.isActive)
            .animation(Motion.navigate, value: focus.awaitingDecision)
        }
        .frame(minWidth: 230, idealWidth: 230, minHeight: 170, idealHeight: 170)
    }

    private var statusDot: some View {
        Circle()
            .fill(focus.phase?.tint ?? .clear)
            .frame(width: 6, height: 6)
            .opacity(focus.isPaused ? 0.4 : 1)
    }

    // MARK: Idle

    /// The picked task, unless it has been completed or deleted since.
    private var selectedTask: TaskItem? {
        planner.task(focus.taskID).flatMap { $0.done ? nil : $0 }
    }

    private var selectedPreset: FocusPreset { .with(id: settings.focusPresetID) }

    private var idleView: some View {
        VStack(spacing: 6) {
            presetPicker
            HStack(spacing: 5) {
                ForEach([5, 10, 30], id: \.self) { minutes in
                    SmallChip(title: "\(minutes)m") {
                        focus.startCountdown(minutes: minutes, label: selectedTask?.title, taskID: selectedTask?.id)
                    }
                }
                SmallChip(symbol: "stopwatch") { focus.startStopwatch(label: selectedTask?.title, taskID: selectedTask?.id) }
                    .help("Stopwatch")
            }
            TaskPicker(selected: selectedTask, tasks: planner.todayTasks()) { focus.focus(on: $0) } label: { title in
                HStack(spacing: 5) {
                    Image(systemName: "scope").font(.system(size: 9, weight: .semibold))
                    Text(title ?? "Focus on…").font(Typography.caption).lineLimit(1)
                    Spacer(minLength: 0)
                    if title != nil, let minutes = selectedTask?.estimateMinutes, minutes > 0 {
                        Text("~\(TaskTime.estimateText(minutes))").font(Typography.micro).foregroundStyle(Color.textTertiary)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(title == nil ? Color.textSecondary : Color.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.surface))
                .contentShape(Rectangle())
            }
            Button {
                focus.startPomodoro(selectedPreset, label: selectedTask?.title, taskID: selectedTask?.id)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(Typography.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.focus))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var presetPicker: some View {
        HStack(spacing: 2) {
            ForEach(FocusPreset.all) { preset in
                let selected = preset.id == selectedPreset.id
                Button {
                    withAnimation(Motion.navigate) { settings.focusPresetID = preset.id }
                } label: {
                    VStack(spacing: 0) {
                        Text(preset.name).font(Typography.micro)
                        Text("\(preset.focus)/\(preset.shortBreak)").font(.system(size: 9, weight: .medium)).monospacedDigit()
                            .foregroundStyle(selected ? Color.textSecondary : Color.textTertiary)
                    }
                    .foregroundStyle(selected ? Color.textPrimary : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.surfaceRaised)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.surface))
    }
}

// MARK: - Check-in

/// Shown when a focus on a task ran out: how long it took so far and what to do next.
private struct CheckInView: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        let spent = focus.taskID.map { planner.focusTime(for: $0) } ?? 0
        let title = planner.task(focus.taskID)?.title ?? focus.label
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.focus)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.focus.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time's up")
                        .font(Typography.title)
                        .foregroundStyle(Color.focus)
                    if let title {
                        Text(title)
                            .font(Typography.caption)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                    }
                    Text("\(TaskTime.text(spent)) so far")
                        .font(Typography.micro)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { focus.dismissCheckIn() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.surface))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Not now")
            }
            Spacer(minLength: 0)
            CheckInActions(style: .large)
        }
    }
}

// MARK: - Active

private struct ActiveFocusView: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        if focus.phase?.isBreak == true {
            breakBody
        } else {
            focusBody
        }
    }

    // MARK: Break

    private var breakBody: some View {
        let tint = Color.rest
        let long = focus.phase == .longBreak
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                ring(tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(focus.phase?.title ?? "Break")
                        .font(Typography.title)
                        .foregroundStyle(tint)
                    Text(BreakTips.emojiRow)
                        .font(.system(size: 19))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let tip = BreakTips.tip(at: context.date, long: long)
                        Text(tip.text)
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(tip.id)
                            .transition(.opacity)
                            .animation(Motion.fade, value: tip.id)
                    }
                    Spacer(minLength: 0)
                    cycleDots(tint: tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 80)
            }
            HStack(spacing: 6) {
                BreakButton(title: "Skip break", tint: tint, prominent: true) { focus.skip() }
                BreakButton(title: "+5 min", tint: tint, prominent: false) { focus.addFiveMinutes() }
            }
            .frame(height: 28)
        }
    }

    // MARK: Focus

    private var focusBody: some View {
        let tint = focus.phase?.tint ?? .focus
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                ring(tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(focus.phase?.title ?? "")
                        .font(Typography.title)
                        .foregroundStyle(Color.textPrimary)
                    if let label = focus.label {
                        Text(label)
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(estimateLine == nil ? 2 : 1)
                        if let estimateLine {
                            Text(estimateLine.text)
                                .font(Typography.micro)
                                .monospacedDigit()
                                .foregroundStyle(estimateLine.over ? Color.accent : Color.textTertiary)
                        }
                        changeMenu(title: "change")
                    } else if focus.phase?.isBreak == false {
                        changeMenu(title: "Choose a task")
                    } else if focus.isPaused {
                        Text("Paused").font(Typography.caption).foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if focus.phase?.countsAsFocus == true || focus.phase?.isBreak == true, isPomodoro {
                        cycleDots(tint: tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 80)
            }
            controls(tint: tint)
        }
    }

    /// "20 of 50m" for the task being focused on, when it has an estimate.
    private var estimateLine: (text: String, over: Bool)? {
        guard let task = planner.task(focus.taskID), let estimate = task.estimateMinutes, estimate > 0,
              focus.phase?.countsAsFocus == true else { return nil }
        let tracked = TaskActions.trackedTime(for: task.id, planner: planner, focus: focus)
        return (TaskTime.ofText(tracked: tracked, estimate: estimate), TaskTime.isOver(tracked: tracked, estimate: estimate))
    }

    private func changeMenu(title: String) -> some View {
        TaskPicker(selected: planner.task(focus.taskID), tasks: planner.todayTasks()) { focus.focus(on: $0) } label: { _ in
            HStack(spacing: 3) {
                Text(title).font(Typography.micro)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Color.accent)
            .contentShape(Rectangle())
        }
    }

    private var isPomodoro: Bool {
        guard let phase = focus.phase else { return false }
        return phase == .focus || phase.isBreak
    }

    private func ring(tint: Color) -> some View {
        let isStopwatch = focus.phase == .stopwatch
        let value = isStopwatch
            ? focus.elapsed.truncatingRemainder(dividingBy: 60) / 60
            : focus.progress
        return ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(value, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: value)
            Text(focus.displayText)
                .font(Typography.timer)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(Color.textPrimary.opacity(focus.isPaused ? 0.5 : 1))
                .padding(.horizontal, 10)
                .contentTransition(.identity)
        }
        .frame(width: 80, height: 80)
        .animation(Motion.fade, value: focus.isPaused)
    }

    private func cycleDots(tint: Color) -> some View {
        let total = focus.preset.sessionsBeforeLongBreak
        let done = focus.completedInCycle % total
        // A running focus session counts as the one in progress.
        let filled = focus.phase?.isBreak == true && done == 0 && focus.completedInCycle > 0 ? total : done
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? tint : Color.white.opacity(0.14))
                    .frame(width: 6, height: 6)
                    .overlay {
                        if index == filled, focus.phase == .focus {
                            Circle().strokeBorder(tint, lineWidth: 1)
                        }
                    }
            }
        }
        .animation(Motion.pop, value: filled)
    }

    private func controls(tint: Color) -> some View {
        HStack(spacing: 6) {
            RoundButton(symbol: focus.isPaused ? "play.fill" : "pause.fill", tint: tint, prominent: true) {
                focus.togglePause()
            }
            .help(focus.isPaused ? "Resume" : "Pause")
            if focus.phase != .stopwatch {
                RoundButton(text: "+5") { focus.addFiveMinutes() }.help("Add 5 minutes")
            }
            if isPomodoro {
                RoundButton(symbol: "forward.end.fill") { focus.skip() }.help("Skip")
            }
            RoundButton(symbol: "stop.fill") { focus.stop() }.help("Stop")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

// MARK: - Components

/// Menu of today's open tasks plus "No task". `label` receives the selected title.
private struct TaskPicker<Content: View>: View {
    var selected: TaskItem?
    var tasks: [TaskItem]
    var choose: (TaskItem?) -> Void
    @ViewBuilder var label: (String?) -> Content

    /// "Write spec  ·  ~50m" when the task has an estimate.
    static func menuTitle(_ task: TaskItem) -> String {
        guard let minutes = task.estimateMinutes, minutes > 0 else { return task.title }
        return "\(task.title)  ·  ~\(TaskTime.estimateText(minutes))"
    }

    var body: some View {
        Menu {
            Button { choose(nil) } label: {
                if selected == nil { Label("No task", systemImage: "checkmark") } else { Text("No task") }
            }
            if !tasks.isEmpty { Divider() }
            ForEach(tasks) { task in
                Button { choose(task) } label: {
                    let title = Self.menuTitle(task)
                    if selected?.id == task.id { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            label(selected?.title)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

private final class HoverState: ObservableObject {
    @Published var on = false
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.hover, value: configuration.isPressed)
    }
}

private struct SmallChip: View {
    var title: String?
    var symbol: String?
    var action: () -> Void
    @StateObject private var hover = HoverState()

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    init(symbol: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let title { Text(title).font(Typography.caption).monospacedDigit() }
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(hover.on ? Color.textPrimary : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover.on ? Color.surfaceRaised : Color.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover.on = $0 }
        .animation(Motion.hover, value: hover.on)
    }
}

private struct BreakButton: View {
    var title: String
    var tint: Color
    var prominent: Bool
    var action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(prominent ? Color.black.opacity(0.8) : (hover.on ? Color.textPrimary : Color.textSecondary))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Capsule().fill(prominent ? tint : (hover.on ? Color.surfaceRaised : Color.surface)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover.on = $0 }
        .animation(Motion.hover, value: hover.on)
    }
}

struct RoundButton: View {
    var symbol: String?
    var text: String?
    var tint: Color = .white
    var prominent = false
    var action: () -> Void
    @StateObject private var hover = HoverState()

    init(symbol: String, tint: Color = .white, prominent: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.tint = tint
        self.prominent = prominent
        self.action = action
    }

    init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                if let text { Text(text).font(Typography.caption).monospacedDigit() }
            }
            .foregroundStyle(prominent ? Color.white : (hover.on ? Color.textPrimary : Color.textSecondary))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? tint : (hover.on ? Color.surfaceRaised : Color.surface)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover.on = $0 }
        .animation(Motion.hover, value: hover.on)
    }
}
