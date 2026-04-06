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

    private static func startsSpecialBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseFence(trimmed) != nil ||
            isThematicBreak(trimmed) ||
            parseHeading(trimmed) != nil ||
            trimmed.hasPrefix(">") ||
            parseListKind(line) != nil
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
