import AppKit
import SwiftUI

// MARK: - Live Markdown Editor (Obsidian-style)

/// An `NSTextView`-based editor that hides markdown syntax markers on lines
/// the cursor is **not** on, showing only the rendered appearance (large
/// headings, bold, italic, etc.).  When the cursor moves onto a line, the raw
/// markers become visible so the user can edit them.  This mirrors the
/// "live preview" behaviour of editors like Obsidian and Typora.
struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator

        textView.string = text
        context.coordinator.rehighlight(textView)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard !context.coordinator.isInternalUpdate else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.rehighlight(textView)
            let length = (textView.string as NSString).length
            let valid = selectedRanges.compactMap { val -> NSValue? in
                let r = val.rangeValue
                guard r.location <= length else { return nil }
                return NSValue(range: NSRange(location: r.location,
                                              length: min(r.length, length - r.location)))
            }
            if !valid.isEmpty { textView.selectedRanges = valid }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LiveMarkdownEditor
        var isInternalUpdate = false

        init(_ parent: LiveMarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isInternalUpdate = true
            parent.text = textView.string
            rehighlight(textView)
            isInternalUpdate = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            rehighlight(textView)
        }

        func rehighlight(_ textView: NSTextView) {
            let cursorRange = activeParagraphRange(in: textView)
            MarkdownHighlighter.apply(to: textView.textStorage!, activeRange: cursorRange)
        }

        /// Returns the NSRange of the paragraph(s) that the cursor / selection
        /// currently spans, or `nil` when the text view has no selection.
        private func activeParagraphRange(in textView: NSTextView) -> NSRange? {
            guard let sel = textView.selectedRanges.first?.rangeValue else { return nil }
            let ns = textView.string as NSString
            guard ns.length > 0 else { return nil }
            return ns.paragraphRange(for: sel)
        }
    }
}

// MARK: - Syntax Highlighter

@MainActor
enum MarkdownHighlighter {

    // MARK: Fonts

    private static let bodySize: CGFloat = 15
    private static let bodyFont   = NSFont.systemFont(ofSize: bodySize)
    private static let boldFont   = NSFont.boldSystemFont(ofSize: bodySize)
    private static let italicFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    private static let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
    private static let monoFont   = NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
    /// Near-zero-size font used to collapse markers so they occupy no visual space.
    private static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    private static func headingFont(level: Int) -> NSFont {
        switch level {
        case 1:  return .systemFont(ofSize: 28, weight: .bold)
        case 2:  return .systemFont(ofSize: 24, weight: .bold)
        case 3:  return .systemFont(ofSize: 20, weight: .semibold)
        case 4:  return .systemFont(ofSize: 17, weight: .semibold)
        case 5:  return .systemFont(ofSize: 15, weight: .semibold)
        default: return .systemFont(ofSize: 14, weight: .semibold)
        }
    }

    // MARK: Colors

    private static let markerColor   = NSColor.tertiaryLabelColor
    private static let hiddenColor   = NSColor.textBackgroundColor
    private static let codeBG        = NSColor(white: 0.5, alpha: 0.06)
    private static let tableBG       = NSColor(white: 0.5, alpha: 0.04)
    private static let tableHeaderBG = NSColor(white: 0.5, alpha: 0.08)
    private static let tableBorderColor = NSColor.separatorColor
    private static let linkColor     = NSColor.systemBlue
    private static let quoteColor    = NSColor.secondaryLabelColor
    private static let ruleColor     = NSColor.separatorColor
    private static let checkboxDone  = NSColor.systemGreen
    private static let checkboxTodo  = NSColor.secondaryLabelColor

    // MARK: Paragraph style

