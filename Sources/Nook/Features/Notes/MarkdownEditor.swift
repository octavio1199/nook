import AppKit
import SwiftUI

// MARK: - Theme

enum MarkdownTheme {
    static let fontSize: CGFloat = 12.5
    static let font = NSFont.systemFont(ofSize: fontSize)
    static let accent = NSColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1)
    static let primary = NSColor.white.withAlphaComponent(0.94)
    static let secondary = NSColor.white.withAlphaComponent(0.58)
    static let tertiary = NSColor.white.withAlphaComponent(0.36)
    static let codeBackground = NSColor.white.withAlphaComponent(0.09)
    static let blockBackground = NSColor.white.withAlphaComponent(0.06)

    static func paragraphStyle(headIndent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.headIndent = headIndent
        return style
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: primary, .paragraphStyle: paragraphStyle()]
    }
}

// MARK: - Text view

/// Plain-text NSTextView with smart markdown editing, checkbox/link clicks, ⌘↩ and a placeholder.
final class MarkdownNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    /// Told when the text view gains or loses keyboard focus.
    var onFocusChange: ((Bool) -> Void)?
    var placeholder = "" { didSet { needsDisplay = true } }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only ⌘↩ is intercepted; ⌘C/⌘V/⌘X/⌘Z keep flowing to the Edit menu.
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command), window?.firstResponder === self {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        placeholder.draw(
            at: NSPoint(x: origin.x + padding, y: origin.y),
            withAttributes: [.font: MarkdownTheme.font, .foregroundColor: MarkdownTheme.tertiary]
        )
    }

    override func didChangeText() {
        super.didChangeText()
        if string.isEmpty { needsDisplay = true }
    }

    // MARK: Smart editing

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.length == 0 else { return super.insertNewline(sender) }
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        if MarkdownStyler.isInFence(ns, lineStart: lineRange.location) { return super.insertNewline(sender) }
        let line = MarkdownStyler.content(of: ns, lineRange: lineRange)
        switch MarkdownStyler.continuation(for: line, cursorColumn: sel.location - lineRange.location) {
        case .none:
            super.insertNewline(sender)
        case .insert(let text):
            insertText(text, replacementRange: sel)
        case .clear(let length):
            replace(NSRange(location: lineRange.location, length: length), with: "", caret: lineRange.location)
        }
    }

    override func insertTab(_ sender: Any?) {
        if !shiftIndent(outdent: false) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !shiftIndent(outdent: true) { super.insertBacktab(sender) }
    }

    private func replace(_ range: NSRange, with text: String, caret: Int) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    /// Indents / outdents the list lines in the selection by 2 spaces. Returns false when no list line is involved.
    private func shiftIndent(outdent: Bool) -> Bool {
        let ns = string as NSString
        let sel = selectedRange()
        let block = ns.lineRange(for: sel)
        var lines: [(text: String, terminator: String)] = []
        var location = block.location
        var anyList = false
        while location < NSMaxRange(block) {
            let range = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = MarkdownStyler.content(of: ns, lineRange: range)
            let terminator = ns.substring(with: NSRange(location: range.location + (content as NSString).length, length: range.length - (content as NSString).length))
            if MarkdownStyler.prefix(of: content) != nil, !MarkdownStyler.isInFence(ns, lineStart: range.location) { anyList = true }
            lines.append((content, terminator))
            location = NSMaxRange(range)
        }
        guard anyList else { return false }

        var firstDelta = 0
        var totalDelta = 0
        var out = ""
        for (i, line) in lines.enumerated() {
            var text = line.text
            var delta = 0
            if MarkdownStyler.prefix(of: text) != nil {
                if outdent {
                    if text.hasPrefix("  ") { text.removeFirst(2); delta = -2 }
                    else if text.hasPrefix(" ") || text.hasPrefix("\t") { text.removeFirst(1); delta = -1 }
                } else {
                    text = "  " + text; delta = 2
                }
            }
            if i == 0 { firstDelta = delta }
            totalDelta += delta
            out += text + line.terminator
        }
        guard totalDelta != 0 else { return true }
        guard shouldChangeText(in: block, replacementString: out) else { return true }
        replaceCharacters(in: block, with: out)
        didChangeText()
        let start = max(block.location, sel.location + firstDelta)
        let end = max(start, NSMaxRange(sel) + totalDelta)
        setSelectedRange(NSRange(location: start, length: end - start))
        return true
    }

    // MARK: Clicks (checkboxes + links)

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, handleClick(event) { return }
        super.mouseDown(with: event)
    }

    private func handleClick(_ event: NSEvent) -> Bool {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let p = convert(event.locationInWindow, from: nil)
        let tp = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: tp, in: tc)
        guard glyph < lm.numberOfGlyphs, lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc).insetBy(dx: -1, dy: -1).contains(tp) else { return false }
        let index = lm.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return false }

        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
        let line = MarkdownStyler.content(of: ns, lineRange: lineRange)
        if let prefix = MarkdownStyler.prefix(of: line), let bracket = prefix.bracket,
           !MarkdownStyler.isInFence(ns, lineStart: lineRange.location) {
            let local = index - lineRange.location
            if local >= bracket.location, local < NSMaxRange(bracket), case .checkbox(_, let checked) = prefix.kind {
                let target = NSRange(location: lineRange.location + bracket.location + 1, length: 1)
                let caret = selectedRange()
                if shouldChangeText(in: target, replacementString: checked ? " " : "x") {
                    replaceCharacters(in: target, with: checked ? " " : "x")
                    didChangeText()
                    setSelectedRange(caret)
                }
                return true
            }
        }
        if !event.modifierFlags.contains(.option), let value = storage.attribute(.link, at: index, effectiveRange: nil) {
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            if let url, let safe = MarkdownStyler.safeURL(url.absoluteString) {
                NSWorkspace.shared.open(safe)
                return true
            }
        }
        return false
    }
}

