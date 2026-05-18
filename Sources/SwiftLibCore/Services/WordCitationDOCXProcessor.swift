import Foundation

public struct WordDOCXDuplicateCitation: Codable, Equatable, Sendable {
    public let paragraphIndex: Int
    public let referenceID: Int64
    public let count: Int
}

public struct WordDOCXAuditReport: Codable, Sendable {
    public let inputPath: String
    public let citationControlCount: Int
    public let bibliographyControlCount: Int
    public let docUniqueIDs: [Int64]
    public let docUniqueIDCount: Int
    public let libraryReferenceCount: Int
    public let citedReferenceCountInLibrary: Int
    public let missingInLibrary: [Int64]
    public let unusedInLibrary: [Int64]
    public let duplicateCitationsInParagraphs: [WordDOCXDuplicateCitation]
    public let bibliographyEntryCount: Int
    public let bibliographyMatchesBodyUniqueCount: Bool
    public let warnings: [String]
}

public struct WordDOCXRefreshReport: Codable, Sendable {
    public let inputPath: String
    public let outputPath: String
    public let citationControlCount: Int
    public let refreshedCitationCount: Int
    public let bibliographyControlCount: Int
    public let refreshedBibliographyCount: Int
    public let insertedBibliography: Bool
    public let audit: WordDOCXAuditReport
}

public enum WordCitationDOCXProcessorError: LocalizedError {
    case missingDocumentXML
    case noSwiftLibCitations
    case missingReferences([Int64])
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingDocumentXML:
            return "The .docx archive does not contain word/document.xml"
        case .noSwiftLibCitations:
            return "The document does not contain SwiftLib citation tags"
        case .missingReferences(let ids):
            return "The document references IDs missing from the library: \(ids.map(String.init).joined(separator: ", "))"
        case .processFailed(let message):
            return message
        }
    }
}

public enum WordCitationDOCXProcessor {
    public static func auditDOCX(
        at inputURL: URL,
        references: [Reference]
    ) throws -> WordDOCXAuditReport {
        let unpacked = try unpackDOCX(inputURL)
        defer { try? FileManager.default.removeItem(at: unpacked.tempRoot) }

        let documentURL = unpacked.unpackedURL.appendingPathComponent("word/document.xml")
        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            throw WordCitationDOCXProcessorError.missingDocumentXML
        }

