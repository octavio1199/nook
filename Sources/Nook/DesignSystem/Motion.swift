// From Pullo (MIT, (c) 2026 Gabriel Jordan)
import SwiftUI

enum Motion {
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let close = Animation.spring(response: 0.36, dampingFraction: 0.92)
    static let peek = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let navigate = Animation.spring(response: 0.33, dampingFraction: 0.84)
    static let reveal = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let hover = Animation.easeOut(duration: 0.14)
    static let fade = Animation.easeOut(duration: 0.2)
}
