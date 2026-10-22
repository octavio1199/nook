import AppKit
import SwiftUI

/// Vertical hour grid for one day: calendar events (read-only), task blocks (drag to move, drag the
/// bottom edge to resize), a plan preview and the "now" line. Drop an unscheduled task to place it.
struct DayTimeline: View {
    let day: Date
    let now: Date
    let events: [AgendaEvent]
    let tasks: [TaskItem]
    let preview: [DayPlanner.PlannedBlock]
    let dayPlanner: DayPlanner

    @Environment(PlannerStore.self) private var planner
    @LocalState private var targeted = false

    static let hourHeight: CGFloat = 46
    static let gutter: CGFloat = 40
    static let labelInset: CGFloat = 10

    private var calendar: Calendar { dayPlanner.calendar }
    private var dayStart: Date { calendar.startOfDay(for: day) }

    private struct Entry: Identifiable {
        enum Kind {
            case event(AgendaEvent)
            case task(TaskItem)
        }
        var id: String
        var kind: Kind
        var start: Date
        var end: Date
    }

    private var entries: [Entry] {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        var result: [Entry] = []
        for event in events where !event.isAllDay && event.end > dayStart && event.start < dayEnd {
            result.append(Entry(id: "event-" + event.id, kind: .event(event), start: max(event.start, dayStart), end: min(event.end, dayEnd)))
        }
        for task in tasks {
            guard let start = task.scheduledStart, let end = DayPlanner.end(of: task) else { continue }
            result.append(Entry(id: "task-" + task.id.uuidString, kind: .task(task), start: start, end: end))
        }
        return result
    }

    /// The whole day: blocks can go at any hour. Working hours only guide "Plan my day"
    /// (and get a lighter band).
    static let hours = 0..<24

    var body: some View {
        let entries = entries
        let range = Self.hours
        let geometry = Geometry(dayStart: dayStart, firstHour: range.lowerBound, hourHeight: Self.hourHeight)
        // Room below the last hour for the closing "24:00" line and its label.
        let total = CGFloat(range.count) * Self.hourHeight + Self.labelInset
        let spans = entries.map { DayPlanner.Span(id: $0.id, start: $0.start, end: $0.end) }
        let columns = DayPlanner.columns(for: spans)
        let overlapping = DayPlanner.overlapping(spans)
        let current = tasks.first { task in
            guard let start = task.scheduledStart, let end = DayPlanner.end(of: task) else { return false }
            return start <= now && end > now
        }?.id

        return GeometryReader { proxy in
            let areaWidth = max(proxy.size.width - Self.gutter - 4, 40)
            let anchor = scrollAnchor(range: range, content: total + Self.labelInset, viewport: proxy.size.height)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Room above the first hour so its label isn't clipped.
                    Color.clear.frame(height: Self.labelInset)
                    ZStack(alignment: .topLeading) {
                        grid(range: range)
                        ForEach(entries) { entry in
                            let place = columns[entry.id] ?? DayPlanner.Placement(column: 0, columns: 1)
                            let width = areaWidth / CGFloat(place.columns)
                            let x = Self.gutter + width * CGFloat(place.column)
                            let y = geometry.y(entry.start)
                            switch entry.kind {
                            case .event(let event):
                                EventBlock(event: event, height: max(geometry.y(entry.end) - y, 18))
                                    .frame(width: width - 2)
                                    .offset(x: x, y: y)
                            case .task(let task):
                                TaskBlock(
                                    task: task, y: y, width: width - 2, geometry: geometry, maxY: total,
                                    warn: overlapping.contains(entry.id), isCurrent: task.id == current, dayPlanner: dayPlanner
                                )
                                .offset(x: x, y: y)
                            }
                        }
                        ForEach(preview) { block in
                            if let task = planner.task(block.id) {
                                let y = geometry.y(block.start)
                                PreviewBlock(task: task, minutes: block.minutes, height: max(CGFloat(block.minutes) / 60 * Self.hourHeight, 18), start: block.start)
                                    .frame(width: areaWidth - 2)
                                    .offset(x: Self.gutter, y: y)
                            }
                        }
                        if calendar.isDate(now, inSameDayAs: dayStart), now >= geometry.origin, geometry.y(now) <= total {
                            NowLine().frame(width: proxy.size.width - Self.gutter + 6).offset(x: Self.gutter - 6, y: geometry.y(now) - 3.5)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: proxy.size.width, height: total, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, location in
                        drop(items, at: location, geometry: geometry, range: range)
                    } isTargeted: { targeted = $0 }
                }
            }
            .defaultScrollAnchor(anchor)
            // A new day starts from its own scroll position.
            .id(dayStart)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accent.opacity(targeted ? 0.7 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .animation(Motion.fade, value: targeted)
    }

    // MARK: - Pieces

    private func grid(range: Range<Int>) -> some View {
        let workFirst = CGFloat(dayPlanner.workStart) / 60
        let workLast = CGFloat(dayPlanner.workEnd) / 60
        return ZStack(alignment: .topLeading) {
            // Working hours sit on a slightly lighter band.
            Rectangle()
                .fill(Color.white.opacity(0.03))
                .frame(height: max((workLast - workFirst) * Self.hourHeight, 0))
                .offset(x: Self.gutter, y: (workFirst - CGFloat(range.lowerBound)) * Self.hourHeight)
            VStack(spacing: 0) {
                ForEach(Array(range), id: \.self) { hour in
                    hourLine(hour)
                        .frame(height: Self.hourHeight, alignment: .top)
                }
                hourLine(range.upperBound)
            }
        }
    }

    private func hourLine(_ hour: Int) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: Self.gutter - 4, alignment: .trailing)
                .offset(y: -6)
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    /// Opens on the hour before now (today) or before the workday: the anchor's y is that hour's line
    /// as a fraction of the scrollable distance (`defaultScrollAnchor` aligns the same point of both).
    private func scrollAnchor(range: Range<Int>, content: CGFloat, viewport: CGFloat) -> UnitPoint {
        let hour: Int
        if let demo = DayDemo.scrollHour {
            hour = demo
        } else if calendar.isDate(now, inSameDayAs: dayStart), !DayDemo.showsMorning {
            hour = calendar.component(.hour, from: now) - 1
        } else {
            hour = dayPlanner.workStart / 60 - 1
        }
        let target = min(max(hour, range.lowerBound), range.upperBound - 1)
        let offset = CGFloat(target - range.lowerBound) * Self.hourHeight
        let scrollable = content - viewport
        guard scrollable > 0 else { return .top }
        return UnitPoint(x: 0, y: min(max(offset / scrollable, 0), 1))
    }