        let xml = try String(contentsOf: documentURL, encoding: .utf8)
        return auditDocumentXML(xml, inputPath: inputURL.path, references: references)
    }

    public static func refreshDOCX(
        at inputURL: URL,
        outputURL: URL,
        references: [Reference],
        defaultStyle: String = "nature"
    ) throws -> WordDOCXRefreshReport {
        let unpacked = try unpackDOCX(inputURL)
        defer { try? FileManager.default.removeItem(at: unpacked.tempRoot) }

        let documentURL = unpacked.unpackedURL.appendingPathComponent("word/document.xml")
        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            throw WordCitationDOCXProcessorError.missingDocumentXML
        }

        let xml = try String(contentsOf: documentURL, encoding: .utf8)
        let audit = auditDocumentXML(xml, inputPath: inputURL.path, references: references)
        guard audit.citationControlCount > 0 else {
            throw WordCitationDOCXProcessorError.noSwiftLibCitations
        }
        guard audit.missingInLibrary.isEmpty else {
            throw WordCitationDOCXProcessorError.missingReferences(audit.missingInLibrary)
        }

        let referencesByID = Dictionary(uniqueKeysWithValues: references.compactMap { ref -> (Int64, Reference)? in
            guard let id = ref.id else { return nil }
            return (id, ref)
        })
        let citations = scanCitationControls(in: xml)
        let bibliographyControls = scanBibliographyControls(in: xml)
        let style = preferredStyle(citations: citations, bibliographyControls: bibliographyControls, defaultStyle: defaultStyle)
        let groups = citations.map {
            WordCitationGroup(
                citationID: $0.citationID,
                start: $0.range.location,
                end: $0.range.location + $0.range.length,
                referenceIDs: $0.referenceIDs,
                styleID: style
            )
        }
        let rendered = WordCitationRenderer.render(groups: groups, referencesByID: referencesByID, styleID: style)
        let refreshedXML = refreshDocumentXML(
            xml,
            citations: citations,
            bibliographyControls: bibliographyControls,
            rendered: rendered,
            style: style
        )

        try refreshedXML.xml.write(to: documentURL, atomically: true, encoding: .utf8)
        try zipDOCX(from: unpacked.unpackedURL, to: outputURL, tempRoot: unpacked.tempRoot)

        return WordDOCXRefreshReport(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            citationControlCount: citations.count,
            refreshedCitationCount: refreshedXML.refreshedCitationCount,
            bibliographyControlCount: bibliographyControls.count,
            refreshedBibliographyCount: refreshedXML.refreshedBibliographyCount,
            insertedBibliography: refreshedXML.insertedBibliography,
            audit: audit
        )
    }

    public static func auditDocumentXML(
        _ xml: String,
        inputPath: String = "",
        references: [Reference]
    ) -> WordDOCXAuditReport {
        let citations = scanCitationControls(in: xml)
        let bibliographyControls = scanBibliographyControls(in: xml)
        let referenceIDs = Set(references.compactMap(\.id))
        let docUniqueIDs = orderedUnique(citations.flatMap(\.referenceIDs))
        let docUniqueIDSet = Set(docUniqueIDs)
        let missingInLibrary = docUniqueIDs.filter { !referenceIDs.contains($0) }
        let unusedInLibrary = references.compactMap(\.id).filter { !docUniqueIDSet.contains($0) }.sorted()
        let bibliographyEntryCount = countBibliographyEntries(in: xml, bibliographyControls: bibliographyControls)
        var warnings: [String] = []
        if bibliographyControls.isEmpty {
            warnings.append("document has SwiftLib citations but no SwiftLib bibliography control")
        }
        if bibliographyEntryCount > 0, bibliographyEntryCount != docUniqueIDs.count {
            warnings.append("bibliography entry count does not match unique body citation count")
        }

        return WordDOCXAuditReport(
            inputPath: inputPath,
            citationControlCount: citations.count,
            bibliographyControlCount: bibliographyControls.count,
            docUniqueIDs: docUniqueIDs,
            docUniqueIDCount: docUniqueIDs.count,
            libraryReferenceCount: references.count,
            citedReferenceCountInLibrary: docUniqueIDs.filter { referenceIDs.contains($0) }.count,
            missingInLibrary: missingInLibrary,
            unusedInLibrary: unusedInLibrary,
            duplicateCitationsInParagraphs: duplicateCitationsByParagraph(in: xml),
            bibliographyEntryCount: bibliographyEntryCount,
            bibliographyMatchesBodyUniqueCount: bibliographyEntryCount == docUniqueIDs.count,
            warnings: warnings
        )
    }

    private static func refreshDocumentXML(
        _ xml: String,
        citations: [CitationControl],
        bibliographyControls: [BibliographyControl],
        rendered: WordRenderedDocument,
        style: String
    ) -> (xml: String, refreshedCitationCount: Int, refreshedBibliographyCount: Int, insertedBibliography: Bool) {
        let mutable = NSMutableString(string: xml)
        var refreshedCitationCount = 0
        var refreshedBibliographyCount = 0
        var replacements: [(range: NSRange, replacement: String, kind: String)] = []

        for citation in citations {
            guard let text = rendered.citationTexts[citation.citationID],
                  let contentRange = contentRange(in: citation.xml) else { continue }
            let contentNSRange = NSRange(
                location: citation.range.location + contentRange.location,
                length: contentRange.length
            )
            let superscript = rendered.superscriptCitationBookmarkNames.contains(citation.citationID)
            replacements.append((contentNSRange, citationContentXML(text: text, superscript: superscript), "citation"))
        }

        let bibliographyXML = bibliographyContentXML(
            entries: rendered.bibliographyText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            templatePPr: bibliographyControls.first.flatMap { firstParagraphProperties(in: $0.xml) }
        )

        for bibliography in bibliographyControls {
            guard let contentRange = contentRange(in: bibliography.xml) else { continue }
            let contentNSRange = NSRange(
                location: bibliography.range.location + contentRange.location,
                length: contentRange.length
            )
            replacements.append((contentNSRange, bibliographyXML, "bibliography"))
        }

        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: replacement.range, with: replacement.replacement)
            if replacement.kind == "citation" {
                refreshedCitationCount += 1
            } else {
                refreshedBibliographyCount += 1
            }
        }

        var output = mutable as String
        var insertedBibliography = false
        if bibliographyControls.isEmpty, !rendered.bibliographyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let control = newBibliographyControlXML(style: style, contentXML: bibliographyXML)
            output = insertBibliographyControl(control, into: output)
            insertedBibliography = true
            refreshedBibliographyCount = 1
        }

        return (output, refreshedCitationCount, refreshedBibliographyCount, insertedBibliography)
    }

    private static func preferredStyle(
        citations: [CitationControl],
        bibliographyControls: [BibliographyControl],
        defaultStyle: String
    ) -> String {
        citations.first(where: { !$0.style.isEmpty })?.style
            ?? bibliographyControls.first(where: { !$0.style.isEmpty })?.style
            ?? defaultStyle
    }

    private static func scanCitationControls(in xml: String) -> [CitationControl] {
        sdtRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let range = Range(match.range, in: xml) else { return nil }
            let sdtXML = String(xml[range])
            guard let rawTag = tagValue(in: sdtXML),
                  let parsed = parseCitationTag(rawTag, controlXML: sdtXML) else { return nil }
            return CitationControl(
                range: match.range,
                xml: sdtXML,
                citationID: parsed.citationID,
                style: parsed.style,
                referenceIDs: parsed.referenceIDs,
                isShortTag: parsed.isShortTag
            )
        }
    }

    private static func scanBibliographyControls(in xml: String) -> [BibliographyControl] {
        sdtRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let range = Range(match.range, in: xml) else { return nil }
            let sdtXML = String(xml[range])
            guard let rawTag = tagValue(in: sdtXML),
                  let parsed = parseBibliographyTag(rawTag) else { return nil }
            return BibliographyControl(
                range: match.range,
                xml: sdtXML,
                bibliographyID: parsed.bibliographyID,
                style: parsed.style
            )
        }
    }

    private static func parseCitationTag(_ rawTag: String, controlXML: String) -> ParsedCitationTag? {
        let tag = xmlUnescaped(rawTag)
        let prefix = "swiftlib:v3:cite:"
        guard tag.hasPrefix(prefix) else { return nil }
        let rest = String(tag.dropFirst(prefix.count))
        let parts = rest.components(separatedBy: ":")
        if parts.count >= 3 {
            let citationID = parts[0].lowercased()
            let style = parts[1].removingPercentEncoding ?? parts[1]
            let ids = parseIDs(parts[2])
            guard !citationID.isEmpty, !ids.isEmpty else { return nil }
            return ParsedCitationTag(citationID: citationID, style: style, referenceIDs: ids, isShortTag: false)
        }

        guard !rest.isEmpty, let payload = fallbackPayload(in: controlXML) else { return nil }
        return ParsedCitationTag(
            citationID: rest.lowercased(),
            style: payload.style,
            referenceIDs: payload.referenceIDs,
            isShortTag: true
        )
    }

    private static func parseBibliographyTag(_ rawTag: String) -> ParsedBibliographyTag? {
        let tag = xmlUnescaped(rawTag)
        let prefix = "swiftlib:v3:bib:"
        guard tag.hasPrefix(prefix) else { return nil }
        let rest = String(tag.dropFirst(prefix.count))
        let parts = rest.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        return ParsedBibliographyTag(
            bibliographyID: parts[0].lowercased(),
            style: parts[1].removingPercentEncoding ?? parts[1]
        )
    }

    private static func fallbackPayload(in controlXML: String) -> (style: String, referenceIDs: [Int64])? {
        guard let match = placeholderPayloadRegex.firstMatch(
            in: controlXML,
            range: NSRange(controlXML.startIndex..., in: controlXML)
        ),
              let range = Range(match.range(at: 1), in: controlXML) else {
            return nil
        }
        let raw = xmlUnescaped(String(controlXML[range]))
        let prefix = "swiftlib:v3:payload:"
        guard raw.hasPrefix(prefix) else { return nil }
        let rest = String(raw.dropFirst(prefix.count))
        guard let split = rest.firstIndex(of: ":") else { return nil }
        let style = String(rest[..<split]).removingPercentEncoding ?? String(rest[..<split])
        let ids = parseIDs(String(rest[rest.index(after: split)...]))
        guard !ids.isEmpty else { return nil }
        return (style, ids)
    }

    private static func tagValue(in controlXML: String) -> String? {
        guard let match = tagRegex.firstMatch(
            in: controlXML,
            range: NSRange(controlXML.startIndex..., in: controlXML)
        ),
              let range = Range(match.range(at: 1), in: controlXML) else {
            return nil
        }
        return String(controlXML[range])
    }

    private static func contentRange(in controlXML: String) -> NSRange? {
        contentRegex.firstMatch(
            in: controlXML,
            range: NSRange(controlXML.startIndex..., in: controlXML)
        )?.range
    }

    private static func parseIDs(_ csv: String) -> [Int64] {
        csv.split(separator: ",")
            .compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func duplicateCitationsByParagraph(in xml: String) -> [WordDOCXDuplicateCitation] {
        var duplicates: [WordDOCXDuplicateCitation] = []
        for (index, match) in paragraphRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).enumerated() {
            guard let range = Range(match.range, in: xml) else { continue }
            let paragraphXML = String(xml[range])
            let ids = scanCitationControls(in: paragraphXML).flatMap(\.referenceIDs)
            let counts = Dictionary(ids.map { ($0, 1) }, uniquingKeysWith: +)
            duplicates.append(contentsOf: counts
                .filter { $0.value > 1 }
                .map { WordDOCXDuplicateCitation(paragraphIndex: index + 1, referenceID: $0.key, count: $0.value) }
                .sorted { $0.referenceID < $1.referenceID })
        }
        return duplicates
    }

    private static func countBibliographyEntries(
        in xml: String,
        bibliographyControls: [BibliographyControl]
    ) -> Int {
        if !bibliographyControls.isEmpty {
            return bibliographyControls.reduce(0) { total, control in
                total + paragraphTexts(in: control.xml)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .count
            }
        }
        return WordCitationMarker.extractBibliographyEntries(from: xml).count
    }

    private static func paragraphTexts(in xml: String) -> [String] {
        paragraphRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).map { match in
            guard let range = Range(match.range, in: xml) else { return "" }
            return textContent(in: String(xml[range]))
        }
    }

    private static func textContent(in xml: String) -> String {
        textNodeRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            return xmlUnescaped(String(xml[range]))
        }.joined()
    }

    private static func citationContentXML(text: String, superscript: Bool) -> String {
        let rPr = superscript ? "<w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr>" : ""
        return "<w:sdtContent><w:r>\(rPr)<w:t xml:space=\"preserve\">\(xmlEscaped(text))</w:t></w:r></w:sdtContent>"
    }

    private static func bibliographyContentXML(entries: [String], templatePPr: String?) -> String {
        let paragraphs = entries.map { entry -> String in
            let pPr = templatePPr ?? "<w:pPr><w:pStyle w:val=\"Normal\"/></w:pPr>"
            return "<w:p>\(pPr)<w:r><w:t xml:space=\"preserve\">\(xmlEscaped(entry))</w:t></w:r></w:p>"
        }.joined()
        return "<w:sdtContent>\(paragraphs)</w:sdtContent>"
    }

    private static func firstParagraphProperties(in xml: String) -> String? {
        guard let paragraph = paragraphRegex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let paragraphRange = Range(paragraph.range, in: xml) else { return nil }
        let paragraphXML = String(xml[paragraphRange])
        guard let pPr = pPrRegex.firstMatch(in: paragraphXML, range: NSRange(paragraphXML.startIndex..., in: paragraphXML)),
              let pPrRange = Range(pPr.range, in: paragraphXML) else { return nil }
        return String(paragraphXML[pPrRange])
    }

    private static func newBibliographyControlXML(style: String, contentXML: String) -> String {
        let id = UUID().uuidString.lowercased()
        let tag = "swiftlib:v3:bib:\(id):\(style.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? style)"
        let controlID = Int.random(in: 100_000...999_999)
        return """
        <w:sdt><w:sdtPr><w:id w:val="\(controlID)"/><w:alias w:val="SwiftLib Bibliography"/><w:tag w:val="\(xmlEscaped(tag))"/></w:sdtPr>\(contentXML)</w:sdt>
        """
    }

    private static func insertBibliographyControl(_ controlXML: String, into xml: String) -> String {
        if let sectRange = xml.range(of: "<w:sectPr", options: .backwards) {
            var copy = xml
            copy.insert(contentsOf: controlXML, at: sectRange.lowerBound)
            return copy
        }
        if let bodyEnd = xml.range(of: "</w:body>", options: .backwards) {
            var copy = xml
            copy.insert(contentsOf: controlXML, at: bodyEnd.lowerBound)
            return copy
        }
        return xml + controlXML
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func xmlUnescaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unpackDOCX(_ inputURL: URL) throws -> (tempRoot: URL, unpackedURL: URL) {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("swiftlib-docx-\(UUID().uuidString)", isDirectory: true)
        let unpackedURL = tempRoot.appendingPathComponent("unzipped", isDirectory: true)
        try fileManager.createDirectory(at: unpackedURL, withIntermediateDirectories: true)
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", inputURL.path, unpackedURL.path]
        )
        return (tempRoot, unpackedURL)
    }

    private static func zipDOCX(from unpackedURL: URL, to outputURL: URL, tempRoot: URL) throws {
        let fileManager = FileManager.default
        let outputDir = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let temporaryOutput = tempRoot.appendingPathComponent("refreshed.docx")
        if fileManager.fileExists(atPath: temporaryOutput.path) {
            try fileManager.removeItem(at: temporaryOutput)
        }

        // Office Open Packaging convention: `[Content_Types].xml` MUST be the
        // first entry in the ZIP and is conventionally STORED (uncompressed).
        // Some Word for Mac / Office.js paths refuse to allow further content
        // control insertion on a package that violates this — the symptom is
        // a silent failure inside Word.run with no exception thrown.
        //
        // Step 1: write [Content_Types].xml first, stored (no compression).
        // Step 2: append the remaining files, deflated.
        //
        // NOTE: `-x [Content_Types].xml` is NOT used in step 2 because zip's
        // pattern matching treats `[Content_Types]` as a character-class glob,
        // causing the exclusion to fail silently — [Content_Types].xml would be
        // re-added and overwrite the first entry, breaking the packaging convention.
        // Instead, we temporarily move the file out of the tree before step 2.
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-qX0", temporaryOutput.path, "[Content_Types].xml"],
            currentDirectoryURL: unpackedURL
        )
        let ctSrc = unpackedURL.appendingPathComponent("[Content_Types].xml")
        let ctBak = tempRoot.appendingPathComponent("__content_types_bak.xml")
        try FileManager.default.moveItem(at: ctSrc, to: ctBak)
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-qrX9", "-D", temporaryOutput.path, "."],
            currentDirectoryURL: unpackedURL
        )

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.moveItem(at: temporaryOutput, to: outputURL)
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw WordCitationDOCXProcessorError.processFailed("\(executableURL.lastPathComponent) failed: \(output)")
        }
    }

    private struct ParsedCitationTag {
        let citationID: String
        let style: String
        let referenceIDs: [Int64]
        let isShortTag: Bool
    }

    private struct ParsedBibliographyTag {
        let bibliographyID: String
        let style: String
    }

    private struct CitationControl {
        let range: NSRange
        let xml: String
        let citationID: String
        let style: String
        let referenceIDs: [Int64]
        let isShortTag: Bool
    }

    private struct BibliographyControl {
        let range: NSRange
        let xml: String
        let bibliographyID: String
        let style: String
    }

    private static let sdtRegex = try! NSRegularExpression(
        pattern: #"<w:sdt\b[^>]*>.*?</w:sdt>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let tagRegex = try! NSRegularExpression(
        pattern: #"<w:tag\b[^>]*\bw:val="([^"]*)"[^>]*/?>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let placeholderPayloadRegex = try! NSRegularExpression(
        pattern: #"<w:docPart\b[^>]*\bw:val="([^"]*)""#,
        options: [.dotMatchesLineSeparators]
    )

    private static let contentRegex = try! NSRegularExpression(
        pattern: #"<w:sdtContent\b[^>]*>.*?</w:sdtContent>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let paragraphRegex = try! NSRegularExpression(
        pattern: #"<w:p\b[^>]*>.*?</w:p>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let textNodeRegex = try! NSRegularExpression(
        pattern: #"<w:t\b[^>]*>(.*?)</w:t>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let pPrRegex = try! NSRegularExpression(
        pattern: #"<w:pPr\b[^>]*>.*?</w:pPr>"#,
        options: [.dotMatchesLineSeparators]
    )
}
