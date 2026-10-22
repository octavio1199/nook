import Foundation

struct FocusSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: Date
    var duration: TimeInterval
    var label: String?
    var taskID: UUID?
}

extension FocusSession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decode(Date.self, forKey: .start)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        label = try? c.decodeIfPresent(String.self, forKey: .label)
        taskID = try? c.decodeIfPresent(UUID.self, forKey: .taskID)
    }
}
