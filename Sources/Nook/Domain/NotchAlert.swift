import SwiftUI

struct NotchAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case focusFinished, breakFinished, eventSoon, taskDue, focusPaused, info
    }

    var id = UUID()
    var kind: Kind = .info
    var symbol: String
    var tint: Color
    var headline: String
    var detail: String?
}
