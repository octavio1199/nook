import SwiftUI

struct TasksColumn: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(NotchInteraction.self) private var notch

    enum Scope: String, CaseIterable, Identifiable {
        case today = "Today", upcoming = "Upcoming", done = "Done"
        var id: Self { self }
    }

    @LocalState private var scope: Scope = .today
    @LocalState private var draft = ""
    @FocusState private var captureFocused: Bool
    @Namespace private var switcherNamespace

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let today = planner.todayTasks(now: now)
        let upcoming = planner.upcomingTasks(now: now)
        let done = planner.doneTasks()
        let visible: [TaskItem] = switch scope {
        case .today: today
        case .upcoming: upcoming
        case .done: done
        }
        let counts: [Scope: Int] = [.today: today.count, .upcoming: upcoming.count, .done: done.count]

        return Card("Tasks", symbol: "checklist") {
            VStack(alignment: .leading, spacing: 8) {
                captureField(now: now)
                switcher(counts: counts)
                taskList(visible, now: now)
            }
        }
        .onChange(of: notch.captureRequest) { captureFocused = true }
    }

    // MARK: - Capture

    private func captureField(now: Date) -> some View {
        let parsed = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : CaptureParser.parse(draft, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(captureFocused ? Color.accent : Color.textTertiary)
                TextField("", text: $draft, prompt: Text("Add a task… try “call Ana tomorrow 3pm !high #work”").foregroundStyle(Color.textTertiary))
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Color.textPrimary)
                    .focused($captureFocused)
                    .onSubmit { submit(now: now) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(captureFocused ? Color.accent.opacity(0.6) : Color.hairline)
            )
            .animation(Motion.hover, value: captureFocused)

            if !parsed.isEmpty {
                CapturePreview(tasks: parsed, now: now)
                    .transition(.opacity.combined(with: .offset(y: -3)))
            }
        }
        .animation(Motion.navigate, value: parsed.count)
        .animation(Motion.navigate, value: parsed.first)
    }

    private func submit(now: Date) {
        let tasks = CaptureParser.parse(draft, now: now)
        guard !tasks.isEmpty else { return }
        withAnimation(Motion.navigate) {
            planner.add(tasks)
            draft = ""
        }
    }

    // MARK: - Switcher

    private func switcher(counts: [Scope: Int]) -> some View {
        HStack(spacing: 2) {
            ForEach(Scope.allCases) { item in
                let selected = item == scope
                Button {
                    withAnimation(Motion.navigate) { scope = item }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.rawValue)
                        Text("\(counts[item] ?? 0)")
                            .foregroundStyle(selected ? Color.textSecondary : Color.textTertiary)
                    }
                    .font(Typography.caption)
                    .foregroundStyle(selected ? Color.textPrimary : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.surfaceRaised)
                                .matchedGeometryEffect(id: "pill", in: switcherNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25)))
    }

    // MARK: - List

    @ViewBuilder
    private func taskList(_ tasks: [TaskItem], now: Date) -> some View {
        if tasks.isEmpty {
            EmptyState(scope: scope)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(tasks) { task in
                        TaskRow(task: task, now: now, reorderable: scope == .today)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -4)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: .infinity)
            .animation(Motion.navigate, value: tasks.map(\.id))
        }
    }
}

// MARK: - Preview chips

private struct CapturePreview: View {
    let tasks: [TaskItem]
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            if tasks.count > 1 {
                Chip(text: "\(tasks.count) tasks", symbol: "square.stack", tint: .accent)
            } else if let task = tasks.first {
                if task.due != nil {
                    Chip(text: TaskFormat.dueText(task, now: now), symbol: task.hasTime ? "clock" : "calendar", tint: .accent)
                }
                if task.priority != .none {
                    Chip(text: task.priority.shortTitle, symbol: "flag.fill", tint: task.priority.tint)
                }
                ForEach(task.tags, id: \.self) { Chip(text: "#\($0)", tint: .textSecondary) }
            }
            Spacer(minLength: 0)
            Text("↩")
                .font(Typography.micro)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

struct Chip: View {
    var text: String
    var symbol: String?
    var tint: Color

    init(text: String, symbol: String? = nil, tint: Color) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(text).font(Typography.micro).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct EmptyState: View {
    let scope: TasksColumn.Scope

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18, weight: .light)).foregroundStyle(Color.textTertiary)
            Text(line).font(Typography.caption).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
    }

    private var symbol: String {
        switch scope {
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .done: "checkmark.circle"
        }
    }

    private var line: String {
        switch scope {
        case .today: "A clear day. Add something above\nor enjoy the quiet."
        case .upcoming: "Nothing scheduled ahead.\nTry “dentist friday 9am”."
        case .done: "Finished tasks will show up here."
        }
    }
}

// MARK: - Row

private struct TaskRow: View {
    @Environment(PlannerStore.self) private var planner
    let task: TaskItem
    let now: Date
    let reorderable: Bool

