import Cocoa
import Quartz
import WebKit

@MainActor
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private let webView = WKWebView()

    override func loadView() {
        view = webView
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdx", "yfm"]

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let ext = url.pathExtension.lowercased()
        guard Self.markdownExtensions.contains(ext) else {
            handler(CocoaError(.fileReadUnsupportedScheme))
            return
        }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let html = Self.renderHTML(from: markdown, baseURL: url.deletingLastPathComponent())
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            handler(nil)
        } catch {
            handler(error)
        }
    }

    // MARK: - Markdown → HTML

    private static func renderHTML(from markdown: String, baseURL: URL) -> String {
        let body = markdownToHTML(markdown)
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            padding: 24px;
            max-width: 980px;
            margin: 0 auto;
            color: #1f2328;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #e6edf3; }
            a { color: #58a6ff; }
            code { background: rgba(110,118,129,0.3); }
            pre { background: rgba(110,118,129,0.2); }
            blockquote { border-left-color: #3b434b; color: #9198a1; }
            table th, table td { border-color: #3b434b; }
            hr { background: #3b434b; }
        }
        h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; }
        h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid rgba(127,127,127,0.25); }
        h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid rgba(127,127,127,0.25); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: #656d76; }
        code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 85%;
            padding: 0.2em 0.4em;
            background: rgba(175,184,193,0.2);
            border-radius: 6px;
        }
        pre {
            padding: 16px;
            overflow: auto;
            border-radius: 6px;
            background: rgba(175,184,193,0.12);
            line-height: 1.45;
        }
        pre code { padding: 0; background: transparent; font-size: 100%; }
        blockquote {
            margin: 0 0 16px 0;
            padding: 0 1em;
            border-left: 4px solid #d0d7de;
            color: #656d76;
        }
        table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
        th, td { border: 1px solid #d0d7de; padding: 8px 13px; }
        th { font-weight: 600; }
        img { max-width: 100%; height: auto; }
        hr { height: 4px; padding: 0; margin: 24px 0; background: #d0d7de; border: 0; border-radius: 2px; }
        a { color: #0969da; text-decoration: none; }
        a:hover { text-decoration: underline; }
        ul, ol { padding-left: 2em; }
        li + li { margin-top: 0.25em; }
        .task-list-item { list-style: none; margin-left: -1.5em; }
        .task-list-item input { margin-right: 0.5em; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func markdownToHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        var inCodeBlock = false
        var codeFence = ""

        // Strip YAML front matter
        let startIndex: Int
        if lines.first == "---" {
            var endFM = 1
            while endFM < lines.count {
                if lines[endFM] == "---" { endFM += 1; break }
                endFM += 1
            }
            startIndex = endFM
        } else {
            startIndex = 0
        }

        i = startIndex

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code blocks
            if !inCodeBlock, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                codeFence = String(trimmed.prefix(3))
                result.append("<pre><code>")
                inCodeBlock = true
                i += 1
                continue
            }
            if inCodeBlock {
                if trimmed.hasPrefix(codeFence) {
                    result.append("</code></pre>")
                    inCodeBlock = false
                } else {
                    result.append(escapeHTML(line))
                }
                i += 1
                continue
            }

            // Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                result.append("<hr>")
                i += 1
                continue
            }

            // ATX headings
            if trimmed.hasPrefix("#") {
                if let (level, text) = parseATXHeading(trimmed) {
                    result.append("<h\(level)>\(inlineMarkdown(text))</h\(level)>")
                    i += 1
                    continue
                }
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix(">") {
                        let content = String(ql.dropFirst(ql.hasPrefix("> ") ? 2 : 1))
                        quoteLines.append(content)
                    } else if ql.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                result.append("<blockquote>\(markdownToHTML(quoteLines.joined(separator: "\n")))</blockquote>")
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                var listItems: [String] = []
                while i < lines.count {
                    let ll = lines[i].trimmingCharacters(in: .whitespaces)
                    if isUnorderedListItem(ll) {
                        listItems.append(String(ll.dropFirst(2)))
                    } else if ll.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                let items = listItems.map { "<li>\(inlineMarkdown($0))</li>" }.joined(separator: "\n")
                result.append("<ul>\n\(items)\n</ul>")
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                var listItems: [String] = []
                while i < lines.count {
                    let ll = lines[i].trimmingCharacters(in: .whitespaces)
                    if isOrderedListItem(ll) {
                        if let dotIndex = ll.firstIndex(of: ".") {
                            let afterDot = ll[ll.index(after: dotIndex)...]
                            listItems.append(String(afterDot).trimmingCharacters(in: .whitespaces))
                        }
                    } else if ll.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                let items = listItems.map { "<li>\(inlineMarkdown($0))</li>" }.joined(separator: "\n")
                result.append("<ol>\n\(items)\n</ol>")
                continue
            }

            // Table
            if i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces).contains("---"),
               trimmed.contains("|") {
                var tableLines: [String] = []
                while i < lines.count {
                    let tl = lines[i].trimmingCharacters(in: .whitespaces)
                    guard tl.contains("|") else { break }
                    tableLines.append(tl)
                    i += 1
                }
                result.append(parseTable(tableLines))
                continue
            }

            // Paragraph
            var paraLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let pl = lines[i].trimmingCharacters(in: .whitespaces)
                if pl.isEmpty { break }
                if pl.hasPrefix("#") || pl.hasPrefix(">") || pl.hasPrefix("```") || pl.hasPrefix("~~~")
                    || isUnorderedListItem(pl) || isOrderedListItem(pl) || isHorizontalRule(pl) { break }
                paraLines.append(pl)
                i += 1
            }
            result.append("<p>\(inlineMarkdown(paraLines.joined(separator: "\n")))</p>")
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Inline markdown

    private static func inlineMarkdown(_ text: String) -> String {
        var s = escapeHTML(text)

        // Images: ![alt](url)
        s = s.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: #"<img src="$2" alt="$1">"#,
            options: .regularExpression
        )

        // Links: [text](url)
        s = s.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: #"<a href="$2">$1</a>"#,
            options: .regularExpression
        )

        // Bold + Italic: ***text*** or ___text___
        s = s.replacingOccurrences(
            of: #"\*\*\*(.+?)\*\*\*"#,
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )

        // Bold: **text**
        s = s.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic: *text*
        s = s.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Strikethrough: ~~text~~
        s = s.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "<del>$1</del>",
            options: .regularExpression
        )

        // Inline code: `code`
        s = s.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: #"<code>$1</code>"#,
            options: .regularExpression
        )

        // Line breaks
        s = s.replacingOccurrences(of: "  \n", with: "<br>\n")

        return s
    }

    // MARK: - Helpers

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func parseATXHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return (level, rest)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        if stripped.count >= 3 {
            if stripped.allSatisfy({ $0 == "-" }) { return true }
            if stripped.allSatisfy({ $0 == "*" }) { return true }
            if stripped.allSatisfy({ $0 == "_" }) { return true }
        }
        return false
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        return prefix.allSatisfy(\.isNumber) && !prefix.isEmpty
            && line.index(after: dotIndex) < line.endIndex
    }

    private static func parseTable(_ lines: [String]) -> String {
        func cells(from line: String) -> [String] {
            var raw = line.trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("|") { raw = String(raw.dropFirst()) }
            if raw.hasSuffix("|") { raw = String(raw.dropLast()) }
            return raw.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        guard lines.count >= 2 else { return "" }

        let headers = cells(from: lines[0])
        var html = "<table>\n<thead><tr>"
        for header in headers {
            html += "<th>\(inlineMarkdown(header))</th>"
        }
        html += "</tr></thead>\n<tbody>\n"

        for row in lines.dropFirst(2) {
            let cols = cells(from: row)
            html += "<tr>"
            for col in cols {
                html += "<td>\(inlineMarkdown(col))</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody></table>"
        return html
    }
}
