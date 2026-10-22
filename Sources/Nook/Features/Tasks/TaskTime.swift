import Foundation

/// Formatting for time spent on tasks.
nonisolated enum TaskTime {
    /// Below this, a task shows no time chip.
    static let minimum: TimeInterval = 60

    /// "47m", "1h 05m", "2h". Empty-ish values read "0m".
    static func text(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(String(format: "%02d", m))m"
    }

    /// Text for a task's chip, or nil when under a minute.
    static func chip(_ interval: TimeInterval) -> String? {
        interval >= minimum ? text(interval) : nil
    }
}

nonisolated extension TaskTime {
    /// An estimate in minutes: `25m`, `1h`, `1h30`, `2h05`.
    static func estimateText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }

    /// Tracked against estimated, e.g. `20/50m`, `1h05/2h`.
    static func progressText(tracked: TimeInterval, estimate: Int) -> String {
        let spent = Int((tracked / 60).rounded(.down))
        let spentText = spent < 60 ? "\(spent)" : estimateText(spent)
        return "\(spentText)/\(estimateText(estimate))"
    }

    /// "20 of 50m" for the focus card. Drops the unit from the first number when both share it.
    static func ofText(tracked: TimeInterval, estimate: Int) -> String {
        let spent = Int((tracked / 60).rounded(.down))
        return spent < 60 ? "\(spent) of \(estimateText(estimate))" : "\(estimateText(spent)) of \(estimateText(estimate))"
    }

    /// 0...1 (capped) fill of the progress underline.
    static func fraction(tracked: TimeInterval, estimate: Int) -> Double {
        guard estimate > 0 else { return 0 }
        return min(max(tracked / Double(estimate * 60), 0), 1)
    }

    static func isOver(tracked: TimeInterval, estimate: Int) -> Bool {
        estimate > 0 && tracked > Double(estimate * 60)
    }
}
