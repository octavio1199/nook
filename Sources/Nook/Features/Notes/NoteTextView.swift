import AppKit
import SwiftUI

/// Plain-text NSTextView that reports ⌘↩.
final class NoteNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command), window?.firstResponder === self {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    /// Receives the current line; returns true when it was turned into task(s).
    var onSendLine: (String) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let tv = NoteNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 0

        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = Self.font
        tv.textColor = Self.color
        tv.insertionPointColor = NSColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 0.35)]
        tv.typingAttributes = Self.attributes
        tv.delegate = context.coordinator
        tv.string = text
        tv.onCommandReturn = { [weak coordinator = context.coordinator] in coordinator?.sendLine() }

        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView, tv.string != text else { return }
        let selection = tv.selectedRange()
        tv.string = text
        tv.textStorage?.setAttributes(Self.attributes, range: NSRange(location: 0, length: (text as NSString).length))
        let length = (text as NSString).length
        tv.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        tv.undoManager?.removeAllActions()
    }

    static let font = NSFont.systemFont(ofSize: 12.5)
    static let color = NSColor.white.withAlphaComponent(0.94)
    static var attributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var textView: NoteNSTextView?

        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, parent.text != tv.string else { return }
            parent.text = tv.string
        }

        /// ⌘↩: send the current line to the planner and mark it as sent.
        func sendLine() {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let location = min(tv.selectedRange().location, ns.length)
            let full = ns.lineRange(for: NSRange(location: location, length: 0))
            var content = full
            while content.length > 0, ["\n", "\r"].contains(ns.substring(with: NSRange(location: content.location + content.length - 1, length: 1))) {
                content.length -= 1
            }
            let line = ns.substring(with: content).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("→ "), !line.hasPrefix("✓ ") else { return }
            guard parent.onSendLine(line) else { return }
            let replacement = "→ " + line
            if tv.shouldChangeText(in: content, replacementString: replacement) {
                tv.replaceCharacters(in: content, with: replacement)
                tv.textStorage?.addAttributes(NoteTextView.attributes, range: NSRange(location: content.location, length: (replacement as NSString).length))
                tv.didChangeText()
            }
            tv.setSelectedRange(NSRange(location: content.location + (replacement as NSString).length, length: 0))
        }
    }
}
