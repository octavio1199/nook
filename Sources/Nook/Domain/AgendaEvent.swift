import Foundation
import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
    /// Unique per occurrence (identifier + start), so recurring events don't collide.
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: Color
    var location: String?
    var url: URL?
    /// https link to a Zoom / Meet / Teams / Webex call found in the url, location or notes.
    var joinURL: URL?
}

extension AgendaEvent {
    private static let meetingHosts = ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]

    static func isMeetingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func meetingLink(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                if let url = match.url, isMeetingURL(url) { return url }
            }
        }
        return nil
    }
}
