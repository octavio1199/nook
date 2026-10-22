import SwiftUI

struct PeekView: View {
    let alert: NotchAlert
    let onTap: () -> Void

    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    @Environment(PlannerStore.self) private var planner
    @Environment(NotchInteraction.self) private var notch

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: alert.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(alert.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(alert.tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.headline)
                    .font(Typography.title)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let detail = alert.detail, !detail.isEmpty {
                    Text(detailText(detail))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let task = finishedTask {
                Button {
                    withAnimation(Motion.navigate) { planner.toggle(task.id) }
                } label: {
                    Text("Mark done")
                        .font(Typography.caption)
                        .foregroundStyle(alert.tint)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(alert.tint.opacity(0.18)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if alert.kind == .taskCheckIn {
                CheckInActions(style: .compact)
            } else if alert.kind == .breakFinished, alert.taskID != nil {
                Button {
                    notch.dismissPeekNow()
                } label: {
                    Text("Later")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.surfaceRaised))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if let action {
                Button(action: action.run) {
                    Text(action.title)
                        .font(Typography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(alert.tint))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// Adds the break emoji row to "Focus done" while a break is running, and 💪 to "Break over".
    private func detailText(_ detail: String) -> String {
        switch alert.kind {
        case .taskCheckIn:
            let spent = alert.taskID.map { planner.focusTime(for: $0) } ?? 0
            return "Time's up · \(TaskTime.text(spent)) so far"
        case .focusFinished where focus.phase?.isBreak == true:
            return "\(detail) \(BreakTips.emojiRow)"
        case .breakFinished:
            return "\(detail) 💪"
        default:
            return detail
        }
    }

    private struct PillAction {
        var title: String
        var run: () -> Void
    }

    /// The open task the just-finished focus was logged against.
    private var finishedTask: TaskItem? {
        guard alert.kind == .focusFinished, let task = planner.task(focus.taskID), !task.done else { return nil }
        return task
    }

    private var preset: FocusPreset { .with(id: settings.focusPresetID) }

    private var action: PillAction? {
        switch alert.kind {
        case .focusFinished:
            if focus.isActive {
                return PillAction(title: "Done") { focus.stop() }
            }
            // Plain countdowns ("Time's up") have no follow-up.
            guard alert.symbol != "timer" else { return nil }
            return PillAction(title: "Start break") { focus.startBreak() }
        case .breakFinished:
            return PillAction(title: alert.taskID == nil ? "Start focus" : "Continue") {
                focus.startNextFocus()
                if alert.taskID != nil { notch.dismissPeekNow() }
            }
        case .focusPaused:
            guard focus.isPaused else { return nil }
            return PillAction(title: "Resume") { focus.resume() }
        default:
            return nil
        }
    }
}
