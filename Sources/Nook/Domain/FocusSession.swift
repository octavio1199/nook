import Foundation

struct FocusSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: Date
    var duration: TimeInterval
    var label: String?
}
