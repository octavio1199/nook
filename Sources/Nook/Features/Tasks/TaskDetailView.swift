import SwiftUI

struct TaskDetailView: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings

    let taskID: UUID
    let now: Date
    var toaster: UndoToaster?
    let onBack: () -> Void

    @LocalState private var titleDraft = ""
    @LocalState private var loaded = false
    @LocalState private var linkHover = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        if let task = planner.task(taskID) {
            VStack(alignment: .leading, spacing: 8) {
                header(task)
                titleField(task)
                chips(task)
                meta(task)
                notes(task)
            }
            .onAppear {
                guard !loaded else { return }
                titleDraft = task.title
                loaded = true
            }
            .onDisappear { commitTitle(task) }
            .onChange(of: task.title) { if !titleFocused { titleDraft = task.title } }
        } else {
            Color.clear.onAppear(perform: onBack)
        }
    }

    // MARK: Header

    private func header(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            Button {
                commitTitle(task)
                withAnimation(Motion.navigate, onBack)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                    Text("Tasks").font(Typography.caption)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 3)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if task.archivedAt != nil { archivedControls(task) } else { focusButton(task) }
        }
    }

    private func archivedControls(_ task: TaskItem) -> some View {
        HStack(spacing: 5) {
            Label("Archived", systemImage: "archivebox")
                .font(Typography.micro)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Capsule().fill(Color.surfaceRaised))
            pill("Restore", symbol: "arrow.uturn.backward", tint: .accent) {
                withAnimation(Motion.navigate) { planner.unarchive(task.id) }
                toaster?.show("Restored", task.title, symbol: "arrow.uturn.backward")
            }
            pill("Delete", symbol: "trash", tint: .red) {
                toaster?.show("Deleted", task.title, symbol: "trash")
                withAnimation(Motion.navigate) { planner.delete(task.id) }
            }
            .help("Delete forever (⌘Z to undo)")
        }
    }

    private func pill(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Typography.micro)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(tint.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func focusButton(_ task: TaskItem) -> some View {
        let isFocusing = focus.isActive && focus.taskID == task.id
        if !task.done {
            Button {
                withAnimation(Motion.navigate) { TaskActions.focus(on: task, timer: focus, settings: settings) }
            } label: {
                Label(isFocusing ? "Focusing" : "Focus on this", systemImage: isFocusing ? "scope" : "play.fill")
                    .font(Typography.micro)
                    .foregroundStyle(isFocusing ? Color.focus : Color.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(isFocusing ? Color.focus.opacity(0.16) : Color.focus))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isFocusing)
        }
    }

    // MARK: Title

    private func titleField(_ task: TaskItem) -> some View {
        TextField("", text: $titleDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typography.title)
            .foregroundStyle(task.done ? Color.textTertiary : Color.textPrimary)
            .lineLimit(1...3)
            .focused($titleFocused)
            .onSubmit { commitTitle(task) }
            .onChange(of: titleFocused) { if !titleFocused { commitTitle(task) } }
    }

    private func commitTitle(_ task: TaskItem) {
        guard loaded else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { titleDraft = task.title; return }
        TaskActions.rename(task, to: trimmed, planner: planner, focus: focus)
    }

    // MARK: Chips

    private func chips(_ task: TaskItem) -> some View {
        HStack(spacing: 4) {
            Menu {
                Button("Today") { TaskActions.reschedule(task, to: .today, in: planner) }
                Button("Tomorrow") { TaskActions.reschedule(task, to: .tomorrow, in: planner) }
                Button("Next Week") { TaskActions.reschedule(task, to: .nextWeek, in: planner) }
                Button("No Date") { TaskActions.reschedule(task, to: .none, in: planner) }
            } label: {
                if task.due != nil {
                    Chip(text: TaskFormat.dueText(task, now: now), symbol: task.hasTime ? "clock" : "calendar",
                         tint: task.isOverdue(now: now) ? .red : .textSecondary)
                } else {
                    Chip(text: "Add date", symbol: "calendar", tint: .textTertiary)
                }
            }
            Menu {
                ForEach(TaskItem.Priority.allCases.reversed(), id: \.self) { p in
                    Button {
                        TaskActions.setPriority(task, p, in: planner)
                    } label: {
                        if task.priority == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                    }
                }
            } label: {
                if task.priority != .none {
                    Chip(text: task.priority.shortTitle, symbol: "flag.fill", tint: task.priority.tint)
                } else {
                    Chip(text: "Priority", symbol: "flag", tint: .textTertiary)
                }
            }
            ForEach(task.tags, id: \.self) { Chip(text: "#\($0)", tint: .textTertiary) }
            Spacer(minLength: 0)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Meta

    @ViewBuilder
    private func meta(_ task: TaskItem) -> some View {
        let logged = TaskActions.focusTimeText(planner.focusTime(for: task.id))
        let source = task.sourceDay.flatMap { key in TaskActions.dayText(key).map { (key, $0) } }
        if logged != nil || source != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let logged {
                    Label(logged, systemImage: "timer")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .labelStyle(TightLabelStyle())
                }
                if let (key, text) = source {
                    Button {
                        NotificationCenter.default.post(name: .nookShowNotesDay, object: key)
                    } label: {
                        Label("From notes · \(text)", systemImage: "note.text")
                            .font(Typography.caption)
                            .foregroundStyle(linkHover ? Color.accent : Color.textSecondary)
                            .labelStyle(TightLabelStyle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { linkHover = $0 }
                    .animation(Motion.hover, value: linkHover)
                }
            }
        }
    }

    // MARK: Notes

    private func notes(_ task: TaskItem) -> some View {
        let binding = Binding<String>(
            get: { planner.task(taskID)?.notes ?? "" },
            set: { planner.setNotes($0, for: taskID) }
        )
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.surface)
            TaskNotesEditor(text: binding)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 9, weight: .semibold)).frame(width: 12)
            configuration.title
        }
    }
}
