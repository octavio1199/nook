import SwiftUI

struct TasksColumn: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(NotchInteraction.self) private var notch

    typealias Scope = TaskScope

    @Environment(WorkspaceState.self) private var workspace
    @Namespace private var switcherNamespace
    private var toaster: UndoToaster { workspace.toaster }
    private var scope: Scope { workspace.taskScope }
    private var detailID: UUID? { workspace.detailTaskID }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let today = planner.todayTasks(now: now)
        let upcoming = planner.upcomingTasks(now: now)
        let done = planner.doneTasks(limit: .max)
        let archived = planner.archivedTasks()
        let visible: [TaskItem] = switch scope {
        case .today: today
        case .upcoming: upcoming
        case .done: done
        case .archive: archived
        }
        let counts: [Scope: Int] = [.today: today.count, .upcoming: upcoming.count, .done: done.count, .archive: archived.count]

        return Card("Tasks", symbol: "checklist") {
            ZStack {
                if let id = detailID, planner.task(id) != nil {
                    TaskDetailView(taskID: id, now: now, toaster: toaster) { workspace.detailTaskID = nil }
                        .transition(.opacity.combined(with: .offset(x: 14)))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        newTaskButton
                        switcher(counts: counts)
                        taskList(visible, now: now)
                    }
                    .transition(.opacity.combined(with: .offset(x: -14)))
                }
            }
            .animation(Motion.navigate, value: workspace.detailTaskID)
            .overlay(alignment: .bottom) {
                if let toast = toaster.toast {
                    UndoToastView(toast: toast) { toaster.undo(planner.undoManager) }
                        .id(toast.id)
                        .padding(.bottom, 2)
                }
            }
        }
        .onAppear {
            toaster.observe(planner.undoManager)
            if let id = workspace.detailTaskID, planner.task(id) == nil { workspace.detailTaskID = nil }
            _ = notch.takePendingCapture()
            syncCaptureRequest()
        }
        .onDisappear {
            workspace.closeComposer()
            workspace.closeFocusPicker()
        }
        .onChange(of: notch.captureRequest) { syncCaptureRequest() }
    }

    /// ⌥⌘N, ⌘N and "Quick capture" open the composer. The "first click focuses the capture field"
    /// request (`captureLeavesDetail == false`) has no field to focus any more, so it is only consumed.
    private func syncCaptureRequest() {
        guard notch.captureRequest != workspace.seenCaptureRequest else { return }
        workspace.seenCaptureRequest = notch.captureRequest
        guard notch.captureLeavesDetail else { return }
        workspace.detailTaskID = nil
        workspace.openComposer()
    }

    private var newTaskButton: some View {
        NewTaskButton(draftTitle: workspace.composer.isEmpty ? nil : workspace.composer.title) {
            withAnimation(Motion.navigate) { workspace.openComposer() }
        }
    }

    private func switcher(counts: [Scope: Int]) -> some View {
        HStack(spacing: 2) {
            ForEach(Scope.allCases) { item in
                let selected = item == scope
                Button {
                    withAnimation(Motion.navigate) { workspace.taskScope = item }
                } label: {
                    HStack(spacing: 4) {
                        if item == .archive {
                            Image(systemName: "archivebox").font(.system(size: 9, weight: .medium))
                        } else {
                            Text(item.label)
                        }
                        Text("\(counts[item] ?? 0)")
                            .foregroundStyle(selected ? Color.textSecondary : Color.textTertiary)
                    }
                    .font(Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
                .help(item == .archive ? "Archive" : (item == .upcoming ? "Upcoming" : item.label))
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
                    if scope == .done { archiveAllBar(count: tasks.count) }
                    ForEach(tasks) { task in
                        Group {
                            if scope == .archive {
                                ArchivedRow(task: task, now: now, toaster: toaster) { workspace.detailTaskID = task.id }
                            } else {
                                TaskRow(task: task, now: now, reorderable: scope == .today, toaster: toaster) {
                                    workspace.detailTaskID = task.id
                                }
                            }
                        }
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

    private func archiveAllBar(count: Int) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                withAnimation(Motion.navigate) { planner.archiveDone() }
                toaster.show(count == 1 ? "Archived 1 done task" : "Archived \(count) done tasks", symbol: "archivebox")
            } label: {
                Label("Archive all", systemImage: "archivebox")
                    .font(Typography.micro)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.surface))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Archive all done tasks (⌘Z to undo)")
        }
        .padding(.bottom, 3)
    }
}

// MARK: - Preview chips

private struct NewTaskButton: View {
    /// nil when there is no draft; otherwise the draft's (possibly empty) title.
    let draftTitle: String?
    let action: () -> Void
    @Environment(AppSettings.self) private var settings
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accent)
                if let draftTitle {
                    Text("Draft").font(Typography.caption).foregroundStyle(Color.accent)
                    Text(draftTitle.isEmpty ? "untitled" : draftTitle)
                        .font(Typography.body)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("New task").font(Typography.body).foregroundStyle(Color.textPrimary)
                }
                Spacer(minLength: 4)
                Text(settings.shortcut(for: .newTask).symbols)
                    .font(Typography.micro)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Color.surfaceRaised : Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help("New task (⌘N)")
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
            if !text.isEmpty { Text(text).font(Typography.micro).lineLimit(1) }
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
        case .archive: "archivebox"
        }
    }

    private var line: String {
        switch scope {
        case .today: "A clear day. Add something above\nor enjoy the quiet."
        case .upcoming: "Nothing scheduled ahead.\nTry “dentist friday 9am”."
        case .done: "Finished tasks will show up here."
        case .archive: "Archived tasks show up here.\nRestore them anytime."
        }
    }
}

