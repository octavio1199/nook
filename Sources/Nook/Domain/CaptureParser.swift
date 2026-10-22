import Foundation

/// Local natural-language capture (English + Portuguese). No network.
/// `call Ana tomorrow 3pm !high #work` -> task with due date, time, priority and tag.
nonisolated enum CaptureParser {
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        split(text).compactMap { parseSegment($0, now: now, calendar: calendar) }
    }

    // MARK: - Splitting

    static func split(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n\r;"))
            .map { stripListMarker($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func stripListMarker(_ line: String) -> String {
        var s = line
        _ = take(#"^(?:[-*•]|\[[ xX]?\]|\d{1,2}[.)])\s+"#, from: &s, replacement: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Segment

    private static let b = #"(?<![\p{L}\p{N}_])"#
    private static let e = #"(?![\p{L}\p{N}_])"#

    private static func parseSegment(_ segment: String, now: Date, calendar: Calendar) -> TaskItem? {
        var s = segment
        var task = TaskItem(title: "", createdAt: now)

        // Priority (standalone tokens only).
        var kept: [Substring] = []
        for token in s.split(whereSeparator: \.isWhitespace) {
            if let p = priority(for: token.lowercased()) {
                if p.rawValue > task.priority.rawValue { task.priority = p }
            } else {
                kept.append(token)
            }
        }
        s = kept.joined(separator: " ")

        // Tags.
        while let caps = take(#"(?<![\p{L}\p{N}_&])#([\p{L}\p{N}_-]+)"#, from: &s), let tag = caps[1]?.lowercased() {
            if !task.tags.contains(tag) { task.tags.append(tag) }
        }

        // Dates / times.
        let when = extractWhen(from: &s, now: now, calendar: calendar)
        task.due = when?.date
        task.hasTime = when?.hasTime ?? false

        task.title = cleanTitle(s)
        return task.title.isEmpty ? nil : task
    }

    private static func priority(for token: String) -> TaskItem.Priority? {
        switch token {
        case "!!!", "!high", "!alta", "!urgent", "!urgente", "!h": .high
        case "!!", "!med", "!medium", "!media", "!média", "!medio", "!médio", "!m": .medium
        case "!", "!low", "!baixa", "!baixo", "!l": .low
        default: nil
        }
    }

    // MARK: - When

    private struct When { var date: Date; var hasTime: Bool }

    private static let weekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "dom": 1, "domingo": 1, "seg": 2, "segunda": 2, "terca": 3, "qua": 4, "quarta": 4,
        "qui": 5, "quinta": 5, "sex": 6, "sexta": 6, "sab": 7, "sabado": 7,
    ]

    private static func extractWhen(from s: inout String, now: Date, calendar: Calendar) -> When? {
        let today = calendar.startOfDay(for: now)
        var day: Date?
        var time: (h: Int, m: Int)?
        var exact: Date? // relative hours / minutes

        // in 2 hours / em 30 minutos / in 3 days
        if let c = take("\(b)(?:in|em)\\s+(\\d+|an?|um|uma|one)\\s*(minutes?|mins?|minutos?|hours?|hrs?|horas?|h|days?|dias?|weeks?|semanas?)\(e)", from: &s),
           let amountText = c[1]?.lowercased(), let unit = c[2]?.lowercased() {
            let n = Int(amountText) ?? 1
            switch unit.first {
            case "m": exact = calendar.date(byAdding: .minute, value: n, to: now)
            case "h": exact = calendar.date(byAdding: .hour, value: n, to: now)
            case "d": day = calendar.date(byAdding: .day, value: n, to: today)
            default: day = calendar.date(byAdding: .day, value: n * 7, to: today)
            }
        }

        // day after tomorrow
        if day == nil, take("\(b)(?:day after tomorrow|depois de amanh[ãa])\(e)", from: &s) != nil {
            day = calendar.date(byAdding: .day, value: 2, to: today)
        }

        // today / tomorrow
        if day == nil, let c = take("\(b)(?:(?:for|para)\\s+)?(today|hoje|tomorrow|amanh[ãa])\(e)", from: &s), let word = c[1]?.lowercased() {
            let offset = (word == "today" || word == "hoje") ? 0 : 1
            day = calendar.date(byAdding: .day, value: offset, to: today)
        }

        // weekday names
        var sameWeekday = false // "on friday" said on a Friday: resolved once the time is known
        if day == nil {
            let full = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|segunda(?:-feira)?|ter[çc]a(?:-feira)?|quarta(?:-feira)?|quinta(?:-feira)?|sexta(?:-feira)?|s[áa]bado|domingo"
            let short = "mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun|seg|qua|qui|sex|sab|dom"
            let preposition = "(?:on|next|this|no|na|em|nesta|neste|dia|pr[óo]xim[ao]|para|for)"
            // Full names stand alone; short ones (sun, sex, dom...) only after a preposition,
            // so "buy sun cream" and "dom casmurro" stay titles.
            var hit: (String?, String?)?
            if let c = take("\(b)(?:(\(preposition))\\s+)?(\(full))\(e)", from: &s) {
                hit = (c[1], c[2])
            } else if let c = take("\(b)(\(preposition))\\s+(\(short))\(e)", from: &s) {
                hit = (c[1], c[2])
            }
            if let (prep, raw) = hit, let raw {
                var key = raw.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                if let dash = key.range(of: "-feira") { key.removeSubrange(dash) }
                if let target = weekdays[key] {
                    let current = calendar.component(.weekday, from: today)
                    var ahead = (target - current + 7) % 7
                    let forcesNext = prep.map { ["next", "proxim", "proxima", "proximo"].contains($0.lowercased().folding(options: .diacriticInsensitive, locale: nil)) } ?? false
                    if ahead == 0 {
                        if forcesNext { ahead = 7 } else { sameWeekday = true }
                    }
                    day = calendar.date(byAdding: .day, value: ahead, to: today)
                }
            }
        }

        if exact == nil {
            let lead = "(?:\(b)(?:at|às|ás)\\s+)?"
            if let c = take("\(lead)\(b)(1[0-2]|0?[1-9])(?::([0-5]\\d))?\\s*(am|pm)\(e)", from: &s),
               let hText = c[1], var h = Int(hText), let suffix = c[3]?.lowercased() {
                h = h % 12 + (suffix == "pm" ? 12 : 0)
                time = (h, Int(c[2] ?? "") ?? 0)
            } else if let c = take("\(lead)\(b)([01]?\\d|2[0-3]):([0-5]\\d)\(e)", from: &s), let h = Int(c[1] ?? "") {
                time = (h, Int(c[2] ?? "") ?? 0)
            } else if let c = take("\(lead)\(b)([01]?\\d|2[0-3])h(?:([0-5]\\d))?\(e)", from: &s), let h = Int(c[1] ?? "") {
                time = (h, Int(c[2] ?? "") ?? 0)
            } else if let c = take("\(b)(at|às|ás)\\s+([01]?\\d|2[0-3])\(e)", from: &s),
                      let word = c[1]?.lowercased(), var h = Int(c[2] ?? "") {
                if word == "at", (1...7).contains(h) { h += 12 }
                time = (h, 0)
            }
        }

        // Fallback: NSDataDetector for explicit dates ("Dec 25", "12/25/2030").
        if day == nil, exact == nil, let hit = detectDate(in: s, now: now, calendar: calendar) {
            s.replaceSubrange(hit.range, with: " ")
            day = hit.date
            if hit.hasTime, time == nil {
                time = (calendar.component(.hour, from: hit.fullDate), calendar.component(.minute, from: hit.fullDate))
            }
        }

        if let exact {
            return When(date: exact, hasTime: true)
        }
        if var day {
            if sameWeekday, let time,
               let slot = calendar.date(bySettingHour: time.h, minute: time.m, second: 0, of: day), slot <= now {
                day = calendar.date(byAdding: .day, value: 7, to: day) ?? day
            }
            if let time, let d = calendar.date(bySettingHour: time.h, minute: time.m, second: 0, of: day) {
                return When(date: d, hasTime: true)
            }
            return When(date: day, hasTime: false)
        }
        if let time, var d = calendar.date(bySettingHour: time.h, minute: time.m, second: 0, of: today) {
            if d <= now { d = calendar.date(byAdding: .day, value: 1, to: d) ?? d }
            return When(date: d, hasTime: true)
        }
        return nil
    }

    private struct Detected { var range: Range<String.Index>; var date: Date; var fullDate: Date; var hasTime: Bool }

    private static func detectDate(in s: String, now: Date, calendar: Calendar) -> Detected? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = s as NSString
        let matches = detector.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        guard let m = matches.first, let date = m.date, m.range.length >= 3, let range = Range(m.range, in: s) else { return nil }
        let text = String(s[range])
        // Reject bare numbers/ambiguous short hits.
        guard text.contains(where: \.isLetter) || text.contains("/") || text.contains("-") || text.contains(".") else { return nil }
        let timeLike = text.range(of: #"\d\s*(:|am|pm)|noon|midnight"#, options: [.regularExpression, .caseInsensitive]) != nil
        // The detector works in the system time zone; rebuild y/m/d in the caller's calendar.
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let rebuilt = calendar.date(from: c) else { return nil }
        return Detected(range: range, date: calendar.startOfDay(for: rebuilt), fullDate: date, hasTime: timeLike)
    }

    // MARK: - Helpers

    /// Removes the first match of `pattern` from `s` (replacing it with `replacement`) and returns its capture groups.
    @discardableResult
    private static func take(_ pattern: String, from s: inout String, replacement: String = " ") -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var caps: [String?] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            caps.append(r.location == NSNotFound ? nil : ns.substring(with: r))
        }
        s = ns.replacingCharacters(in: m.range, with: replacement)
        return caps
    }

    private static let danglingWords: Set<String> = ["at", "on", "by", "in", "for", "às", "ás", "de", "em", "no", "na", "para"]

    private static func cleanTitle(_ raw: String) -> String {
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let junk = CharacterSet(charactersIn: ",.:;-–—@")
        func trimmed(_ w: String) -> String { w.trimmingCharacters(in: junk) }
        // Drop trailing dangling prepositions / punctuation-only words; also leading punctuation-only words.
        while let last = words.last, trimmed(last).isEmpty || danglingWords.contains(trimmed(last).lowercased()) { words.removeLast() }
        while let first = words.first, trimmed(first).isEmpty { words.removeFirst() }
        var title = words.joined(separator: " ")
        title = title.trimmingCharacters(in: junk.union(.whitespaces))
        return title
    }
}
