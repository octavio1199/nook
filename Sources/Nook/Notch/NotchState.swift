enum NotchState: Equatable {
    case closed, peek, open
}

enum PanelArea: String, CaseIterable, Identifiable {
    case workspace, focus, day, insights

    var id: Self { self }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .focus: "Focus"
        case .day: "Day"
        case .insights: "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "square.grid.2x2"
        case .focus: "scope"
        case .day: "calendar.day.timeline.left"
        case .insights: "chart.bar.xaxis"
        }
    }
}
