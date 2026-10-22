import SwiftUI

struct LiveActivityWings: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let height: CGFloat

    @Environment(FocusTimer.self) private var focus

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .padding(.leading, 16)
                .frame(width: NotchLayout.wingWidth, height: height, alignment: .leading)
            Color.clear.frame(width: notchWidth, height: height)
            rightWing
                .padding(.trailing, 14)
                .frame(width: NotchLayout.wingWidth, height: height, alignment: .trailing)
        }
        .frame(height: height)
    }

    @ViewBuilder private var leftWing: some View {
        switch activity {
        case .focus:
            let tint = focus.phase?.tint ?? .focus
            let stopwatch = focus.phase == .stopwatch
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
        case .event(let event):
            Circle().fill(event.color).frame(width: 8, height: 8)
                .padding(.leading, 3)
        }
    }

    @ViewBuilder private var rightWing: some View {
        switch activity {
        case .focus:
            Text(focus.displayText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(focus.isPaused ? 0.5 : 0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.identity)
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
