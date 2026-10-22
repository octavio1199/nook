import Foundation
import Testing
@testable import Nook

struct MarkdownStylerTests {
    func kinds(_ line: String, inFence: Bool = false) -> [MarkdownStyler.Span] {
        MarkdownStyler.style(line: line, inFence: inFence).spans
    }

    func text(_ line: String, _ span: MarkdownStyler.Span) -> String {
        (line as NSString).substring(with: span.range)
    }

    func first(_ line: String, _ kind: MarkdownStyler.Kind) -> String? {
        kinds(line).first { $0.kind == kind }.map { text(line, $0) }
    }

    @Test func headings() {
        #expect(first("## Title", .heading(2)) == "## Title")
        #expect(first("## Title", .marker) == "## ")
        #expect(first("#### nope", .heading(3)) == nil)
        #expect(first("#hashtag", .heading(1)) == nil)
    }

    @Test func inlineStyles() {
        #expect(first("a **bold** b", .bold) == "**bold**")
        #expect(first("a *it* b", .italic) == "*it*")
        #expect(first("a _it_ b", .italic) == "_it_")
        #expect(first("a ~~gone~~ b", .strike) == "~~gone~~")
        #expect(first("run `ls -la` now", .code) == "`ls -la`")
        #expect(first("snake_case_word", .italic) == nil)
    }

    @Test func markersAreDimmed() {
        let markers = kinds("**b**").filter { $0.kind == .marker }.map { text("**b**", $0) }
        #expect(markers == ["**", "**"])
    }

    @Test func codeProtectsContents() {
        #expect(first("`**not bold**`", .bold) == nil)
    }

    @Test func lists() {
        #expect(first("- item", .listMarker) == "-")
        #expect(first("  * item", .listMarker) == "*")
        #expect(first("12. item", .listMarker) == "12.")
        #expect(MarkdownStyler.style(line: "- item", inFence: false).prefixLength == 2)
        #expect(first("*italic* start", .listMarker) == nil)
    }

    @Test func checkboxes() {
        #expect(first("- [ ] todo", .checkbox) == "[ ]")
        #expect(first("- [ ] todo", .done) == nil)
        #expect(first("- [x] done it", .checkbox) == "[x]")
        #expect(first("- [x] done it", .done) == "done it")
    }

    @Test func quotes() {
        #expect(first("> wise", .quote) == "wise")
        #expect(first("> wise", .marker) == ">")
    }

    @Test func links() {
        #expect(first("see [docs](https://a.com/x) ok", .link("https://a.com/x")) == "docs")
        #expect(first("go https://a.com/x.", .link("https://a.com/x")) == "https://a.com/x")
        #expect(first("[x](javascript:alert(1))", .link("javascript:alert(1)")) == nil)
        #expect(first("[m](mailto:a@b.co)", .link("mailto:a@b.co")) == "m")
        #expect(MarkdownStyler.safeURL("file:///etc/passwd") == nil)
    }

    @Test func fences() {
        #expect(MarkdownStyler.style(line: "```swift", inFence: false).isFence)
        #expect(kinds("let x = 1", inFence: true).first?.kind == .codeBlock)
        let doc = "a\n```\ncode\n```\nb" as NSString
        #expect(MarkdownStyler.isInFence(doc, lineStart: 6))
        #expect(!MarkdownStyler.isInFence(doc, lineStart: 15))
    }

    @Test func sentLines() {
        #expect(first("→ call Ana", .sentArrow) == "→")
        #expect(first("→ call Ana", .sent) == "→ call Ana")
    }

    @Test func continuation() {
        #expect(MarkdownStyler.continuation(for: "- a", cursorColumn: 3) == .insert("\n- "))
        #expect(MarkdownStyler.continuation(for: "  - a", cursorColumn: 5) == .insert("\n  - "))
        #expect(MarkdownStyler.continuation(for: "- [x] a", cursorColumn: 7) == .insert("\n- [ ] "))
        #expect(MarkdownStyler.continuation(for: "2. a", cursorColumn: 4) == .insert("\n3. "))
        #expect(MarkdownStyler.continuation(for: "> q", cursorColumn: 3) == .insert("\n> "))
        #expect(MarkdownStyler.continuation(for: "- ", cursorColumn: 2) == .clear(2))
        #expect(MarkdownStyler.continuation(for: "- [ ] ", cursorColumn: 6) == .clear(6))
        #expect(MarkdownStyler.continuation(for: "plain", cursorColumn: 5) == .none)
        #expect(MarkdownStyler.continuation(for: "- a", cursorColumn: 1) == .none)
    }

    @Test func plainContent() {
        #expect(MarkdownStyler.plainContent(of: "- [ ] buy milk") == "buy milk")
        #expect(MarkdownStyler.plainContent(of: "1. call Ana") == "call Ana")
        #expect(MarkdownStyler.plainContent(of: "just text") == "just text")
    }
}
