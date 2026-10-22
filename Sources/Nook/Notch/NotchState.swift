enum NotchState: Equatable {
    case closed, peek, open
}

enum PanelArea: String, CaseIterable, Identifiable {
    case workspace, insights

    var id: Self { self }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .insights: "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "square.grid.2x2"
        case .insights: "chart.bar.xaxis"
        }
    }
}
