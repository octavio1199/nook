import Foundation

/// Pure markdown tokenizer for one line (paragraph). Returns style spans; the editor maps them to attributes.
/// Ranges are UTF-16 (`NSRange`) relative to the start of the line passed in.
nonisolated enum MarkdownStyler {
    enum Kind: Equatable, Sendable {
        case heading(Int)
        case marker          // dimmed syntax: `**`, `` ` ``, `#`, link brackets
        case bold, italic, strike
        case code            // inline code
        case codeBlock       // line inside a fenced block
        case fence           // the ``` line itself
        case quote
        case listMarker      // `-`, `*`, `1.`
        case checkbox        // `[ ]` / `[x]`
        case done            // content of a checked item
        case link(String)
        case sentArrow       // "→ " already sent to tasks
        case sent
    }

    struct Span: Equatable, Sendable {
        var range: NSRange
        var kind: Kind
    }

    struct Result: Equatable, Sendable {
        var spans: [Span]
        var isFence: Bool
        /// UTF-16 length of the leading list/quote prefix (indent + marker + space); 0 if none. Used for hanging indents.
        var prefixLength: Int
    }

    struct Prefix: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case bullet(String)
            case ordered(Int, String)
            case checkbox(bullet: String, checked: Bool)
            case quote
        }
        var indent: String
        var kind: Kind
        /// UTF-16 length including trailing whitespace.
        var length: Int
        /// Range of the `[ ]` bracket, for checkboxes.
        var bracket: NSRange?
    }

    enum Continuation: Equatable, Sendable {
        case none
        /// Text to insert at the cursor (starts with "\n").
        case insert(String)
        /// The item is empty: remove this many UTF-16 units from the line start.
        case clear(Int)
    }

    // MARK: - Public API

    static func style(line: String, inFence: Bool) -> Result {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if isFence(line) { return Result(spans: [Span(range: full, kind: .fence)], isFence: true, prefixLength: 0) }
        if inFence { return Result(spans: [Span(range: full, kind: .codeBlock)], isFence: false, prefixLength: 0) }
        if line.hasPrefix("→ ") || line == "→" {
            var spans = [Span(range: full, kind: .sent)]
            spans.append(Span(range: NSRange(location: 0, length: 1), kind: .sentArrow))
            return Result(spans: spans, isFence: false, prefixLength: 0)
        }

        var spans: [Span] = []
        var contentStart = 0
        var prefixLength = 0

        if let m = headingRegex.firstMatch(in: line, range: full) {
            let level = m.range(at: 1).length
            spans.append(Span(range: full, kind: .heading(level)))
            spans.append(Span(range: m.range, kind: .marker))
            contentStart = m.range.length
        } else if let prefix = prefix(of: line) {
            prefixLength = prefix.length
            let indent = (prefix.indent as NSString).length
            let rest = NSRange(location: prefix.length, length: max(0, ns.length - prefix.length))
            switch prefix.kind {
            case .bullet:
                spans.append(Span(range: NSRange(location: indent, length: 1), kind: .listMarker))
            case .ordered(let n, let delim):
                let len = String(n).utf16.count + delim.utf16.count
                spans.append(Span(range: NSRange(location: indent, length: len), kind: .listMarker))
            case .checkbox(_, let checked):
                spans.append(Span(range: NSRange(location: indent, length: 1), kind: .listMarker))
                if let b = prefix.bracket { spans.append(Span(range: b, kind: .checkbox)) }
                if checked { spans.append(Span(range: rest, kind: .done)) }
            case .quote:
                spans.append(Span(range: rest, kind: .quote))
                spans.append(Span(range: NSRange(location: indent, length: 1), kind: .marker))
            }
            contentStart = prefix.length
        }

        spans.append(contentsOf: inline(line, from: contentStart))
        // Dim markers last so they win over color-setting spans.
        let ordered = spans.filter { $0.kind != .marker } + spans.filter { $0.kind == .marker }
        return Result(spans: ordered, isFence: false, prefixLength: prefixLength)
    }

    static func isFence(_ line: String) -> Bool {
        fenceRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Whether the line starting at `lineStart` sits inside a fenced block (state before that line is processed).
    static func isInFence(_ text: NSString, lineStart: Int) -> Bool {
        var inFence = false
        var location = 0
        while location < lineStart, location < text.length {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            if isFence(content(of: text, lineRange: range)) { inFence.toggle() }
            location = NSMaxRange(range)
        }
        return inFence
    }

    static func content(of text: NSString, lineRange: NSRange) -> String {
        var r = lineRange
        while r.length > 0, text.character(at: r.location + r.length - 1) == 10 || text.character(at: r.location + r.length - 1) == 13 {
            r.length -= 1
        }
        return text.substring(with: r)
    }

    static func prefix(of line: String) -> Prefix? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = checkboxRegex.firstMatch(in: line, range: full) {
            let bracketOpen = m.range(at: 3).location - 1
            return Prefix(
                indent: ns.substring(with: m.range(at: 1)),
                kind: .checkbox(bullet: ns.substring(with: m.range(at: 2)), checked: ns.substring(with: m.range(at: 3)).lowercased() == "x"),
                length: m.range.length,
                bracket: NSRange(location: bracketOpen, length: 3)
            )
        }
        if let m = bulletRegex.firstMatch(in: line, range: full) {
            return Prefix(indent: ns.substring(with: m.range(at: 1)), kind: .bullet(ns.substring(with: m.range(at: 2))), length: m.range.length, bracket: nil)
        }
        if let m = orderedRegex.firstMatch(in: line, range: full), let n = Int(ns.substring(with: m.range(at: 2))) {
            return Prefix(indent: ns.substring(with: m.range(at: 1)), kind: .ordered(n, ns.substring(with: m.range(at: 3))), length: m.range.length, bracket: nil)
        }
        if let m = quoteRegex.firstMatch(in: line, range: full) {
            return Prefix(indent: ns.substring(with: m.range(at: 1)), kind: .quote, length: m.range.length, bracket: nil)
        }
        return nil
    }

    /// What Enter should do on `line` with the cursor `cursorColumn` UTF-16 units from the line start.
    static func continuation(for line: String, cursorColumn: Int) -> Continuation {
        guard let prefix = prefix(of: line), cursorColumn >= prefix.length else { return .none }
        let ns = line as NSString
        let rest = ns.substring(from: min(prefix.length, ns.length)).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return .clear(ns.length) }
        let marker: String
        switch prefix.kind {
        case .bullet(let b): marker = "\(b) "
        case .ordered(let n, let d): marker = "\(n + 1)\(d) "
        case .checkbox(let b, _): marker = "\(b) [ ] "
        case .quote: marker = "> "
        }
        return .insert("\n" + prefix.indent + marker)
    }

    /// Text of a line without list / checkbox / quote syntax (for turning a line into a task).
    static func plainContent(of line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let prefix = prefix(of: t) else { return t }
        return (t as NSString).substring(from: min(prefix.length, (t as NSString).length)).trimmingCharacters(in: .whitespaces)
    }

    static func safeURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }

    // MARK: - Inline

    private static func inline(_ line: String, from start: Int) -> [Span] {
        let ns = line as NSString
        guard start < ns.length else { return [] }
        let range = NSRange(location: start, length: ns.length - start)
        var spans: [Span] = []
        var protected: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !protected.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in codeRegex.matches(in: line, range: range) where free(m.range) {
            protected.append(m.range)
            spans.append(Span(range: m.range, kind: .code))
            spans.append(Span(range: NSRange(location: m.range.location, length: 1), kind: .marker))
            spans.append(Span(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1), kind: .marker))
        }
        for m in linkRegex.matches(in: line, range: range) where free(m.range) {
            let url = ns.substring(with: m.range(at: 2))
            guard safeURL(url) != nil else { continue }
            protected.append(m.range)
            let text = m.range(at: 1)
            spans.append(Span(range: text, kind: .link(url)))
            spans.append(Span(range: NSRange(location: m.range.location, length: 1), kind: .marker))
            let tail = NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text))
            spans.append(Span(range: tail, kind: .marker))
        }
        for m in urlRegex.matches(in: line, range: range) {
            var r = m.range
            while r.length > 1, ".,;:!?".contains(ns.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1))) { r.length -= 1 }
            guard free(r) else { continue }
            let url = ns.substring(with: r)
            guard safeURL(url) != nil else { continue }
            protected.append(r)
            spans.append(Span(range: r, kind: .link(url)))
        }
        let pairs: [(NSRegularExpression, Kind, Int)] = [(boldRegex, .bold, 2), (strikeRegex, .strike, 2), (italicStarRegex, .italic, 1), (italicUnderscoreRegex, .italic, 1)]
        for (regex, kind, width) in pairs {
            for m in regex.matches(in: line, range: range) where free(m.range) {
                spans.append(Span(range: m.range, kind: kind))
                spans.append(Span(range: NSRange(location: m.range.location, length: width), kind: .marker))
                spans.append(Span(range: NSRange(location: NSMaxRange(m.range) - width, length: width), kind: .marker))
            }
        }
        return spans
    }

    // MARK: - Regexes

    private static func re(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals; a failure is a programmer error caught by tests.
        (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression()
    }

    private static let headingRegex = re(#"^(#{1,3})[ \t]+"#)
    private static let fenceRegex = re(#"^[ \t]*```"#)
    private static let checkboxRegex = re(#"^([ \t]*)([-*+])[ \t]+\[([ xX])\](?:[ \t]+|$)"#)
    private static let bulletRegex = re(#"^([ \t]*)([-*+])[ \t]+"#)
    private static let orderedRegex = re(#"^([ \t]*)(\d{1,9})([.)])[ \t]+"#)
    private static let quoteRegex = re(#"^([ \t]*)>[ \t]?"#)
    private static let codeRegex = re(#"`[^`\n]+`"#)
    private static let linkRegex = re(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let urlRegex = re(#"https?://[^\s<>"')\]]+"#)
    private static let boldRegex = re(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    private static let strikeRegex = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let italicStarRegex = re(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#)
    private static let italicUnderscoreRegex = re(#"(?<![_\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_\w])"#)
}

private extension NSRegularExpression {
    nonisolated func firstMatch(in s: String, range: NSRange) -> NSTextCheckingResult? {
        firstMatch(in: s, options: [], range: range)
    }
    nonisolated func matches(in s: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: s, options: [], range: range)
    }
}
