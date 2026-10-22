import SwiftUI

struct NotesColumn: View {
    @Environment(PlannerStore.self) private var planner

    @LocalState private var day = Calendar.current.startOfDay(for: Date())
    @LocalState private var text = ""
    @LocalState private var loaded = false
    @LocalState private var sentCount = 0
    @LocalState private var flashTask: Task<Void, Never>?

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Card("Notepad", symbol: "note.text", trailing: AnyView(dayPicker)) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    NoteTextView(text: $text, onSendLine: sendLine)
                    if text.isEmpty {
                        Text(isToday ? "Jot something down…" : "Nothing written this day.")
                            .font(Typography.body)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .onAppear(perform: load)
        .onChange(of: text) { save() }
        .onChange(of: day) { load() }
    }

    // MARK: - Header

    private var dayPicker: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", help: "Previous day") { shift(-1) }
            Button {
                withAnimation(Motion.navigate) { day = Calendar.current.startOfDay(for: Date()) }
            } label: {
                Text(dayLabel)
                    .font(Typography.micro)
                    .foregroundStyle(isToday ? Color.textSecondary : Color.accent)
                    .frame(minWidth: 56)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .help("Jump to today")
            arrow("chevron.right", help: "Next day", disabled: isToday) { shift(1) }
        }
    }

    private func arrow(_ symbol: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(disabled ? Color.textTertiary.opacity(0.4) : Color.textSecondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if sentCount > 0 {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(Color.rest)
                Text(sentCount == 1 ? "Added 1 task" : "Added \(sentCount) tasks")
                    .foregroundStyle(Color.rest)
                    .transition(.opacity)
            } else {
                Text("⌘↩ line → task").foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .foregroundStyle(Color.textTertiary)
        }
        .font(Typography.micro)
        .animation(Motion.fade, value: sentCount)
    }

    // MARK: - Persistence

    private func load() {
        let note = planner.note(for: day)
        if note != text { text = note }
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        if planner.note(for: day) != text { planner.setNote(text, for: day) }
    }

    private func shift(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: day) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        withAnimation(Motion.navigate) { day = min(next, today) }
    }

    // MARK: - ⌘↩

    private func sendLine(_ line: String) -> Bool {
        let tasks = CaptureParser.parse(line)
        guard !tasks.isEmpty else { return false }
        withAnimation(Motion.navigate) { planner.add(tasks) }
        sentCount = tasks.count
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            sentCount = 0
        }
        return true
    }
}
