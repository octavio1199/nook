import SwiftUI

struct FocusCard: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    @StateObject private var draft = Draft()

    var body: some View {
        Card("Focus", symbol: "timer", trailing: focus.isActive ? AnyView(statusDot) : nil) {
            ZStack {
                if focus.isActive {
                    ActiveFocusView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    idleView
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.navigate, value: focus.isActive)
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

    private var trimmedLabel: String? {
        let text = draft.label.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private var selectedPreset: FocusPreset { .with(id: settings.focusPresetID) }

    private var idleView: some View {
        VStack(spacing: 6) {
            presetPicker
            HStack(spacing: 5) {
                ForEach([5, 10, 30], id: \.self) { minutes in
                    SmallChip(title: "\(minutes)m") { focus.startCountdown(minutes: minutes, label: trimmedLabel) }
                }
                SmallChip(symbol: "stopwatch") { focus.startStopwatch(label: trimmedLabel) }
                    .help("Stopwatch")
            }
            TextField("What are you focusing on?", text: $draft.label)
                .textFieldStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.surface))
                .onSubmit { focus.startPomodoro(selectedPreset, label: trimmedLabel) }
            Button {
                focus.startPomodoro(selectedPreset, label: trimmedLabel)
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

// MARK: - Active

private struct ActiveFocusView: View {
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        let tint = focus.phase?.tint ?? .focus
        VStack(spacing: 8) {
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
                            .lineLimit(2)
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

private final class Draft: ObservableObject {
    @Published var label = ""
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

private struct RoundButton: View {
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
