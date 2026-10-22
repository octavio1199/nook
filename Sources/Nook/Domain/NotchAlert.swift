import SwiftUI

struct NotchAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case focusFinished, breakFinished, eventSoon, taskDue, focusPaused, info
        /// A focus on a task ran out: the user picks +5 min, break-and-continue or done.
        case taskCheckIn
    }

    var id = UUID()
    var kind: Kind = .info
    var symbol: String
    var tint: Color
    var headline: String
    var detail: String?
    /// Sticky alerts stay in the notch until the user acts on them.
    var sticky = false
    var taskID: UUID?
}