    @LocalState private var hovering = false
    @LocalState private var editing = false
    @LocalState private var editText = ""
    @LocalState private var dropTargeted = false
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            checkbox
            VStack(alignment: .leading, spacing: 3) {
                titleView
                if hasChips { chips }
            }
            Spacer(minLength: 0)
            if hovering && !editing {
                Button {
                    withAnimation(Motion.navigate) { planner.delete(task.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.surfaceRaised))
                }
                .buttonStyle(.plain)
                .help("Delete")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.surface : .clear)
        )
        .overlay(alignment: .top) {
            if dropTargeted { Capsule().fill(Color.accent).frame(height: 2).offset(y: -1) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu { menu }
        .modifier(ReorderModifier(enabled: reorderable, id: task.id, targeted: $dropTargeted, planner: planner))
    }

    private var hasChips: Bool {
        task.due != nil || task.priority != .none || !task.tags.isEmpty
    }

    private var checkbox: some View {
        Button {
            withAnimation(Motion.pop) { planner.toggle(task.id) }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(task.done ? Color.accent : Color.textTertiary, lineWidth: 1.4)
                Circle()
                    .fill(Color.accent)
                    .scaleEffect(task.done ? 1 : 0.01)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.black)
                    .scaleEffect(task.done ? 1 : 0.1)
                    .opacity(task.done ? 1 : 0)
            }
            .frame(width: 15, height: 15)
            .padding(.top, 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var titleView: some View {
        if editing {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Color.textPrimary)
                .focused($editFocused)
                .onSubmit(commitEdit)
                .onExitCommand { editing = false }
                .onChange(of: editFocused) { if !editFocused { commitEdit() } }
        } else {
            Text(task.title)
                .font(Typography.body)
                .foregroundStyle(task.done ? Color.textTertiary : Color.textPrimary)
                .strikethrough(task.done, color: Color.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginEdit() }
        }
    }

    private var chips: some View {
        HStack(spacing: 4) {
            if task.due != nil {
                let overdue = task.isOverdue(now: now)
                Chip(text: TaskFormat.dueText(task, now: now),
                     symbol: task.hasTime ? "clock" : "calendar",
                     tint: overdue ? .red : .textSecondary)
            }
            if task.priority != .none {
                Chip(text: task.priority.shortTitle, symbol: "flag.fill", tint: task.priority.tint)
            }
            ForEach(task.tags, id: \.self) { Chip(text: "#\($0)", tint: .textTertiary) }
        }
        .opacity(task.done ? 0.5 : 1)
    }

    // MARK: Editing

    private func beginEdit() {
        editText = task.title
        editing = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        let title = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != task.title else { return }
        var updated = task
        updated.title = title
        planner.update(updated)
    }

    // MARK: Menu

    @ViewBuilder
    private var menu: some View {
        Button("Move to Today") { reschedule(.today) }
        Button("Move to Tomorrow") { reschedule(.tomorrow) }
        Button("Move to Next Week") { reschedule(.nextWeek) }
        Button("No Date") { reschedule(.none) }
        Divider()
        Menu("Priority") {
            ForEach(TaskItem.Priority.allCases.reversed(), id: \.self) { p in
                Button {
                    var updated = task
                    updated.priority = p
                    planner.update(updated)
                } label: {
                    if task.priority == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { withAnimation(Motion.navigate) { planner.delete(task.id) } }
    }

    private enum Target { case today, tomorrow, nextWeek, none }

    private func reschedule(_ target: Target) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var updated = task
        updated.hasTime = false
        switch target {
        case .today: updated.due = start
        case .tomorrow: updated.due = cal.date(byAdding: .day, value: 1, to: start)
        case .nextWeek: updated.due = cal.date(byAdding: .day, value: 7, to: start)
        case .none: updated.due = nil
        }
        withAnimation(Motion.navigate) { planner.update(updated) }
    }
}

private struct ReorderModifier: ViewModifier {
    let enabled: Bool
    let id: UUID
    @Binding var targeted: Bool
    let planner: PlannerStore

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
                    withAnimation(Motion.navigate) { planner.move(dragged, before: id) }
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

// MARK: - Formatting

enum TaskFormat {
    static func dueText(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> String {
        guard let due = task.due else { return "" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        let time = due.formatted(date: .omitted, time: .shortened)
        switch days {
        case 0: return task.hasTime ? time : "Today"
        case 1: return task.hasTime ? "Tomorrow \(time)" : "Tomorrow"
        case -1: return task.hasTime ? "Yesterday \(time)" : "Yesterday"
        case 2...6:
            let day = due.formatted(.dateTime.weekday(.abbreviated))
            return task.hasTime ? "\(day) \(time)" : day
        default:
            let day = due.formatted(.dateTime.day().month(.abbreviated))
            return task.hasTime ? "\(day) \(time)" : day
        }
    }
}

extension TaskItem.Priority {
    var tint: Color {
        switch self {
        case .none: .textTertiary
        case .low: Color(red: 0.42, green: 0.72, blue: 1.0)
        case .medium: .accent
        case .high: .focus
        }
    }
}
