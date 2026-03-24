import Foundation

// MARK: - Block Type

enum MarkdownBlockType {
    case heading
    case paragraph
    case codeBlock
    case list
    case table
    case blockquote
    case horizontalRule
    case separator          // blank-line spacer between blocks
}

// MARK: - Block Model

struct MarkdownBlock: Identifiable, Equatable {
    let id: UUID
    var text: String
    var blockType: MarkdownBlockType

    /// Whether this block type naturally contains multiple lines (Enter adds a new
    /// line instead of committing the edit).
    var isMultiLine: Bool {
        switch blockType {
        case .codeBlock, .list, .table, .blockquote:
            return true
        case .heading, .paragraph, .horizontalRule, .separator:
            return false
        }
    }
}

// MARK: - Block Parser

enum MarkdownBlockParser {

    /// Split a raw markdown string into an ordered array of ``MarkdownBlock``s.
    ///
    /// Rules
    /// ─────
    /// • Fenced code blocks (``` / ~~~) are kept as single blocks even when they
    ///   contain internal blank lines.
    /// • Outside of code fences, consecutive non-blank lines form one block.
    /// • One or more blank lines between blocks become a single `.separator` block.
    static func parse(_ content: String) -> [MarkdownBlock] {
        guard !content.isEmpty else { return [] }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var currentLines: [String] = []
        var insideFence = false
        var fenceMarker = ""          // "```" or "~~~" (the opening marker)

        func flushCurrent() {
            guard !currentLines.isEmpty else { return }
            let text = currentLines.joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                blocks.append(MarkdownBlock(id: UUID(), text: "", blockType: .separator))
            } else {
                blocks.append(MarkdownBlock(id: UUID(), text: text, blockType: detectType(text)))
            }
            currentLines = []
        }

        for line in lines {
            // ── Fence toggle ───────────────────────────────────────
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if !insideFence {
                if stripped.hasPrefix("```") || stripped.hasPrefix("~~~") {
                    // Start a new code fence – flush whatever we have so far.
                    flushCurrent()
                    fenceMarker = String(stripped.prefix(3))
                    insideFence = true
                    currentLines.append(line)
                    continue
                }
            } else {
                // Inside a fence – look for the closing marker.
                currentLines.append(line)
                if stripped.hasPrefix(fenceMarker) && stripped.drop(while: { String($0) == String(fenceMarker.first!) }).trimmingCharacters(in: .whitespaces).isEmpty && currentLines.count > 1 {
                    insideFence = false
                    flushCurrent()
                }
                continue
            }

            // ── Normal (non-fence) lines ───────────────────────────
            if stripped.isEmpty {
                // Blank line → flush current block, then record blank line as separator
                flushCurrent()
                currentLines.append(line)
                flushCurrent()
            } else {
                currentLines.append(line)
            }
        }

        // Flush remaining (handles unclosed fences gracefully)
        if insideFence { insideFence = false }
        flushCurrent()

        return blocks
    }

    /// Re-join blocks into a single content string.  Each block's text is
    /// joined with a single newline.  Separator blocks contribute an empty line,
    /// which naturally produces the blank-line gap between content blocks.
    static func reconstruct(_ blocks: [MarkdownBlock]) -> String {
        blocks.map(\.text).joined(separator: "\n")
    }

    // MARK: - Internal helpers

    private static func detectType(_ text: String) -> MarkdownBlockType {
        let firstLine = text.prefix(while: { $0 != "\n" })
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)

        // Heading
        if trimmed.hasPrefix("#") {
            let afterHash = trimmed.drop(while: { $0 == "#" })
            if afterHash.isEmpty || afterHash.first == " " {
                return .heading
            }
        }

        // Fenced code block
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return .codeBlock
        }

        // Horizontal rule  (---, ***, ___ with optional spaces)
        if isHorizontalRule(trimmed) {
            return .horizontalRule
        }

        // Table (first line contains |)
        if trimmed.contains("|") && text.contains("\n") {
            let lines = text.components(separatedBy: "\n")
            if lines.count >= 2 {
                let secondLine = lines[1].trimmingCharacters(in: .whitespaces)
                if secondLine.contains("---") && secondLine.contains("|") {
                    return .table
                }
            }
        }

        // Blockquote
        if trimmed.hasPrefix(">") {
            return .blockquote
        }

        // List (unordered)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .list
        }

        // List (ordered)  e.g. "1. ", "2. "
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[trimmed.startIndex..<dotIndex]
            if !prefix.isEmpty && prefix.allSatisfy(\.isNumber) {
                let afterDot = trimmed.index(after: dotIndex)
                if afterDot < trimmed.endIndex && trimmed[afterDot] == " " {
                    return .list
                }
            }
        }

        return .paragraph
    }

    private static func isHorizontalRule(_ line: some StringProtocol) -> Bool {
        let cleaned = line.filter { $0 != " " }
        guard cleaned.count >= 3 else { return false }
        let first = cleaned.first!
        guard first == "-" || first == "*" || first == "_" else { return false }
        return cleaned.allSatisfy { $0 == first }
    }
}
