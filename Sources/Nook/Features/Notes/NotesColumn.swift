import SwiftUI

struct NotesColumn: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(WorkspaceState.self) private var workspace

    @LocalState private var text = ""
    @LocalState private var loaded = false
    @LocalState private var sentCount = 0
    @LocalState private var flashTask: Task<Void, Never>?
    @LocalState private var showHints = false
    @AppStorage("notesWrapLines") private var wrapLines = true

    private var day: Date { workspace.notesDay }
    private var isToday: Bool { workspace.notesDayIsToday }

    var body: some View {
        Card("Notepad", symbol: "note.text", trailing: AnyView(toolbar)) {
            VStack(alignment: .leading, spacing: 6) {
                MarkdownEditor(
                    text: $text,
                    placeholder: isToday ? "Jot something down…" : "Nothing written this day.",
                    onCommandReturn: sendLine,
                    wrapsLines: wrapLines
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .onAppear(perform: load)
        .onChange(of: text) { save() }
        .onChange(of: workspace.notesDay) { load() }
        // The store edits notes too (sent lines disappear when their task is done, undo restores them).
        .onChange(of: planner.note(for: day)) { load() }
        .onReceive(NotificationCenter.default.publisher(for: .nookShowNotesDay)) { note in
            guard let key = note.object as? String, let date = DayKey.date(from: key) else { return }
            save()
            workspace.selectNotesDay(date)
        }
    }

    // MARK: - Header

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton("face.smiling", help: "Emoji (⌃⌘Space)", active: false) { NSApp.orderFrontCharacterPalette(nil) }
            toolButton("text.word.spacing", help: wrapLines ? "Line wrap: on" : "Line wrap: off", active: wrapLines) { wrapLines.toggle() }
            Button { showHints.toggle() } label: {
                Text("Aa")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(showHints ? Color.accent : Color.textSecondary)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Markdown shortcuts")
            .popover(isPresented: $showHints, arrowEdge: .bottom) { hints }
            dayPicker
        }
    }

    private func toolButton(_ symbol: String, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(active ? Color.accent : Color.textSecondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var hints: some View {
        let rows: [(String, String)] = [
            ("# · ## · ###", "Headings"),
            ("**bold**  *italic*  ~~strike~~", "Inline styles"),
            ("`code`  ```block```", "Code"),
            ("- item · 1. item", "Lists (Enter continues)"),
            ("- [ ] task", "Checkbox (click to toggle)"),
            ("> quote", "Quote"),
            ("[text](https://…)", "Links"),
            ("Tab · ⇧Tab", "Indent / outdent list"),
            ("⌘↩", "Line → task"),
        ]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(rows[i].0).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.accent)
                    Spacer(minLength: 8)
                    Text(rows[i].1).font(Typography.caption).foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(width: 290)
    }

    private var dayPicker: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", help: "Previous day") { shift(-1) }
            Button {
                withAnimation(Motion.navigate) { workspace.selectNotesDay(workspace.today) }
            } label: {
                Text(dayLabel)
                    .font(Typography.micro)
                    .foregroundStyle(isToday ? Color.textSecondary : Color.accent)
                    .frame(minWidth: 40)
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
        if isToday { return "Today" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: workspace.today),
           Calendar.current.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
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
        withAnimation(Motion.navigate) { workspace.selectNotesDay(next) }
    }

    // MARK: - ⌘↩

    private func sendLine(_ line: String) -> Bool {
        var tasks = CaptureParser.parse(MarkdownStyler.plainContent(of: line))
        guard !tasks.isEmpty else { return false }
        let source = DayKey.string(for: day)
        for index in tasks.indices {
            tasks[index].sourceDay = source
            tasks[index].sourceLine = line.trimmingCharacters(in: .whitespaces)
        }
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
