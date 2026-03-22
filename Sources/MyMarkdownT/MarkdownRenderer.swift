import Foundation
import MarkdownUI

struct MarkdownHeadingAnchor: Equatable {
    let text: String
    let anchor: String
}

struct MarkdownRenderResult: Equatable {
    let markdown: String
    let headingAnchors: [MarkdownHeadingAnchor]
}

enum MarkdownRenderer {
    static func prepare(markdown: String, baseURL: URL?) -> MarkdownRenderResult {
        let noFrontMatter = stripFrontMatter(markdown)
        let autoTitled = resolveAutoTitleLinks(in: noFrontMatter, baseURL: baseURL)
        let transformed = transformYFMSyntax(autoTitled)

        var anchors = headingAnchors(in: transformed.markdown)
        for (index, customAnchor) in transformed.customAnchorsByIndex where index < anchors.count {
            anchors[index] = MarkdownHeadingAnchor(text: anchors[index].text, anchor: customAnchor)
        }

        return MarkdownRenderResult(markdown: transformed.markdown, headingAnchors: anchors)
    }

        static func renderHTMLDocument(markdown: String, baseURL: URL?) -> String {
                let prepared = prepare(markdown: markdown, baseURL: baseURL)
                let body = MarkdownContent(prepared.markdown).renderHTML()

                return """
                <!DOCTYPE html>
                <html lang="zh-CN">
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <title>Markdown Export</title>
                    <style>
                        :root { color-scheme: light dark; }
                        body {
                            margin: 0;
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                            line-height: 1.65;
                            padding: 40px;
                            max-width: 980px;
                        }
                        pre {
                            padding: 12px;
                            border-radius: 8px;
                            overflow-x: auto;
                            background: rgba(127, 127, 127, 0.12);
                        }
                        code {
                            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                        }
                        blockquote {
                            margin: 0;
                            padding-left: 12px;
                            border-left: 4px solid rgba(127, 127, 127, 0.45);
                        }
                        table {
                            border-collapse: collapse;
                            width: 100%;
                        }
                        th, td {
                            border: 1px solid rgba(127, 127, 127, 0.35);
                            padding: 8px;
                            vertical-align: top;
                        }
                        img { max-width: 100%; height: auto; }
                        @page { size: A4; margin: 20mm; }
                        @media print {
                            body { max-width: none; padding: 0; }
                            pre { white-space: pre-wrap; }
                            h1,h2,h3,h4,h5,h6 { page-break-after: avoid; }
                            pre, blockquote, img, table { page-break-inside: avoid; }
                        }
                    </style>
                </head>
                <body>
                \(body)
                </body>
                </html>
                """
        }