// MARK: - Row

private struct TaskRow: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    let task: TaskItem
    let now: Date
    let reorderable: Bool
    let toaster: UndoToaster
    let onOpen: () -> Void

    @LocalState private var hovering = false
    @LocalState private var editing = false
    @LocalState private var editText = ""
    @LocalState private var dropTargeted = false
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            checkbox
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    titleView
                    if hasNotes && !editing {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                if hasChips { chips }
                if let estimate, tracked >= TaskTime.minimum, !task.done {
                    EstimateBar(fraction: TaskTime.fraction(tracked: tracked, estimate: estimate), over: isOver)
                        .padding(.trailing, 4)
                }
            }
            Spacer(minLength: 0)
            if hovering && !editing {
                if !task.done && !isFocused {
                    Button {
                        withAnimation(Motion.navigate) { TaskActions.focus(on: task, timer: focus, settings: settings) }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.focus)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.focus.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help("Focus on this")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                Button {
                    archive()
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.surfaceRaised))
                }
                .buttonStyle(.plain)
                .help("Archive (⌘Z to undo)")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? Color.focus.opacity(0.09) : (hovering ? Color.surface : .clear))
        )
        .overlay(alignment: .leading) {
            if isFocused {
                Capsule().fill(Color.focus).frame(width: 2, height: 14).offset(x: -1)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            }
        }
        .animation(Motion.navigate, value: isFocused)
        .overlay(alignment: .top) {
            if dropTargeted { Capsule().fill(Color.accent).frame(height: 2).offset(y: -1) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu { menu }
        .modifier(ReorderModifier(enabled: reorderable, id: task.id, targeted: $dropTargeted, planner: planner))
    }

    private var hasNotes: Bool { !(task.notes ?? "").isEmpty }

    private var isFocused: Bool { focus.isActive && focus.taskID == task.id }

    /// Focus time logged against this task (nil under a minute).
    private var tracked: TimeInterval { TaskActions.trackedTime(for: task.id, planner: planner, focus: focus) }

    private var timeText: String? { TaskTime.chip(tracked) }

    private var estimate: Int? { task.estimateMinutes.flatMap { $0 > 0 ? $0 : nil } }

    private var isOver: Bool { estimate.map { TaskTime.isOver(tracked: tracked, estimate: $0) } ?? false }

    private var hasChips: Bool {
        task.due != nil || task.priority != .none || !task.tags.isEmpty || timeText != nil || estimate != nil
    }

    private var checkbox: some View {
        Button {
            toggle()
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
                .gesture(
                    TapGesture(count: 2).onEnded { beginEdit() }
                        .exclusively(before: TapGesture().onEnded { onOpen() })
                )
        }
    }

    private var chips: some View {
        // Narrow column: if everything doesn't fit, the tags go first, then a plain "Today" date,
        // then the priority's label (its flag stays), rather than the row getting squeezed.
        ViewThatFits(in: .horizontal) {
            chipRow(withTags: true)
            chipRow(withTags: false)
            chipRow(withTags: false, compact: 1)
            chipRow(withTags: false, compact: 2)
        }
        .opacity(task.done ? 0.65 : 1)
    }

    private func chipRow(withTags: Bool, compact: Int = 0) -> some View {
        let overdue = task.isOverdue(now: now)
        let plainToday = !task.hasTime && !overdue && task.due.map { Calendar.current.isDate($0, inSameDayAs: now) } == true
        return HStack(spacing: 4) {
            if task.due != nil, !(compact >= 1 && plainToday) {
                Chip(text: TaskFormat.dueText(task, now: now),
                     symbol: task.hasTime ? "clock" : "calendar",
                     tint: overdue ? .red : .textSecondary)
            }
            if task.priority != .none {
                Chip(text: compact >= 2 ? "" : task.priority.shortTitle, symbol: "flag.fill", tint: task.priority.tint)
            }
            if let estimate {
                Chip(text: TaskTime.progressText(tracked: tracked, estimate: estimate), symbol: "stopwatch",
                     tint: isOver ? .accent : (timeText == nil ? .textTertiary : (task.done ? .rest : .focus)))
                    .help(isOver ? "Over the \(TaskTime.estimateText(estimate)) estimate" : "Focused / estimated")
            } else if let timeText {
                Chip(text: task.done ? "took \(timeText)" : timeText, symbol: "stopwatch", tint: task.done ? .rest : .focus)
            }
            if withTags {
                ForEach(task.tags, id: \.self) { Chip(text: "#\($0)", tint: .textTertiary) }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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
        TaskActions.rename(task, to: editText, planner: planner, focus: focus)
    }

    // MARK: Menu

    @ViewBuilder
    private var menu: some View {
        if !task.done {
            Button("Focus on this") { TaskActions.focus(on: task, timer: focus, settings: settings) }
            Divider()
        }
        Button("Open Details") { onOpen() }
        Divider()
        Button("Move to Today") { reschedule(.today) }
        Button("Move to Tomorrow") { reschedule(.tomorrow) }
        Button("Move to Next Week") { reschedule(.nextWeek) }
        Button("No Date") { reschedule(.none) }
        Divider()
        Menu("Priority") {
            ForEach(TaskItem.Priority.allCases.reversed(), id: \.self) { p in
                Button {
                    TaskActions.setPriority(task, p, in: planner)
                } label: {
                    if task.priority == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                }
            }
        }
        Divider()
        Button("Archive", systemImage: "archivebox") { archive() }
    }

    private func archive() {
        withAnimation(Motion.navigate) { planner.archive(task.id) }
        toaster.show("Archived", task.title, symbol: "archivebox")
    }

    private func toggle() {
        let completing = !task.done
        withAnimation(Motion.pop) { planner.toggle(task.id) }
        if completing { toaster.show("Completed", task.title, symbol: "checkmark.circle") }
    }

    private func reschedule(_ target: TaskActions.Reschedule) {
        TaskActions.reschedule(task, to: target, in: planner)
    }
}

/// Thin tracked-vs-estimated underline; orange once the estimate is exceeded.
private struct EstimateBar: View {
    let fraction: Double
    let over: Bool

    var body: some View {
        let tint: Color = over ? .accent : .focus
        Capsule()
            .fill(tint.opacity(0.18))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(tint).frame(width: proxy.size.width * (over ? 1 : fraction))
                }
            }
            .animation(Motion.fade, value: fraction)
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

// MARK: - Archived row

private struct ArchivedRow: View {
    @Environment(PlannerStore.self) private var planner
    let task: TaskItem
    let now: Date
    let toaster: UndoToaster
    let onOpen: () -> Void

    @LocalState private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Typography.body)
                    .foregroundStyle(Color.textSecondary.opacity(0.7))
                    .lineLimit(2)
                if let at = task.archivedAt {
                    Text("archived \(ArchiveFormat.ago(at, now: now))")
                        .font(Typography.micro)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                iconButton("arrow.uturn.backward", help: "Restore", tint: .textSecondary, action: restore)
                iconButton("trash", help: "Delete forever (⌘Z to undo)", tint: .red, action: deleteForever)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.surface : .clear))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward") { restore() }
            Button("Open Details") { onOpen() }
            Divider()
            Button("Delete Forever", systemImage: "trash", role: .destructive) { deleteForever() }
        }
    }

    private func iconButton(_ symbol: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
                .background(Circle().fill(tint == .red ? Color.red.opacity(0.14) : Color.surfaceRaised))
        }
        .buttonStyle(.plain)
        .help(help)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private func restore() {
        withAnimation(Motion.navigate) { planner.unarchive(task.id) }
        toaster.show("Restored", task.title, symbol: "arrow.uturn.backward")
    }

    private func deleteForever() {
        withAnimation(Motion.navigate) { planner.delete(task.id) }
        toaster.show("Deleted", task.title, symbol: "trash")
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