    private static var defaultParagraph: NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        return ps
    }

    private static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.textColor, .paragraphStyle: defaultParagraph]
    }

    // MARK: - Public entry point

    static func apply(to storage: NSTextStorage, activeRange: NSRange?) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes(defaultAttributes, range: full)

        var codeRanges: [NSRange] = []
        codeRanges += applyCodeBlocks(storage, text, activeRange: activeRange)
        codeRanges += applyInlineCode(storage, text, skip: codeRanges, activeRange: activeRange)

        applyHeadings(storage, text, skip: codeRanges, activeRange: activeRange)
        applyBoldItalic(storage, text, skip: codeRanges, activeRange: activeRange)
        applyBold(storage, text, skip: codeRanges, activeRange: activeRange)
        applyItalic(storage, text, skip: codeRanges, activeRange: activeRange)
        applyStrikethrough(storage, text, skip: codeRanges, activeRange: activeRange)
        applyBlockquotes(storage, text, skip: codeRanges, activeRange: activeRange)
        applyLinks(storage, text, skip: codeRanges, activeRange: activeRange)
        applyHorizontalRules(storage, text, skip: codeRanges, activeRange: activeRange)
        applyListMarkers(storage, text, skip: codeRanges, activeRange: activeRange)
        applyTaskLists(storage, text, skip: codeRanges, activeRange: activeRange)
        applyTables(storage, text, skip: codeRanges, activeRange: activeRange)

        storage.endEditing()
    }

    // MARK: - Helpers

    private static func overlaps(_ range: NSRange, _ skip: [NSRange]) -> Bool {
        skip.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func isActive(_ range: NSRange, _ activeRange: NSRange?) -> Bool {
        guard let ar = activeRange else { return false }
        return NSIntersectionRange(ar, range).length > 0
    }

    /// Collapse a marker range on non-active lines: hidden colour **and**
    /// near-zero font so the characters occupy no visual space.  On the
    /// active line the markers are simply dimmed.
    private static func collapseMarker(_ s: NSTextStorage, _ range: NSRange,
                                        context: NSRange, activeRange: NSRange?) {
        if isActive(context, activeRange) {
            s.addAttribute(.foregroundColor, value: markerColor, range: range)
        } else {
            s.addAttribute(.foregroundColor, value: hiddenColor, range: range)
            s.addAttribute(.font, value: hiddenFont, range: range)
        }
    }

    private static func re(_ pattern: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: opts)
    }

    private static func matches(_ pattern: String, in text: String,
                                opts: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = re(pattern, opts) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    // MARK: - Fenced code blocks

    private static func applyCodeBlocks(_ s: NSTextStorage, _ t: String,
                                        activeRange: NSRange?) -> [NSRange] {
        var ranges: [NSRange] = []
        for m in matches("^(`{3,}|~{3,})([^\\n]*)\\n([\\s\\S]*?)\\n\\1[ \\t]*$", in: t, opts: .anchorsMatchLines) {
            let full = m.range
            ranges.append(full)
            s.addAttribute(.font, value: monoFont, range: full)
            s.addAttribute(.backgroundColor, value: codeBG, range: full)
            let fenceRange = m.range(at: 1)
            let closeFenceStart = full.location + full.length - fenceRange.length
            let closeFenceRange = NSRange(location: closeFenceStart, length: fenceRange.length)
            let openLineEnd = fenceRange.location + fenceRange.length + m.range(at: 2).length
            let openLineRange = NSRange(location: fenceRange.location, length: openLineEnd - fenceRange.location)
            collapseMarker(s, fenceRange, context: openLineRange, activeRange: activeRange)
            let langRange = m.range(at: 2)
            if langRange.length > 0 {
                collapseMarker(s, langRange, context: openLineRange, activeRange: activeRange)
            }
            collapseMarker(s, closeFenceRange, context: closeFenceRange, activeRange: activeRange)
        }
        return ranges
    }

    // MARK: - Inline code

    private static func applyInlineCode(_ s: NSTextStorage, _ t: String,
                                        skip: [NSRange], activeRange: NSRange?) -> [NSRange] {
        var ranges: [NSRange] = []
        for m in matches("`([^`\\n]+)`", in: t) {
            let full = m.range
            if overlaps(full, skip) { continue }
            ranges.append(full)
            s.addAttribute(.font, value: monoFont, range: full)
            s.addAttribute(.backgroundColor, value: codeBG, range: full)
            let openTick  = NSRange(location: full.location, length: 1)
            let closeTick = NSRange(location: full.location + full.length - 1, length: 1)
            collapseMarker(s, openTick, context: full, activeRange: activeRange)
            collapseMarker(s, closeTick, context: full, activeRange: activeRange)
        }
        return ranges
    }

    // MARK: - Headings

    private static func applyHeadings(_ s: NSTextStorage, _ t: String,
                                      skip: [NSRange], activeRange: NSRange?) {
        for m in matches("^(#{1,6})( .+)$", in: t, opts: .anchorsMatchLines) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let hashRange = m.range(at: 1)
            s.addAttribute(.font, value: headingFont(level: hashRange.length), range: full)
            if isActive(full, activeRange) {
                s.addAttribute(.foregroundColor, value: markerColor, range: hashRange)
            } else {
                // Collapse hash marks + leading space so heading text starts flush-left
                let markerLen = hashRange.length + 1
                let markerWithSpace = NSRange(location: hashRange.location, length: markerLen)
                s.addAttribute(.foregroundColor, value: hiddenColor, range: markerWithSpace)
                s.addAttribute(.font, value: hiddenFont, range: markerWithSpace)
            }
        }
    }

    // MARK: - Bold + Italic (***text***)

    private static func applyBoldItalic(_ s: NSTextStorage, _ t: String,
                                        skip: [NSRange], activeRange: NSRange?) {
        for m in matches("(\\*{3}|_{3})(?=\\S)(.+?)(?<=\\S)\\1", in: t) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let mk = m.range(at: 1)
            let ct = m.range(at: 2)
            s.addAttribute(.font, value: boldItalicFont, range: ct)
            let closeMk = NSRange(location: full.location + full.length - mk.length, length: mk.length)
            collapseMarker(s, mk, context: full, activeRange: activeRange)
            collapseMarker(s, closeMk, context: full, activeRange: activeRange)
        }
    }

    // MARK: - Bold

    private static func applyBold(_ s: NSTextStorage, _ t: String,
                                  skip: [NSRange], activeRange: NSRange?) {
        for m in matches("(\\*{2}|_{2})(?=\\S)(.+?)(?<=\\S)\\1", in: t) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let mk = m.range(at: 1)
            let ct = m.range(at: 2)
            if let f = s.attribute(.font, at: ct.location, effectiveRange: nil) as? NSFont,
               f == boldItalicFont { continue }
            s.addAttribute(.font, value: boldFont, range: ct)
            let closeMk = NSRange(location: full.location + full.length - mk.length, length: mk.length)
            collapseMarker(s, mk, context: full, activeRange: activeRange)
            collapseMarker(s, closeMk, context: full, activeRange: activeRange)
        }
    }

    // MARK: - Italic

    private static func applyItalic(_ s: NSTextStorage, _ t: String,
                                    skip: [NSRange], activeRange: NSRange?) {
        for m in matches("(?<![\\*_])(\\*|_)(?=\\S)(.+?)(?<=\\S)\\1(?![\\*_])", in: t) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let mk = m.range(at: 1)
            let ct = m.range(at: 2)
            if let f = s.attribute(.font, at: ct.location, effectiveRange: nil) as? NSFont,
               f == boldFont || f == boldItalicFont { continue }
            s.addAttribute(.font, value: italicFont, range: ct)
            let closeMk = NSRange(location: full.location + full.length - 1, length: 1)
            collapseMarker(s, mk, context: full, activeRange: activeRange)
            collapseMarker(s, closeMk, context: full, activeRange: activeRange)
        }
    }

    // MARK: - Strikethrough

    private static func applyStrikethrough(_ s: NSTextStorage, _ t: String,
                                           skip: [NSRange], activeRange: NSRange?) {
        for m in matches("~~(?=\\S)(.+?)(?<=\\S)~~", in: t) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let ct = m.range(at: 1)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: ct)
            let openMk = NSRange(location: full.location, length: 2)
            let closeMk = NSRange(location: full.location + full.length - 2, length: 2)
            collapseMarker(s, openMk, context: full, activeRange: activeRange)
            collapseMarker(s, closeMk, context: full, activeRange: activeRange)
        }
    }

    // MARK: - Blockquotes

    private static func applyBlockquotes(_ s: NSTextStorage, _ t: String,
                                         skip: [NSRange], activeRange: NSRange?) {
        for m in matches("^(>+)(.*)$", in: t, opts: .anchorsMatchLines) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let mk = m.range(at: 1)
            s.addAttribute(.foregroundColor, value: quoteColor, range: full)
            collapseMarker(s, mk, context: full, activeRange: activeRange)
            let ps = NSMutableParagraphStyle()
            ps.headIndent = 20
            ps.firstLineHeadIndent = 0
            ps.lineSpacing = 4
            s.addAttribute(.paragraphStyle, value: ps, range: full)
        }
    }

    // MARK: - Links & images

    private static func applyLinks(_ s: NSTextStorage, _ t: String,
                                   skip: [NSRange], activeRange: NSRange?) {
        for m in matches("(!?\\[)([^\\]]*)(\\]\\()([^)]*)(\\))", in: t) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let openBracket = m.range(at: 1)
            let textRange   = m.range(at: 2)
            let midPart     = m.range(at: 3)
            let urlRange    = m.range(at: 4)
            let closeParen  = m.range(at: 5)
            s.addAttribute(.foregroundColor, value: linkColor, range: textRange)
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            for r in [openBracket, midPart, urlRange, closeParen] {
                collapseMarker(s, r, context: full, activeRange: activeRange)
            }
        }
    }

    // MARK: - Horizontal rules

    private static func applyHorizontalRules(_ s: NSTextStorage, _ t: String,
                                             skip: [NSRange], activeRange: NSRange?) {
        for m in matches("^([-*_][ ]*){3,}$", in: t, opts: .anchorsMatchLines) {
            let full = m.range
            if overlaps(full, skip) { continue }
            s.addAttribute(.foregroundColor, value: ruleColor, range: full)
            if !isActive(full, activeRange) {
                s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full)
            }
        }
    }

    // MARK: - List markers

    private static func applyListMarkers(_ s: NSTextStorage, _ t: String,
                                         skip: [NSRange], activeRange: NSRange?) {
        for m in matches("^([ \\t]*)([-*+]|\\d+\\.)( )", in: t, opts: .anchorsMatchLines) {
            if overlaps(m.range, skip) { continue }
            let mk = m.range(at: 2)
            s.addAttribute(.foregroundColor, value: linkColor, range: mk)
        }
    }

    // MARK: - Task lists  (- [ ] / - [x])

    private static func applyTaskLists(_ s: NSTextStorage, _ t: String,
                                       skip: [NSRange], activeRange: NSRange?) {
        for m in matches("^([ \\t]*- )(\\[([ xX])\\])( )", in: t, opts: .anchorsMatchLines) {
            let full = m.range
            if overlaps(full, skip) { continue }
            let checkboxRange = m.range(at: 2)  // [x] or [ ]
            let markChar = m.range(at: 3)        // x, X, or space
            let ns = t as NSString
            let isDone = ns.substring(with: markChar).lowercased() == "x"

            if isActive(full, activeRange) {
                // Show markers dimmed on active line
                s.addAttribute(.foregroundColor, value: isDone ? checkboxDone : checkboxTodo,
                               range: checkboxRange)
            } else {
                // Replace [x] with ☑ and [ ] with ☐ visually by:
                // - Hiding the brackets
                let openBracket = NSRange(location: checkboxRange.location, length: 1)
                let closeBracket = NSRange(location: checkboxRange.location + checkboxRange.length - 1, length: 1)
                s.addAttribute(.foregroundColor, value: hiddenColor, range: openBracket)
                s.addAttribute(.font, value: hiddenFont, range: openBracket)
                s.addAttribute(.foregroundColor, value: hiddenColor, range: closeBracket)
                s.addAttribute(.font, value: hiddenFont, range: closeBracket)
                // - Colouring the mark character
                s.addAttribute(.foregroundColor, value: isDone ? checkboxDone : checkboxTodo,
                               range: markChar)
                // Also collapse the trailing space after checkbox
                let trailingSpace = m.range(at: 4)
                s.addAttribute(.foregroundColor, value: hiddenColor, range: trailingSpace)
                s.addAttribute(.font, value: hiddenFont, range: trailingSpace)
            }
        }
    }

    // MARK: - Tables

    /// Detect table blocks (consecutive lines starting/ending with `|`) and
    /// apply monospaced font, background colour, and styled separators.
    private static func applyTables(_ s: NSTextStorage, _ t: String,
                                    skip: [NSRange], activeRange: NSRange?) {
        let ns = t as NSString
        let lines = splitLines(ns)
        var i = 0
        while i < lines.count {
            // A table must have at least a header row and a separator row.
            guard isTableRow(ns, lines[i]),
                  i + 1 < lines.count,
                  isTableSeparator(ns, lines[i + 1]) else {
                i += 1
                continue
            }
            let tableStart = i
            var tableEnd = i + 1
            // Extend to all consecutive table rows
            while tableEnd + 1 < lines.count && isTableRow(ns, lines[tableEnd + 1]) {
                tableEnd += 1
            }
            let headerLine = lines[tableStart]
            let sepLine    = lines[tableStart + 1]

            // Apply mono font + background to the whole table block
            let tableRange = NSRange(location: headerLine.location,
                                     length: NSMaxRange(lines[tableEnd]) - headerLine.location)
            if overlaps(tableRange, skip) { i = tableEnd + 1; continue }

            let active = isActive(tableRange, activeRange)

            // Mono font for alignment
            s.addAttribute(.font, value: monoFont, range: tableRange)

            // Header row: bold + header background
            s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .semibold),
                           range: headerLine)
            s.addAttribute(.backgroundColor, value: tableHeaderBG, range: headerLine)

            // Body rows: light background
            for row in (tableStart + 2)...tableEnd where row < lines.count {
                s.addAttribute(.backgroundColor, value: tableBG, range: lines[row])
            }

            // Separator row: dim or collapse
            if active {
                s.addAttribute(.foregroundColor, value: ruleColor, range: sepLine)
            } else {
                s.addAttribute(.foregroundColor, value: hiddenColor, range: sepLine)
                s.addAttribute(.font, value: hiddenFont, range: sepLine)
            }

            // Style pipe characters in all rows (except separator)
            for row in tableStart...tableEnd where row != tableStart + 1 {
                stylePipes(s, in: lines[row], ns: ns, color: tableBorderColor)
            }

            i = tableEnd + 1
        }
    }

    /// Split text into line ranges.
    private static func splitLines(_ ns: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var loc = 0
        while loc < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            // Trim the trailing newline for the range we store
            var contentLen = lineRange.length
            if contentLen > 0 && ns.character(at: lineRange.location + contentLen - 1) == 0x0A /* \n */ {
                contentLen -= 1
            }
            lines.append(NSRange(location: lineRange.location, length: contentLen))
            loc = NSMaxRange(lineRange)
        }
        return lines
    }

    private static func isTableRow(_ ns: NSString, _ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let line = ns.substring(with: range).trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("|") && line.hasSuffix("|") && line.count >= 3
    }

    private static func isTableSeparator(_ ns: NSString, _ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let line = ns.substring(with: range).trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("|") && line.hasSuffix("|") else { return false }
        // Must contain only |, -, :, and spaces
        let inner = line.dropFirst().dropLast()
        return !inner.isEmpty && inner.allSatisfy { "|-: ".contains($0) }
    }

    /// Colour pipe `|` characters within a line range.
    private static func stylePipes(_ s: NSTextStorage, in range: NSRange,
                                   ns: NSString, color: NSColor) {
        let pipe: unichar = 0x7C // |
        for offset in 0..<range.length {
            if ns.character(at: range.location + offset) == pipe {
                let r = NSRange(location: range.location + offset, length: 1)
                s.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
    }
}