// MARK: - SwiftUI wrapper

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Receives the current line. Return true when it was consumed (the editor then marks the line with a "→ " prefix).
    var onCommandReturn: ((String) -> Bool)?
    var wrapsLines: Bool
    /// When set, the editor takes (true) or gives up (false) keyboard focus to match.
    var wantsFocus: Bool?
    var onFocusChange: ((Bool) -> Void)?

    init(
        text: Binding<String>, placeholder: String = "", onCommandReturn: ((String) -> Bool)? = nil, wrapsLines: Bool = true,
        wantsFocus: Bool? = nil, onFocusChange: ((Bool) -> Void)? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.onCommandReturn = onCommandReturn
        self.wrapsLines = wrapsLines
        self.wantsFocus = wantsFocus
        self.onFocusChange = onFocusChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WrappingScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let tv = MarkdownNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 3
        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.font = MarkdownTheme.font
        tv.textColor = MarkdownTheme.primary
        tv.insertionPointColor = MarkdownTheme.accent
        tv.selectedTextAttributes = [.backgroundColor: MarkdownTheme.accent.withAlphaComponent(0.35)]
        tv.linkTextAttributes = [.foregroundColor: MarkdownTheme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
        tv.typingAttributes = MarkdownTheme.baseAttributes
        tv.placeholder = placeholder
        tv.delegate = context.coordinator
        tv.textStorage?.delegate = context.coordinator
        tv.onCommandReturn = { [weak coordinator = context.coordinator] in coordinator?.commandReturn() }
        tv.onFocusChange = { [weak coordinator = context.coordinator] focused in coordinator?.parent.onFocusChange?(focused) }

        scroll.documentView = tv
        context.coordinator.textView = tv
        Self.configureWrapping(scroll: scroll, textView: tv, wraps: wrapsLines)
        context.coordinator.wraps = wrapsLines
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let tv = coordinator.textView else { return }
        if tv.placeholder != placeholder { tv.placeholder = placeholder }
        if let wants = wantsFocus {
            // After this update pass, so a text field taking focus at the same time wins.
            DispatchQueue.main.async { [weak tv] in
                guard let tv, let window = tv.window else { return }
                let focused = window.firstResponder === tv
                if wants, !focused { window.makeFirstResponder(tv) }
                if !wants, focused { window.makeFirstResponder(nil) }
            }
        }
        if coordinator.wraps != wrapsLines {
            coordinator.wraps = wrapsLines
            Self.configureWrapping(scroll: scroll, textView: tv, wraps: wrapsLines)
        }
        guard tv.string != text else { return }
        let selection = tv.selectedRange()
        tv.string = text // delegate restyles the whole range
        let length = (text as NSString).length
        tv.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        tv.undoManager?.removeAllActions()
    }

    private static func configureWrapping(scroll: NSScrollView, textView tv: NSTextView, wraps: Bool) {
        guard let container = tv.textContainer else { return }
        (scroll as? WrappingScrollView)?.wraps = wraps
        let width = max(scroll.contentSize.width, 200)
        if wraps {
            scroll.hasHorizontalScroller = false
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            tv.setFrameSize(NSSize(width: width, height: tv.frame.height))
        } else {
            scroll.hasHorizontalScroller = true
            tv.isHorizontallyResizable = true
            tv.autoresizingMask = []
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.minSize = NSSize(width: width, height: 0)
        }
        tv.layoutManager?.ensureLayout(for: container)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        weak var textView: MarkdownNSTextView?
        var wraps = true
        private var fenceCount = 0

        /// Each editor keeps its own text undo, separate from the task undo stack on the panel.
        let undo = UndoManager()

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, parent.text != tv.string else { return }
            parent.text = tv.string
        }

        // MARK: Styling

        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            nonisolated(unsafe) let storage = textStorage
            MainActor.assumeIsolated { restyle(storage, edited: editedRange) }
        }

        private func restyle(_ storage: NSTextStorage, edited: NSRange) {
            let ns = storage.string as NSString
            var range = ns.paragraphRange(for: NSRange(location: min(edited.location, ns.length), length: min(edited.length, max(0, ns.length - edited.location))))
            // A changed number of ``` markers shifts every following paragraph.
            let count = Self.fenceMarkerCount(ns)
            if count != fenceCount {
                fenceCount = count
                range = NSRange(location: range.location, length: ns.length - range.location)
            }
            guard ns.length > 0 else { return }
            var inFence = MarkdownStyler.isInFence(ns, lineStart: range.location)
            var location = range.location
            while location < NSMaxRange(range) {
                let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
                let line = MarkdownStyler.content(of: ns, lineRange: lineRange)
                let result = MarkdownStyler.style(line: line, inFence: inFence)
                if result.isFence { inFence.toggle() }
                Self.apply(result, line: line, at: lineRange, to: storage)
                location = NSMaxRange(lineRange)
            }
        }

        private static func fenceMarkerCount(_ ns: NSString) -> Int {
            var count = 0
            var from = 0
            while from < ns.length {
                let r = ns.range(of: "```", range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                count += 1
                from = NSMaxRange(r)
            }
            return count
        }

        private static func apply(_ result: MarkdownStyler.Result, line: String, at lineRange: NSRange, to storage: NSTextStorage) {
            var indent: CGFloat = 0
            if result.prefixLength > 0 {
                let prefix = (line as NSString).substring(to: result.prefixLength)
                indent = ceil((prefix as NSString).size(withAttributes: [.font: MarkdownTheme.font]).width)
            }
            var base = MarkdownTheme.baseAttributes
            if indent > 0 { base[.paragraphStyle] = MarkdownTheme.paragraphStyle(headIndent: indent) }
            storage.setAttributes(base, range: lineRange)
            for span in result.spans {
                let r = NSRange(location: lineRange.location + span.range.location, length: span.range.length)
                guard r.length > 0, NSMaxRange(r) <= NSMaxRange(lineRange) else { continue }
                style(span.kind, range: r, storage: storage)
            }
        }

        private static func transformFont(_ storage: NSTextStorage, _ range: NSRange, _ transform: (NSFont) -> NSFont) {
            var runs: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: range) { value, r, _ in
                runs.append((r, (value as? NSFont) ?? MarkdownTheme.font))
            }
            for (r, font) in runs { storage.addAttribute(.font, value: transform(font), range: r) }
        }

        private static func style(_ kind: MarkdownStyler.Kind, range r: NSRange, storage: NSTextStorage) {
            let fm = NSFontManager.shared
            switch kind {
            case .heading(let level):
                let size: CGFloat = [17, 15, 13.5][min(max(level, 1), 3) - 1]
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: r)
            case .marker:
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.tertiary, range: r)
            case .bold:
                transformFont(storage, r) { fm.convert($0, toHaveTrait: .boldFontMask) }
            case .italic:
                transformFont(storage, r) { fm.convert($0, toHaveTrait: .italicFontMask) }
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: MarkdownTheme.secondary], range: r)
            case .code:
                transformFont(storage, r) { NSFont.monospacedSystemFont(ofSize: $0.pointSize * 0.92, weight: .regular) }
                storage.addAttributes([.backgroundColor: MarkdownTheme.codeBackground, .foregroundColor: NSColor.white.withAlphaComponent(0.88)], range: r)
            case .codeBlock:
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: MarkdownTheme.fontSize * 0.92, weight: .regular),
                    .backgroundColor: MarkdownTheme.blockBackground,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                ], range: r)
            case .fence:
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: MarkdownTheme.fontSize * 0.92, weight: .regular),
                    .backgroundColor: MarkdownTheme.blockBackground,
                    .foregroundColor: MarkdownTheme.tertiary,
                ], range: r)
            case .quote:
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: r)
            case .listMarker:
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent.withAlphaComponent(0.85), range: r)
            case .checkbox:
                storage.addAttributes([.foregroundColor: MarkdownTheme.tertiary, .font: NSFont.monospacedSystemFont(ofSize: MarkdownTheme.fontSize * 0.95, weight: .medium)], range: r)
            case .done:
                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.tertiary,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: MarkdownTheme.tertiary,
                ], range: r)
            case .link(let url):
                storage.addAttributes([.link: url, .foregroundColor: MarkdownTheme.accent], range: r)
            case .sentArrow:
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent.withAlphaComponent(0.8), range: r)
            case .sent:
                storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.4), range: r)
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let raw = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
            guard let url = MarkdownStyler.safeURL(raw) else { return true }
            NSWorkspace.shared.open(url)
            return true
        }

        // MARK: ⌘↩

        /// Sends the current line to the host; when consumed, marks it with "→ ".
        func commandReturn() {
            guard let tv = textView, let handler = parent.onCommandReturn else { return }
            let ns = tv.string as NSString
            let location = min(tv.selectedRange().location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = NSRange(location: lineRange.location, length: (MarkdownStyler.content(of: ns, lineRange: lineRange) as NSString).length)
            let line = ns.substring(with: content).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("→ "), !line.hasPrefix("✓ ") else { return }
            guard handler(line) else { return }
            let replacement = "→ " + ns.substring(with: content)
            if tv.shouldChangeText(in: content, replacementString: replacement) {
                tv.replaceCharacters(in: content, with: replacement)
                tv.didChangeText()
            }
            tv.setSelectedRange(NSRange(location: content.location + (replacement as NSString).length, length: 0))
        }
    }
}

/// Keeps the text view exactly as wide as the visible area while wrapping. Autoresizing alone
/// keeps the width offset from the first layout pass, which let long lines run past the edge.
final class WrappingScrollView: NSScrollView {
    var wraps = true

    override func tile() {
        super.tile()
        syncDocumentWidth()
    }

    override func layout() {
        super.layout()
        syncDocumentWidth()
    }

    /// SwiftUI can resize the column without a tile pass, so sync on layout too, and keep the
    /// text container in step even if the text view frame already matches.
    private func syncDocumentWidth() {
        guard wraps, let doc = documentView as? NSTextView, contentSize.width > 0 else { return }
        if doc.frame.width != contentSize.width {
            doc.setFrameSize(NSSize(width: contentSize.width, height: doc.frame.height))
        }
        if let container = doc.textContainer {
            let width = contentSize.width - doc.textContainerInset.width * 2
            if abs(container.containerSize.width - width) > 0.5 {
                container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }
}