    private func drop(_ items: [String], at location: CGPoint, geometry: Geometry, range: Range<Int>) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw), let task = planner.task(id), task.isOpen else { return false }
        let lower = dayStart.addingTimeInterval(TimeInterval(range.lowerBound * 3600))
        let raw0 = geometry.date(atY: location.y)
        let start = min(max(dayPlanner.snapped(raw0), lower), dayStart.addingTimeInterval(TimeInterval(range.upperBound * 3600 - 900)))
        withAnimation(Motion.navigate) { planner.schedule(id, at: start) }
        return true
    }

    /// Maps between dates and y positions of this timeline.
    struct Geometry {
        var dayStart: Date
        var firstHour: Int
        var hourHeight: CGFloat

        var origin: Date { dayStart.addingTimeInterval(TimeInterval(firstHour * 3600)) }

        func y(_ date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(origin) / 3600) * hourHeight
        }

        func date(atY y: CGFloat) -> Date {
            origin.addingTimeInterval(TimeInterval(y / hourHeight) * 3600)
        }
    }
}

// MARK: - Blocks

private struct EventBlock: View {
    let event: AgendaEvent
    let height: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Capsule().fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                if height >= 34 {
                    Text("\(event.start.formatted(.dateTime.hour().minute())) – \(event.end.formatted(.dateTime.hour().minute()))")
                        .font(Typography.micro)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .frame(height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help("\(event.title) (calendar, read-only)")
    }
}

private struct PreviewBlock: View {
    let task: TaskItem
    let minutes: Int
    let height: CGFloat
    let start: Date

