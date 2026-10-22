import Foundation

struct BreakTip: Hashable, Identifiable {
    var emoji: String
    var text: String
    var id: String { emoji + text }
    var line: String { "\(emoji) \(text)" }
}

enum BreakTips {
    /// Seconds each suggestion stays on screen.
    static let interval: TimeInterval = 20

    static let emojiRow = "🧍🏻‍♂️ 🚰 🍃"

    static let short: [BreakTip] = [
        BreakTip(emoji: "🧍🏻‍♂️", text: "Stand up and stretch"),
        BreakTip(emoji: "🚰", text: "Drink some water"),
        BreakTip(emoji: "🍃", text: "Breathe deeply"),
        BreakTip(emoji: "👀", text: "Look 20 m away for 20 s"),
        BreakTip(emoji: "🚶", text: "Take a short walk"),
        BreakTip(emoji: "🙆", text: "Roll your shoulders"),
        BreakTip(emoji: "🤲", text: "Shake out your hands"),
        BreakTip(emoji: "🪟", text: "Look out the window"),
    ]

    static let long: [BreakTip] = short + [
        BreakTip(emoji: "☕️", text: "Make a coffee"),
        BreakTip(emoji: "🍎", text: "Grab a healthy snack"),
    ]

    static func tips(long isLong: Bool) -> [BreakTip] { isLong ? long : short }

    /// Deterministic rotation: the same date always yields the same tip.
    static func tip(at date: Date, long isLong: Bool) -> BreakTip {
        let list = tips(long: isLong)
        let slot = Int((date.timeIntervalSinceReferenceDate / interval).rounded(.down))
        return list[((slot % list.count) + list.count) % list.count]
    }
}
