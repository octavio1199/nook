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