    var body: some View {
        let tint = DayPalette.tint(task.priority)
        HStack(spacing: 5) {
            Text(task.title).font(Typography.caption).foregroundStyle(Color.textPrimary).lineLimit(1)
            Text(start.formatted(.dateTime.hour().minute())).font(Typography.micro).monospacedDigit().foregroundStyle(Color.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: height, alignment: height < 30 ? .center : .top)
        .padding(.top, height < 30 ? 0 : 3)
        .frame(height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tint.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .allowsHitTesting(false)
    }
}

private struct TaskBlock: View {
    let task: TaskItem
    let y: CGFloat
    let width: CGFloat
    let geometry: DayTimeline.Geometry
    let maxY: CGFloat
    let warn: Bool
    let isCurrent: Bool
    let dayPlanner: DayPlanner

    @Environment(PlannerStore.self) private var planner
    @Environment(BlockWatcher.self) private var blocks
    @LocalState private var moveY: CGFloat = 0
    @LocalState private var resizeY: CGFloat = 0
    @LocalState private var moving = false
    @LocalState private var resizing = false

    private var minutes: Int { DayPlanner.minutes(for: task) }
    private var start: Date { task.scheduledStart ?? geometry.origin }

    /// Length while a resize drag is in progress (15 min steps, at least 15).
    private var liveMinutes: Int {
        guard resizing else { return minutes }
        let raw = Double(minutes) + Double(resizeY / geometry.hourHeight) * 60
        return max(Int((raw / 15).rounded()) * 15, 15)
    }

    private var height: CGFloat { max(CGFloat(liveMinutes) / 60 * geometry.hourHeight, 18) }

    /// Start while a move drag is in progress: absolute 15 min snapping, kept inside the timeline.
    private var liveStart: Date {
        guard moving else { return start }
        let raw = start.addingTimeInterval(TimeInterval(moveY / geometry.hourHeight) * 3600)
        var snapped = dayPlanner.snapped(raw)
        let top = geometry.origin
        let bottom = geometry.date(atY: maxY - 6).addingTimeInterval(-TimeInterval(liveMinutes * 60))
        snapped = min(max(snapped, top), max(bottom, top))
        return snapped
    }

    private var offsetY: CGFloat { moving ? geometry.y(liveStart) - y : 0 }

    var body: some View {
        let tint = DayPalette.tint(task.priority)
        let compact = height < 36
        let active = moving || resizing
        VStack(alignment: .leading, spacing: 1) {
            if compact {
                HStack(spacing: 4) {
                    title
                    Text(TaskTime.text(TimeInterval(liveMinutes * 60))).font(Typography.micro).foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                    warning
                }
            } else {
                HStack(spacing: 4) {
                    title
                    Spacer(minLength: 0)
                    warning
                }
                Text(timeText).font(Typography.micro).monospacedDigit().foregroundStyle(Color.textSecondary).lineLimit(1)
            }
        }
        .padding(.leading, 9).padding(.trailing, 6)
        .padding(.top, compact ? 0 : 3)
        .frame(width: width, height: height, alignment: compact ? .leading : .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.09))
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(active ? 0.42 : isCurrent ? 0.36 : 0.24))
            }
        )
        .overlay(alignment: .leading) {
            Capsule().fill(tint).frame(width: 3).padding(.vertical, 2).padding(.leading, 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(warn ? DayPalette.warning : tint.opacity(isCurrent || active ? 0.9 : 0.35), lineWidth: warn ? 1.5 : 1)
        )
        .overlay(alignment: .bottom) { resizeHandle }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .offset(y: offsetY)
        .zIndex(active ? 10 : 0)
        .gesture(moveGesture)
        .contextMenu {
            Button("Start focus") { blocks.startFocus(task.id) }
            Button("Mark done") { withAnimation(Motion.navigate) { planner.toggle(task.id) } }
            Divider()
            Button("Unschedule") { withAnimation(Motion.navigate) { planner.schedule(task.id, at: nil) } }
        }
        .help(warn ? "Overlaps another block or event" : "Drag to move, drag the bottom edge to resize")
        .animation(Motion.fade, value: warn)
    }

    private var title: some View {
        Text(task.title).font(Typography.caption).foregroundStyle(Color.textPrimary).lineLimit(1)
    }

    @ViewBuilder private var warning: some View {
        if warn {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DayPalette.warning)
        }
    }

    private var timeText: String {
        let begin = liveStart
        let end = begin.addingTimeInterval(TimeInterval(liveMinutes * 60))
        let format = Date.FormatStyle.dateTime.hour().minute()
        return "\(begin.formatted(format)) – \(end.formatted(format)) · \(TaskTime.text(TimeInterval(liveMinutes * 60)))"
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                moving = true
                moveY = value.translation.height
            }
            .onEnded { value in
                moveY = value.translation.height
                let target = liveStart
                withAnimation(Motion.navigate) {
                    if target != start { planner.schedule(task.id, at: target) }
                    moving = false
                    moveY = 0
                }
            }
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        resizing = true
                        resizeY = value.translation.height
                    }
                    .onEnded { value in
                        resizeY = value.translation.height
                        let target = liveMinutes
                        withAnimation(Motion.navigate) {
                            if target != minutes { planner.setEstimate(target, for: task.id) }
                            resizing = false
                            resizeY = 0
                        }
                    }
            )
    }
}

private struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
    }
}
