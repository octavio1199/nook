import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: Color
    var location: String?
    var url: URL?
}
