import Foundation

enum MarkdownHTMLRenderer {
    static func render(markdown: String, baseURL: URL?) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var index = 0
        var blocks: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Pass through raw HTML blocks (e.g. <table>, <div>, etc.)
            if let htmlTag = parseHTMLBlockOpen(trimmed) {
                var htmlLines: [String] = [line]
                let closingTag = "</\(htmlTag)>"
                if !trimmed.contains(closingTag) {
                    index += 1
                    while index < lines.count {
                        htmlLines.append(lines[index])
                        if lines[index].contains(closingTag) {
                            index += 1
                            break
                        }
                        index += 1
                    }
                } else {
                    index += 1
                }
                blocks.append(replaceOCRAnnotationMarkersInRawHTML(htmlLines.joined(separator: "\n")))
                continue
            }

            if let fence = parseFence(trimmed) {
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if isClosingFence(candidate, matching: fence) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }

                let escapedCode = escapeHTML(codeLines.joined(separator: "\n"))
                let languageClass = fence.language.isEmpty
                    ? ""
                    : #" class="language-\#(escapeHTMLAttribute(fence.language))""#
                blocks.append("<pre><code\(languageClass)>\(escapedCode)</code></pre>")
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append("<hr>")
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                let content = renderInline(heading.text, baseURL: baseURL)
                blocks.append("<h\(heading.level)>\(content)</h\(heading.level)>")
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard candidate.isEmpty || candidate.hasPrefix(">") else { break }
                    if candidate.hasPrefix(">") {
                        let withoutMarker = String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(withoutMarker)
                    } else {
                        quoteLines.append("")
                    }
                    index += 1
                }
                let rendered = render(markdown: quoteLines.joined(separator: "\n"), baseURL: baseURL)
                blocks.append("<blockquote>\(rendered)</blockquote>")
                continue
            }

            // Display math block: $$...$$
            if trimmed.hasPrefix("$$") {
                if trimmed.hasSuffix("$$") && trimmed.count > 4 {
                    // Single-line display math: $$ ... $$
                    let inner = String(trimmed.dropFirst(2).dropLast(2))
                    blocks.append(#"<div class="math-display">$$\#(inner)$$</div>"#)
                    index += 1
                    continue
                }
                // Multi-line display math
                index += 1
                var mathLines: [String] = [trimmed]
                while index < lines.count {
                    let ml = lines[index]
                    mathLines.append(ml)
                    index += 1
                    if ml.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("$$") { break }
                }
                blocks.append(#"<div class="math-display">\#(mathLines.joined(separator: "\n"))</div>"#)
                continue
            }

            if isTableRow(trimmed) {
                blocks.append(renderTable(lines: lines, startIndex: &index, baseURL: baseURL))
                continue
            }

            if let listKind = parseListKind(line) {
                blocks.append(renderList(lines: lines, startIndex: &index, kind: listKind, baseURL: baseURL))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let candidateLine = lines[index]
                let candidate = candidateLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty || startsSpecialBlock(candidateLine) {
                    break
                }
                paragraphLines.append(candidateLine)
                index += 1
            }

            let paragraphHTML = renderParagraph(paragraphLines, baseURL: baseURL)
            if !paragraphHTML.isEmpty {
                blocks.append(paragraphHTML)
            }
        }

        return blocks.joined(separator: "\n")
    }

    private struct Fence {
        let marker: Character
        let count: Int
        let language: String
    }

    private struct Heading {
        let level: Int
        let text: String
    }

    private enum ListKind {
        case unordered
        case ordered
    }

    private struct ListItemMarker {
        let kind: ListKind
        let content: String
    }

    private static let htmlBlockTags: Set<String> = [
        "table", "div", "p", "pre", "blockquote", "ul", "ol", "dl",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "section",
        "article", "aside", "details", "figcaption", "figure",
        "header", "footer", "main", "nav", "summary",
    ]

    private static func parseHTMLBlockOpen(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("<") else { return nil }
        let scanner = Scanner(string: trimmed)
        scanner.currentIndex = trimmed.index(after: trimmed.startIndex)
        guard let tag = scanner.scanCharacters(from: .letters) else { return nil }
        let lower = tag.lowercased()
        return htmlBlockTags.contains(lower) ? lower : nil
    }

    private static func startsSpecialBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseFence(trimmed) != nil ||
            isThematicBreak(trimmed) ||
            parseHeading(trimmed) != nil ||
            trimmed.hasPrefix(">") ||
            parseListKind(line) != nil ||
            isTableRow(trimmed) ||
            trimmed.hasPrefix("$$") ||
            parseHTMLBlockOpen(trimmed) != nil
    }

    private static func isTableRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1
    }

    private static func isTableSeparator(_ trimmed: String) -> Bool {
        guard isTableRow(trimmed) else { return false }
        let inner = trimmed.dropFirst().dropLast()
        let cells = inner.split(separator: "|", omittingEmptySubsequences: false)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func parseTableCells(_ trimmed: String) -> [String] {
        var row = trimmed
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTableAlignment(_ trimmed: String) -> [String] {
        parseTableCells(trimmed).map { cell in
            let startsColon = cell.hasPrefix(":")
            let endsColon = cell.hasSuffix(":")
            if startsColon && endsColon { return "center" }
            if endsColon { return "right" }
            return "left"
        }
    }

    private static func renderTable(lines: [String], startIndex: inout Int, baseURL: URL?) -> String {
        let headerTrimmed = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        startIndex += 1

        // Check for separator line
        var alignments: [String]?
        if startIndex < lines.count {
            let sepTrimmed = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if isTableSeparator(sepTrimmed) {
                alignments = parseTableAlignment(sepTrimmed)
                startIndex += 1
            }
        }

        let headerCells = parseTableCells(headerTrimmed)
        let aligns = alignments ?? Array(repeating: "left", count: headerCells.count)

        var html = "<table><thead><tr>"
        for (i, cell) in headerCells.enumerated() {
            let align = i < aligns.count ? aligns[i] : "left"
            html += #"<th style="text-align:\#(align)">\#(renderInline(cell, baseURL: baseURL))</th>"#
        }
        html += "</tr></thead><tbody>"

        while startIndex < lines.count {
            let rowTrimmed = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isTableRow(rowTrimmed) && !isTableSeparator(rowTrimmed) else { break }
            let cells = parseTableCells(rowTrimmed)
            html += "<tr>"
            for (i, cell) in cells.enumerated() {
                let align = i < aligns.count ? aligns[i] : "left"
                html += #"<td style="text-align:\#(align)">\#(renderInline(cell, baseURL: baseURL))</td>"#
            }
            html += "</tr>"
            startIndex += 1
        }

        html += "</tbody></table>"
        return html
    }

    private static func parseFence(_ trimmed: String) -> Fence? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else {
            return nil
        }

        let prefixCount = trimmed.prefix { $0 == marker }.count
        guard prefixCount >= 3 else { return nil }

        let language = trimmed.dropFirst(prefixCount).trimmingCharacters(in: .whitespaces)
        return Fence(marker: marker, count: prefixCount, language: language)
    }

    private static func isClosingFence(_ trimmed: String, matching fence: Fence) -> Bool {
        guard let first = trimmed.first, first == fence.marker else { return false }
        let prefixCount = trimmed.prefix { $0 == fence.marker }.count
        return prefixCount >= fence.count
    }

    private static func parseHeading(_ trimmed: String) -> Heading? {
        let prefix = trimmed.prefix { $0 == "#" }
        let level = prefix.count
        guard (1...6).contains(level) else { return nil }

        let remainder = trimmed.dropFirst(level)
        guard remainder.first?.isWhitespace == true else { return nil }
        return Heading(level: level, text: remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseListKind(_ line: String) -> ListKind? {
        parseListItemMarker(line)?.kind
    }

    private static func parseListItemMarker(_ line: String) -> ListItemMarker? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let first = trimmed.first, "-+*".contains(first) {
            let remainder = trimmed.dropFirst()
            guard remainder.first?.isWhitespace == true else { return nil }
            return ListItemMarker(
                kind: .unordered,
                content: remainder.trimmingCharacters(in: .whitespaces)
            )
        }

        var digits = ""
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
            digits.append(trimmed[cursor])
            cursor = trimmed.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < trimmed.endIndex, trimmed[cursor] == "." else {
            return nil
        }

        cursor = trimmed.index(after: cursor)
        guard cursor < trimmed.endIndex, trimmed[cursor].isWhitespace else { return nil }
        let content = trimmed[cursor...].trimmingCharacters(in: .whitespaces)
        return ListItemMarker(kind: .ordered, content: content)
    }

    private static func renderList(
        lines: [String],
        startIndex: inout Int,
        kind: ListKind,
        baseURL: URL?
    ) -> String {
        var items: [String] = []

        while startIndex < lines.count {
            guard let marker = parseListItemMarker(lines[startIndex]), marker.kind == kind else { break }

            var itemLines = [marker.content]
            startIndex += 1

            while startIndex < lines.count {
                let nextLine = lines[startIndex]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)

                if nextTrimmed.isEmpty || startsSpecialBlock(nextLine) {
                    break
                }

                if nextLine.hasPrefix("  ") || nextLine.hasPrefix("\t") {
                    itemLines.append(nextTrimmed)
                    startIndex += 1
                } else {
                    break
                }
            }

            let body = itemLines
                .map { renderInline($0, baseURL: baseURL) }
                .joined(separator: "<br>")
            items.append("<li>\(body)</li>")

            while startIndex < lines.count,
                  lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                startIndex += 1
                break
            }
        }

        let tag = kind == .ordered ? "ol" : "ul"
        return "<\(tag)>\(items.joined())</\(tag)>"
    }

    private static func renderParagraph(_ lines: [String], baseURL: URL?) -> String {
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !trimmedLines.isEmpty else { return "" }

        if trimmedLines.allSatisfy(isStandaloneImageLine) {
            let images = trimmedLines
                .map { renderInline($0, baseURL: baseURL) }
                .joined(separator: "\n")
            return #"<div class="swiftlib-md-media-block">\#(images)</div>"#
        }

        let content = trimmedLines
            .map { renderInline($0, baseURL: baseURL) }
            .joined(separator: "<br>")
        return "<p>\(content)</p>"
    }

    private static func isStandaloneImageLine(_ line: String) -> Bool {
        matchWhole(pattern: #"!\[[^\]]*\]\([^\n]+?\)"#, in: line)
    }

    private static func renderInline(_ text: String, baseURL: URL?) -> String {
        var placeholders: [String: String] = [:]
        var placeholderIndex = 0

        func storePlaceholder(_ html: String) -> String {
            let token = "\u{E000}\(placeholderIndex)\u{E001}"
            placeholderIndex += 1
            placeholders[token] = html
            return token
        }

        var output = text

        output = replaceMatches(
            pattern: #"`([^`]+)`"#,
            in: output
        ) { match, source in
            let inner = capture(match, in: source, at: 1) ?? ""
            return storePlaceholder("<code>\(escapeHTML(inner))</code>")
        }

        output = replaceOCRAnnotationMarkers(in: output) { content, kind in
            storePlaceholder("<\(kind.htmlTag)>\(escapeHTML(content))</\(kind.htmlTag)>")
        }

        // Protect inline math $...$ (but not $$) before other processing
        output = replaceMatches(
            pattern: #"(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)"#,
            in: output
        ) { match, source in
            let full = capture(match, in: source, at: 0) ?? ""
            return storePlaceholder(full)
        }

        output = replaceMatches(
            pattern: #"!\[([^\]]*)\]\((.+?)\)"#,
            in: output
        ) { match, source in
            let alt = capture(match, in: source, at: 1) ?? ""
            let rawDestination = capture(match, in: source, at: 2) ?? ""
            let destination = resolveURL(rawDestination, baseURL: baseURL)
            guard !destination.isEmpty else { return capture(match, in: source, at: 0) ?? "" }
            return storePlaceholder(
                #"<img class="swiftlib-md-image" src="\#(escapeHTMLAttribute(destination))" alt="\#(escapeHTMLAttribute(alt))" loading="lazy">"#
            )
        }

        output = replaceMatches(
            pattern: #"(?<!!)\[([^\]]+)\]\((.+?)\)"#,
            in: output
        ) { match, source in
            let label = capture(match, in: source, at: 1) ?? ""
            let rawDestination = capture(match, in: source, at: 2) ?? ""
            let destination = resolveURL(rawDestination, baseURL: baseURL)
            guard !destination.isEmpty else { return capture(match, in: source, at: 0) ?? "" }
            let labelHTML = renderInline(label, baseURL: baseURL)
            return storePlaceholder(
                #"<a href="\#(escapeHTMLAttribute(destination))">\#(labelHTML)</a>"#
            )
        }

        output = escapeHTML(output)
        output = replaceSimpleTag(pattern: #"~~(.+?)~~"#, tag: "del", in: output)
        output = replaceSimpleTag(pattern: #"\*\*(.+?)\*\*"#, tag: "strong", in: output)
        output = replaceSimpleTag(pattern: #"__(.+?)__"#, tag: "strong", in: output)
        output = replaceSimpleTag(pattern: #"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*"#, tag: "em", in: output)
        output = replaceSimpleTag(pattern: #"(?<!_)_(?!\s)(.+?)(?<!\s)_"#, tag: "em", in: output)

        for token in placeholders.keys.sorted(by: { $0.count > $1.count }) {
            if let html = placeholders[token] {
                output = output.replacingOccurrences(of: token, with: html)
            }
        }

        return output
    }

    private static func replaceSimpleTag(pattern: String, tag: String, in text: String) -> String {
        replaceMatches(pattern: pattern, in: text) { match, source in
            let inner = capture(match, in: source, at: 1) ?? ""
            return "<\(tag)>\(inner)</\(tag)>"
        }
    }

    private static func replaceMatches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        replaceMatches(pattern: pattern, in: text, options: options) { match, source in
            capture(match, in: source, at: 0) ?? ""
        }
    }

    private static func replaceMatches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        replacement: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement(match, result))
        }
        return result
    }

    private static func capture(_ match: NSTextCheckingResult, in text: String, at index: Int) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func matchWhole(pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^\(pattern)$", options: []) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private enum OCRAnnotationKind {
        case superscript
        case subscriptText

        var htmlTag: String {
            switch self {
            case .superscript: return "sup"
            case .subscriptText: return "sub"
            }
        }
    }

    private static func replaceOCRAnnotationMarkersInRawHTML(_ text: String) -> String {
        replaceOCRAnnotationMarkers(in: text) { content, kind in
            "<\(kind.htmlTag)>\(escapeHTML(content))</\(kind.htmlTag)>"
        }
    }

    private static func replaceOCRAnnotationMarkers(
        in text: String,
        replacement: (String, OCRAnnotationKind) -> String
    ) -> String {
        var result = text
        let patterns: [(String, OCRAnnotationKind)] = [
            (#"\${1,2}\s*\^\{([^{}$<>\n]+)\}\s*\${1,2}"#, .superscript),
            (#"\${1,2}\s*_\{([^{}$<>\n]+)\}\s*\${1,2}"#, .subscriptText),
        ]

        for (pattern, kind) in patterns {
            result = replaceMatches(pattern: pattern, in: result) { match, source in
                guard let rawContent = capture(match, in: source, at: 1) else {
                    return capture(match, in: source, at: 0) ?? ""
                }

                let normalizedContent = normalizedOCRAnnotationContent(rawContent)
                guard isLikelyOCRAnnotationContent(normalizedContent) else {
                    return capture(match, in: source, at: 0) ?? ""
                }

                return replacement(normalizedContent, kind)
            }
        }

        return result
    }

    private static func normalizedOCRAnnotationContent(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s*,\s*"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyOCRAnnotationContent(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 32 else { return false }
        return text.range(of: #"^[A-Za-z0-9*,.†‡\- ]+$"#, options: .regularExpression) != nil
    }

    private static func resolveURL(_ rawValue: String, baseURL: URL?) -> String {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

        guard !trimmed.isEmpty else { return "" }
        if let baseURL,
           let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL.absoluteString {
            return resolved
        }
        return trimmed
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTML(text)
    }
}
