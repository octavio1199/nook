import SwiftUI

struct LiveActivityWings: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let height: CGFloat

    @Environment(FocusTimer.self) private var focus
    @Environment(NotchInteraction.self) private var notch
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .padding(.leading, 16)
                .frame(width: notch.wingWidth, height: height, alignment: .leading)
            Color.clear.frame(width: notchWidth, height: height)
            rightWing
                .padding(.trailing, 14)
                .frame(width: notch.wingWidth, height: height, alignment: .trailing)
        }
        .frame(height: height)
    }

    @ViewBuilder private var leftWing: some View {
        switch activity {
        case .checkIn:
            Text("⏰ \(planner.task(focus.taskID)?.title ?? focus.label ?? "Focus")")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        case .focus where focus.phase?.isBreak == true:
            BreakTipLine(long: focus.phase == .longBreak)
        case .focus:
            let tint = focus.phase?.tint ?? .focus
            let stopwatch = focus.phase == .stopwatch
            HStack(spacing: 7) {
                ring(tint: tint, stopwatch: stopwatch)
                if let label = focus.label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(focus.isPaused ? 0.5 : 0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.opacity)
                }
            }
            .animation(Motion.fade, value: focus.label)
        case .event(let event):
            Circle().fill(event.color).frame(width: 8, height: 8)
                .padding(.leading, 3)
        case .block(let block):
            HStack(spacing: 6) {
                Capsule().fill(block.priority == .none ? Color.accent : block.priority.tint).frame(width: 3, height: 12)
                Text(block.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func ring(tint: Color, stopwatch: Bool) -> some View {
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: stopwatch ? 0.001 : max(focus.progress, 0.001))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: focus.progress)
                if stopwatch {
                    Circle().fill(tint).frame(width: 4, height: 4)
                }
                if focus.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(tint)
                        .transition(.opacity)
                }
            }
            .frame(width: 14, height: 14)
            .animation(Motion.fade, value: focus.isPaused)
    }

    @ViewBuilder private var rightWing: some View {
        switch activity {
        case .checkIn:
            HStack(spacing: 5) {
                PulsingDot(tint: .focus)
                Text("Time's up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.focus)
                    .lineLimit(1)
            }
        case .focus:
            Text(focus.displayText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(focus.phase?.isBreak == true ? Color.white : Color.white.opacity(focus.isPaused ? 0.5 : 0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.identity)
        case .block(let block):
            Text("until \(block.end.formatted(.dateTime.hour().minute()))")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .event(let event):
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let minutes = max(Int((event.start.timeIntervalSince(context.date) / 60).rounded(.up)), 0)
                Text(minutes == 0 ? "now" : "in \(minutes)m")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
    }
}

/// Rotating break suggestion ("🚰 Drink some water") that crossfades as it changes.
struct BreakTipLine: View {
    let long: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tip = BreakTips.tip(at: context.date, long: long)
            Text(tip.line)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .id(tip.id)
                .transition(.opacity)
                .animation(Motion.fade, value: tip.id)
        }
    }
}

/// A dot that breathes slowly, to say "waiting on you" without shouting.
struct PulsingDot: View {
    var tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2.4
            let wave = (sin(phase) + 1) / 2
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .opacity(0.55 + 0.45 * wave)
                .scaleEffect(0.85 + 0.25 * wave)
        }
    }
}