    static func stripFrontMatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n") else {
            return markdown
        }

        let lines = markdown.components(separatedBy: "\n")
        guard lines.count > 2 else {
            return markdown
        }

        var closingIndex: Int?
        for index in 1..<lines.count {
            if lines[index] == "---" {
                closingIndex = index
                break
            }
        }

        guard let end = closingIndex, end + 1 < lines.count else {
            return markdown
        }

        return lines[(end + 1)...].joined(separator: "\n")
    }

    static func slug(from heading: String) -> String {
        let normalized = heading
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let allowed = normalized.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }

            if scalar.properties.generalCategory == .dashPunctuation {
                return "-"
            }

            return " "
        }

        let collapsed = String(allowed)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return collapsed.isEmpty ? "section" : collapsed
    }

    static func headingAnchors(in markdown: String) -> [MarkdownHeadingAnchor] {
        let lines = markdown.components(separatedBy: "\n")
        var anchors: [MarkdownHeadingAnchor] = []
        var slugCounts: [String: Int] = [:]
        var index = 0
        var fencedCodeDelimiter: String?

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let delimiter = fencedCodeDelimiter {
                if trimmed.hasPrefix(delimiter) {
                    fencedCodeDelimiter = nil
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                fencedCodeDelimiter = "```"
                index += 1
                continue
            }

            if trimmed.hasPrefix("~~~") {
                fencedCodeDelimiter = "~~~"
                index += 1
                continue
            }

            if let atxHeading = parseATXHeading(line) {
                anchors.append(uniqueHeadingAnchor(for: atxHeading, slugCounts: &slugCounts))
                index += 1
                continue
            }

            if index + 1 < lines.count, let setextHeading = parseSetextHeading(textLine: line, underlineLine: lines[index + 1]) {
                anchors.append(uniqueHeadingAnchor(for: setextHeading, slugCounts: &slugCounts))
                index += 2
                continue
            }

            index += 1
        }

        return anchors
    }

    private static func uniqueHeadingAnchor(for headingText: String, slugCounts: inout [String: Int]) -> MarkdownHeadingAnchor {
        let baseSlug = slug(from: headingText)
        let currentCount = slugCounts[baseSlug, default: 0]
        slugCounts[baseSlug] = currentCount + 1

        let uniqueSlug = currentCount == 0 ? baseSlug : "\(baseSlug)-\(currentCount)"
        return MarkdownHeadingAnchor(text: headingText, anchor: uniqueSlug)
    }

    private static func parseATXHeading(_ line: String) -> String? {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLeading.hasPrefix("#") else {
            return nil
        }

        let hashes = trimmedLeading.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else {
            return nil
        }

        let contentStart = trimmedLeading.index(trimmedLeading.startIndex, offsetBy: hashes.count)
        let remainder = trimmedLeading[contentStart...]
        guard remainder.first?.isWhitespace == true else {
            return nil
        }

        var content = remainder.trimmingCharacters(in: .whitespaces)
        while content.last == "#" {
            content.removeLast()
        }

        let normalized = content.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            return nil
        }

        return MarkdownContent("# \(normalized)").renderPlainText()
    }

    private static func parseSetextHeading(textLine: String, underlineLine: String) -> String? {
        let normalizedText = textLine.trimmingCharacters(in: .whitespaces)
        guard !normalizedText.isEmpty else {
            return nil
        }

        let underline = underlineLine.trimmingCharacters(in: .whitespaces)
        guard !underline.isEmpty else {
            return nil
        }

        let isLevel1 = underline.allSatisfy { $0 == "=" }
        let isLevel2 = underline.allSatisfy { $0 == "-" }
        guard isLevel1 || isLevel2 else {
            return nil
        }

        return MarkdownContent("\(normalizedText)\n\(underline)").renderPlainText()
    }

    private static func resolveAutoTitleLinks(in markdown: String, baseURL: URL?) -> String {
        let pattern = #"\[\{#T\}\]\(([^)\s]+)\)"#
        return replacingMatches(in: markdown, pattern: pattern) { match, source in
            guard let range = Range(match.range(at: 1), in: source) else {
                return nil
            }

            let rawTarget = String(source[range])
            let title = titleForMarkdownLink(target: rawTarget, baseURL: baseURL)
            return "[\(title)](\(rawTarget))"
        }
    }

    private static func titleForMarkdownLink(target: String, baseURL: URL?) -> String {
        let pathPart = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(pathPart.first ?? "")

        guard !rawPath.isEmpty else {
            return "当前章节"
        }

        let resolvedURL: URL
        if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://") {
            return rawPath
        }

        if let absolute = URL(string: rawPath), absolute.isFileURL {
            resolvedURL = absolute
        } else if let baseURL {
            resolvedURL = URL(fileURLWithPath: rawPath, relativeTo: baseURL).standardizedFileURL
        } else {
            return rawPath
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path),
              let fileContent = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            return resolvedURL.deletingPathExtension().lastPathComponent
        }

        let withoutFrontMatter = stripFrontMatter(fileContent)
        let lines = withoutFrontMatter.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }
            if let heading = parseATXHeading(trimmed) {
                return heading
            }
            break
        }

        return resolvedURL.deletingPathExtension().lastPathComponent
    }

    private struct YFMTransformResult {
        var markdown: String
        var customAnchorsByIndex: [Int: String]
    }

    private static func transformYFMSyntax(_ markdown: String) -> YFMTransformResult {
        var lines = markdown.components(separatedBy: "\n")
        lines = removeMetaComments(from: lines)

        let terms = collectTermDefinitions(from: &lines)
        var output: [String] = []
        var customAnchorsByIndex: [Int: String] = [:]
        var headingIndex = 0
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let note = parseNoteStart(trimmed) {
                let endIndex = findDirectiveEnd(from: index + 1, in: lines, endTag: "{% endnote %}")
                output.append("> [!\(note.type)] \(note.title)")
                for contentLine in lines[(index + 1)..<endIndex] {
                    output.append(contentLine.isEmpty ? ">" : "> \(contentLine)")
                }
                output.append("")
                index = min(endIndex + 1, lines.count)
                continue
            }

            if let cutTitle = parseCutStart(trimmed) {
                let endIndex = findDirectiveEnd(from: index + 1, in: lines, endTag: "{% endcut %}")
                output.append("> **折叠：\(cutTitle)**")
                for contentLine in lines[(index + 1)..<endIndex] {
                    output.append(contentLine.isEmpty ? ">" : "> \(contentLine)")
                }
                output.append("")
                index = min(endIndex + 1, lines.count)
                continue
            }

            if trimmed == "{% list tabs %}" {
                let endIndex = findDirectiveEnd(from: index + 1, in: lines, endTag: "{% endlist %}")
                output.append(contentsOf: transformTabsBlock(lines: Array(lines[(index + 1)..<endIndex])))
                output.append("")
                index = min(endIndex + 1, lines.count)
                continue
            }

            if trimmed == "#|" {
                let endIndex = findDirectiveEnd(from: index + 1, in: lines, endTag: "|#")
                output.append(contentsOf: transformMultilineTableBlock(lines: Array(lines[(index + 1)..<endIndex])))
                output.append("")
                index = min(endIndex + 1, lines.count)
                continue
            }

            if let fileDirective = parseFileDirective(trimmed) {
                output.append("[下载 \(fileDirective.name)](\(fileDirective.src))")
                index += 1
                continue
            }

            var transformedLine = line
            transformedLine = normalizeImageSizeSyntax(transformedLine)
            transformedLine = normalizeSuperscript(transformedLine)
            transformedLine = normalizeMonospace(transformedLine)
            transformedLine = normalizeVideoSyntax(transformedLine)
            transformedLine = replaceTermUsages(in: transformedLine, terms: terms)

            if let heading = parseHeadingWithCustomAnchor(transformedLine) {
                transformedLine = heading.markdownLine
                customAnchorsByIndex[headingIndex] = heading.customAnchor
            }

            if parseATXHeading(transformedLine) != nil {
                headingIndex += 1
            } else if index + 1 < lines.count,
                      parseSetextHeading(textLine: transformedLine, underlineLine: lines[index + 1]) != nil {
                headingIndex += 1
            }

            output.append(transformedLine)
            index += 1
        }

        let markdownOut = output.joined(separator: "\n")
        return YFMTransformResult(markdown: markdownOut, customAnchorsByIndex: customAnchorsByIndex)
    }

    private static func removeMetaComments(from lines: [String]) -> [String] {
        lines.filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("[//]: # (")
        }
    }

    private static func collectTermDefinitions(from lines: inout [String]) -> [String: String] {
        var terms: [String: String] = [:]
        var filtered: [String] = []

        for line in lines {
            if let match = line.range(of: #"^\[\*([^\]]+)\]:\s*(.+)$"#, options: .regularExpression) {
                let raw = String(line[match])
                let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else {
                    continue
                }
                let key = parts[0].replacingOccurrences(of: "[*", with: "").replacingOccurrences(of: "]", with: "")
                terms[key] = parts[1].trimmingCharacters(in: .whitespaces)
            } else {
                filtered.append(line)
            }
        }

        lines = filtered
        return terms
    }

    private static func replaceTermUsages(in line: String, terms: [String: String]) -> String {
        let pattern = #"\[([^\]]+)\]\(\*([^\)]+)\)"#
        return replacingMatches(in: line, pattern: pattern) { match, source in
            guard let textRange = Range(match.range(at: 1), in: source),
                  let keyRange = Range(match.range(at: 2), in: source) else {
                return nil
            }

            let text = String(source[textRange])
            let key = String(source[keyRange])
            let definition = terms[key]

            if let definition, !definition.isEmpty {
                return "\(text)（\(definition)）"
            }

            return text
        }
    }

    private static func normalizeImageSizeSyntax(_ line: String) -> String {
        line.replacingOccurrences(of: #"\s*=\d+x\d*"#, with: "", options: .regularExpression)
    }

    private static func normalizeSuperscript(_ line: String) -> String {
        replacingMatches(in: line, pattern: #"\^([^\^\n]+)\^"#) { match, source in
            guard let range = Range(match.range(at: 1), in: source) else {
                return nil
            }
            let content = String(source[range])
            return "^(\(content))"
        }
    }

    private static func normalizeMonospace(_ line: String) -> String {
        replacingMatches(in: line, pattern: #"(?<!#)##([^#\n]+)##"#) { match, source in
            guard let range = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return "`\(source[range])`"
        }
    }

    private static func normalizeVideoSyntax(_ line: String) -> String {
        replacingMatches(in: line, pattern: #"@\[([^\]]+)\]\(([^\)]+)\)"#) { match, source in
            guard let platformRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source) else {
                return nil
            }

            let platform = String(source[platformRange]).trimmingCharacters(in: .whitespaces)
            let value = String(source[valueRange]).trimmingCharacters(in: .whitespaces)
            return "[视频（\(platform)）](\(value))"
        }
    }

    private static func parseHeadingWithCustomAnchor(_ line: String) -> (markdownLine: String, customAnchor: String)? {
        let pattern = #"^(#{1,6}\s+.*)\s+\{#([^}]+)\}\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let contentRange = Range(match.range(at: 1), in: line),
              let anchorRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let anchor = String(line[anchorRange]).trimmingCharacters(in: .whitespaces)
        return (String(line[contentRange]), anchor)
    }

    private static func parseNoteStart(_ line: String) -> (type: String, title: String)? {
        let pattern = #"^\{%\s*note\s+(info|tip|warning|alert)(?:\s+"([^"]*)")?\s*%\}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let typeRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let type = String(line[typeRange]).uppercased()
        let title: String
        if match.range(at: 2).location != NSNotFound, let titleRange = Range(match.range(at: 2), in: line) {
            let raw = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
            title = raw.isEmpty ? defaultNoteTitle(type) : raw
        } else {
            title = defaultNoteTitle(type)
        }

        return (type, title)
    }

    private static func defaultNoteTitle(_ type: String) -> String {
        switch type {
        case "TIP": return "提示"
        case "WARNING": return "警告"
        case "ALERT": return "注意"
        default: return "说明"
        }
    }

    private static func parseCutStart(_ line: String) -> String? {
        let pattern = #"^\{%\s*cut\s+"([^"]+)"\s*%\}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let titleRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[titleRange])
    }

    private static func parseFileDirective(_ line: String) -> (src: String, name: String)? {
        let pattern = #"^\{%\s*file\s+src="([^"]+)"\s+name="([^"]+)"\s*%\}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let srcRange = Range(match.range(at: 1), in: line),
              let nameRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        return (String(line[srcRange]), String(line[nameRange]))
    }

    private static func findDirectiveEnd(from start: Int, in lines: [String], endTag: String) -> Int {
        var cursor = start
        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespaces) == endTag {
                return cursor
            }
            cursor += 1
        }
        return lines.count
    }

    private static func transformTabsBlock(lines: [String]) -> [String] {
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("- ") {
                let tabTitle = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                output.append("### \(tabTitle)")
                index += 1

                while index < lines.count {
                    let contentLine = lines[index]
                    let contentTrimmed = contentLine.trimmingCharacters(in: .whitespaces)
                    if contentTrimmed.hasPrefix("- ") && !contentLine.hasPrefix("  ") {
                        break
                    }
                    output.append(contentLine.hasPrefix("  ") ? String(contentLine.dropFirst(2)) : contentLine)
                    index += 1
                }

                output.append("")
                continue
            }

            index += 1
        }

        return output
    }

    private static func transformMultilineTableBlock(lines: [String]) -> [String] {
        var rows: [[String]] = []
        var isSimpleTable = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }

            guard trimmed.hasPrefix("||"), trimmed.hasSuffix("||") else {
                isSimpleTable = false
                break
            }

            let inner = String(trimmed.dropFirst(2).dropLast(2))
            let cells = inner
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }

            rows.append(cells)
        }

        guard isSimpleTable, let firstRow = rows.first else {
            var output = ["```text", "#|"]
            output.append(contentsOf: lines)
            output.append("|#")
            output.append("```")
            return output
        }

        let columnCount = firstRow.count
        let normalizedRows = rows.map { row in
            row.count < columnCount
                ? row + Array(repeating: "", count: columnCount - row.count)
                : Array(row.prefix(columnCount))
        }

        var output: [String] = []
        output.append("| " + normalizedRows[0].joined(separator: " | ") + " |")
        output.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        for row in normalizedRows.dropFirst() {
            output.append("| " + row.joined(separator: " | ") + " |")
        }
        return output
    }

    private static func replacingMatches(
        in source: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        replacer: (_ match: NSTextCheckingResult, _ source: String) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return source
        }

        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        if matches.isEmpty {
            return source
        }

        let mutable = NSMutableString(string: source)
        for match in matches.reversed() {
            guard let replacement = replacer(match, source) else {
                continue
            }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }

        return mutable as String
    }
}
