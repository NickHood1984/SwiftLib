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
    public let bodyCitationNumbers: [Int]
    public let bibliographyEntryNumbers: [Int]
    public let listedButUncitedBibliographyNumbers: [Int]
    public let citedButUnlistedBodyCitationNumbers: [Int]
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
        let footnotesURL = unpacked.unpackedURL.appendingPathComponent("word/footnotes.xml")
        let footnotesXML = FileManager.default.fileExists(atPath: footnotesURL.path)
            ? (try? String(contentsOf: footnotesURL, encoding: .utf8))
            : nil
        return auditDocumentXML(xml, footnotesXML: footnotesXML, inputPath: inputURL.path, references: references)
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

        // Load footnotes.xml if present
        let footnotesURL = unpacked.unpackedURL.appendingPathComponent("word/footnotes.xml")
        let footnotesXMLOriginal: String? = FileManager.default.fileExists(atPath: footnotesURL.path)
            ? (try? String(contentsOf: footnotesURL, encoding: .utf8))
            : nil

        let footnoteCitations = footnotesXMLOriginal.map { scanFootnoteCitations(in: $0) } ?? []

        let audit = auditDocumentXML(xml, footnotesXML: footnotesXMLOriginal, inputPath: inputURL.path, references: references)
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
        let style = preferredStyle(
            citations: citations,
            bibliographyControls: bibliographyControls,
            footnoteCitations: footnoteCitations,
            defaultStyle: defaultStyle
        )

        // Combine SDT citations and footnote citations for rendering (footnotes follow body in order)
        let sdtRefIDs = orderedUnique(citations.flatMap(\.referenceIDs))
        let fnRefIDs = orderedUnique(footnoteCitations.flatMap(\.referenceIDs))
        let allRefIDs = orderedUnique(sdtRefIDs + fnRefIDs)
        let cslItems = allRefIDs.compactMap { referencesByID[$0] }.map { CSLExportService.cslJSONObject(for: $0) }

        // Read locator/prefix/suffix data stored in the document's CustomXmlPart by the Word add-in
        let citationItemsMap = readCitationItemsMap(from: unpacked.unpackedURL)

        // SDT citations use byte offsets as positions; footnote citations follow with offsets beyond body
        let bodyLength = xml.utf16.count
        let citeprocCitations: [CitationDocumentCluster] =
            citations.map { c in
                CitationDocumentCluster(
                    id: c.citationID,
                    itemIDs: orderedUnique(c.referenceIDs).map { String($0) },
                    position: c.range.location,
                    citationItems: citationItemsMap[c.citationID]
                )
            } +
            footnoteCitations.enumerated().map { index, c in
                CitationDocumentCluster(
                    id: c.citationID,
                    itemIDs: orderedUnique(c.referenceIDs).map { String($0) },
                    position: bodyLength + index * 1000,
                    citationItems: citationItemsMap[c.citationID]
                )
            }

        let renderResult: (citationTexts: [String: String], bibliographyText: String, superscriptIDs: Set<String>, citationFormatting: CitationTextFormatting?)
        do {
            guard let r = try CiteprocJSCorePool.shared.withEngine(forStyleId: style, { engine in
                engine.setItems(cslItems)
                return try engine.renderDocument(citationClusters: citeprocCitations)
            }) else {
                throw WordCitationDOCXProcessorError.processFailed("无法加载引文样式「\(style)」，请在样式管理中确认该样式已导入。")
            }
            renderResult = r
        } catch let err as WordCitationDOCXProcessorError {
            throw err
        } catch {
            throw WordCitationDOCXProcessorError.processFailed("引文渲染失败：\(error.localizedDescription)")
        }

        let rendered = WordRenderedDocument(
            citationTexts: renderResult.citationTexts,
            superscriptCitationBookmarkNames: renderResult.superscriptIDs,
            bibliographyText: renderResult.bibliographyText,
            citationKind: CSLManager.shared.citationKind(for: style)
        )

        // Refresh SDT citations in document.xml
        let refreshedXML = refreshDocumentXML(
            xml,
            citations: citations,
            bibliographyControls: bibliographyControls,
            rendered: rendered,
            style: style
        )
        try refreshedXML.xml.write(to: documentURL, atomically: true, encoding: .utf8)

        // Refresh footnote citations in footnotes.xml (if any)
        var refreshedFootnoteCount = 0
        if let fnXML = footnotesXMLOriginal, !footnoteCitations.isEmpty {
            let (refreshedFnXML, count) = refreshFootnotesXML(fnXML, citationTexts: renderResult.citationTexts)
            refreshedFootnoteCount = count
            try refreshedFnXML.write(to: footnotesURL, atomically: true, encoding: .utf8)
        }

        try zipDOCX(from: unpacked.unpackedURL, to: outputURL, tempRoot: unpacked.tempRoot)

        // ── Back-fill cite-item options to the library ────────────────────
        // Read locator/prefix/suffix from the document's citationItemsMap and
        // persist them in citationItemOption so they survive document renaming
        // or CustomXmlPart stripping by third-party tools.
        let documentURI = inputURL.path
        Self.backfillCitationItemOptions(
            documentURI: documentURI,
            citationsMap: citationItemsMap,
            database: AppDatabase.shared
        )

        return WordDOCXRefreshReport(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            citationControlCount: citations.count + footnoteCitations.count,
            refreshedCitationCount: refreshedXML.refreshedCitationCount + refreshedFootnoteCount,
            bibliographyControlCount: bibliographyControls.count,
            refreshedBibliographyCount: refreshedXML.refreshedBibliographyCount,
            insertedBibliography: refreshedXML.insertedBibliography,
            audit: audit
        )
    }

    // MARK: - Back-fill cite-item options

    /// Persist locator/prefix/suffix/suppressAuthor to the library database.
    /// This is a best-effort call; failures are silently swallowed so they
    /// never block the DOCX refresh operation.
    private static func backfillCitationItemOptions(
        documentURI: String,
        citationsMap: [String: [CitationDocumentItemOption]],
        database: AppDatabase
    ) {
        guard !citationsMap.isEmpty else { return }
        var options: [CitationItemOption] = []
        for (citationID, items) in citationsMap {
            for item in items {
                guard let rawID = item.resolvedItemID, let rid = Int64(rawID) else { continue }

                let locator = item.locator?.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = item.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = item.prefix?.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = item.suffix?.trimmingCharacters(in: .whitespacesAndNewlines)

                // Only store rows that actually carry non-trivial options.
                let hasOptions = !(locator ?? "").isEmpty
                    || !(prefix ?? "").isEmpty
                    || !(suffix ?? "").isEmpty
                    || item.suppressAuthor
                guard hasOptions else { continue }

                options.append(CitationItemOption(
                    documentURI: documentURI,
                    citationID: citationID,
                    refID: rid,
                    locator: locator?.swiftlib_nilIfBlank,
                    label: label?.swiftlib_nilIfBlank,
                    prefix: prefix?.swiftlib_nilIfBlank,
                    suffix: suffix?.swiftlib_nilIfBlank,
                    suppressAuthor: item.suppressAuthor
                ))
            }
        }
        guard !options.isEmpty else { return }
        try? database.upsertCitationItemOptions(options)
    }

    public static func auditDocumentXML(
        _ xml: String,
        footnotesXML: String? = nil,
        inputPath: String = "",
        references: [Reference]
    ) -> WordDOCXAuditReport {
        let citations = scanCitationControls(in: xml)
        let footnoteCitations = footnotesXML.map { scanFootnoteCitations(in: $0) } ?? []
        let bibliographyControls = scanBibliographyControls(in: xml)
        let referenceIDs = Set(references.compactMap(\.id))
        let docUniqueIDs = orderedUnique(
            citations.flatMap(\.referenceIDs) + footnoteCitations.flatMap(\.referenceIDs)
        )
        let docUniqueIDSet = Set(docUniqueIDs)
        let missingInLibrary = docUniqueIDs.filter { !referenceIDs.contains($0) }
        let unusedInLibrary = references.compactMap(\.id).filter { !docUniqueIDSet.contains($0) }.sorted()
        let bibliographyEntryCount = countBibliographyEntries(in: xml, bibliographyControls: bibliographyControls)
        let bodyCitationNumbers = orderedUnique(
            citations.flatMap { displayedCitationNumbers(in: $0.xml) }
            + plainTextBodyCitationNumbers(in: xml)
        )
        let bibliographyEntryNumbers = orderedUnique(
            numberedBibliographyEntries(in: xml, bibliographyControls: bibliographyControls).map(\.number)
        )
        let bodyCitationNumberSet = Set(bodyCitationNumbers)
        let bibliographyEntryNumberSet = Set(bibliographyEntryNumbers)
        let listedButUncitedBibliographyNumbers = bibliographyEntryNumbers
            .filter { !bodyCitationNumberSet.contains($0) }
        let citedButUnlistedBodyCitationNumbers = bodyCitationNumbers
            .filter { !bibliographyEntryNumberSet.contains($0) }
        let bodyReferenceCountForBibliographyComparison = docUniqueIDs.isEmpty
            ? bodyCitationNumbers.count
            : docUniqueIDs.count
        var warnings: [String] = []
        let totalCitationCount = citations.count + footnoteCitations.count
        if bibliographyControls.isEmpty, totalCitationCount > 0, footnoteCitations.isEmpty {
            warnings.append("document has SwiftLib citations but no SwiftLib bibliography control")
        }
        if bibliographyEntryCount > 0, bibliographyEntryCount != bodyReferenceCountForBibliographyComparison {
            warnings.append("bibliography entry count does not match unique body citation count")
        }
        if !listedButUncitedBibliographyNumbers.isEmpty {
            warnings.append(
                "bibliography contains numbered entries not present in visible body citations: "
                + listedButUncitedBibliographyNumbers.map(String.init).joined(separator: ", ")
            )
        }
        if !citedButUnlistedBodyCitationNumbers.isEmpty {
            warnings.append(
                "visible body citations contain numbers not present in bibliography: "
                + citedButUnlistedBodyCitationNumbers.map(String.init).joined(separator: ", ")
            )
        }

        return WordDOCXAuditReport(
            inputPath: inputPath,
            citationControlCount: totalCitationCount,
            bibliographyControlCount: bibliographyControls.count,
            docUniqueIDs: docUniqueIDs,
            docUniqueIDCount: docUniqueIDs.count,
            libraryReferenceCount: references.count,
            citedReferenceCountInLibrary: docUniqueIDs.filter { referenceIDs.contains($0) }.count,
            missingInLibrary: missingInLibrary,
            unusedInLibrary: unusedInLibrary,
            duplicateCitationsInParagraphs: duplicateCitationsByParagraph(in: xml),
            bibliographyEntryCount: bibliographyEntryCount,
            bodyCitationNumbers: bodyCitationNumbers,
            bibliographyEntryNumbers: bibliographyEntryNumbers,
            listedButUncitedBibliographyNumbers: listedButUncitedBibliographyNumbers,
            citedButUnlistedBodyCitationNumbers: citedButUnlistedBodyCitationNumbers,
            bibliographyMatchesBodyUniqueCount: bibliographyEntryCount == bodyReferenceCountForBibliographyComparison,
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
        footnoteCitations: [FootnoteSwiftLibCitation] = [],
        defaultStyle: String
    ) -> String {
        citations.first(where: { !$0.style.isEmpty })?.style
            ?? bibliographyControls.first(where: { !$0.style.isEmpty })?.style
            ?? footnoteCitations.first(where: { !$0.style.isEmpty })?.style
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

    private static func numberedBibliographyEntries(
        in xml: String,
        bibliographyControls: [BibliographyControl]
    ) -> [WordCitationMarker.BibliographyEntry] {
        if !bibliographyControls.isEmpty {
            return bibliographyControls.flatMap { control in
                paragraphTexts(in: control.xml).compactMap { text in
                    guard let number = bibliographyEntryNumber(from: text) else { return nil }
                    return WordCitationMarker.BibliographyEntry(number: number, text: text)
                }
            }
        }
        return WordCitationMarker.extractBibliographyEntries(from: xml)
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

    private static func displayedCitationNumbers(in controlXML: String) -> [Int] {
        parseCitationNumberList(from: textContent(in: controlXML))
    }

    private static func plainTextBodyCitationNumbers(in xml: String) -> [Int] {
        var numbers: [Int] = []
        var insideBibliographySection = false

        for text in paragraphTexts(in: xml) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if isBibliographyHeading(trimmed) {
                insideBibliographySection = true
                continue
            }
            if insideBibliographySection { continue }
            if bibliographyEntryNumber(from: trimmed) != nil { continue }

            numbers.append(contentsOf: bracketedCitationNumbers(in: trimmed))
        }

        return numbers
    }

    private static func isBibliographyHeading(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return normalized == "参考文献"
            || normalized == "references"
            || normalized == "bibliography"
    }

    private static func bibliographyEntryNumber(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.first == "[", let closing = trimmed.firstIndex(of: "]") {
            let numberText = trimmed[trimmed.index(after: trimmed.startIndex)..<closing]
            let remainder = trimmed[trimmed.index(after: closing)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remainder.isEmpty else { return nil }
            return Int(numberText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var digitEnd = trimmed.startIndex
        while digitEnd < trimmed.endIndex, trimmed[digitEnd].isNumber {
            digitEnd = trimmed.index(after: digitEnd)
        }
        guard digitEnd > trimmed.startIndex, digitEnd < trimmed.endIndex else { return nil }
        let separator = trimmed[digitEnd]
        guard separator == "." || separator == ")" else { return nil }
        let remainder = trimmed[trimmed.index(after: digitEnd)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }
        return Int(trimmed[..<digitEnd])
    }

    private static func parseCitationNumberList(from text: String) -> [Int] {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.first == "[", trimmed.last == "]" {
            trimmed = String(trimmed.dropFirst().dropLast())
        } else if !trimmed.unicodeScalars.allSatisfy({ citationNumberListCharacters.contains($0) }) {
            return []
        }

        let normalized = trimmed
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "、", with: ",")
        var values: [Int] = []
        for part in normalized.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            if let separatorIndex = token.firstIndex(where: { $0 == "-" || $0 == "–" || $0 == "—" }) {
                let startText = token[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let endText = token[token.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let start = Int(startText), let end = Int(endText), start <= end else { return [] }
                values.append(contentsOf: start...end)
            } else {
                guard let value = Int(token) else { return [] }
                values.append(value)
            }
        }
        return values
    }

    private static func bracketedCitationNumbers(in text: String) -> [Int] {
        var numbers: [Int] = []
        for match in citationMarkerRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { return [] }
            numbers.append(contentsOf: parseCitationNumberList(from: "[\(text[range])]"))
        }
        return numbers
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

    // MARK: - CustomXmlPart: locator / prefix / suffix recovery

    private static let swiftlibXmlNS = "http://swiftlib.com/citations"

    /// Reads the SwiftLib CustomXmlPart stored by the Word add-in inside `customXml/item*.xml`.
    /// Returns a map from citationId → citationItems array so that locators, prefixes, suffixes,
    /// and suppress-author flags set in the add-in UI survive a CLI refresh.
    private static func readCitationItemsMap(from unpackedURL: URL) -> [String: [CitationDocumentItemOption]] {
        let customXmlDir = unpackedURL.appendingPathComponent("customXml")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: customXmlDir, includingPropertiesForKeys: nil
        ) else { return [:] }

        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = file.lastPathComponent
            // Skip *Props*.xml (metadata) — only read item content files
            guard name.hasPrefix("item"), !name.contains("Props"), file.pathExtension == "xml" else { continue }
            guard let content = try? String(contentsOf: file, encoding: .utf8),
                  content.contains(swiftlibXmlNS) else { continue }

            // Extract base64 payload between <payload encoding="base64">…</payload>
            guard let openTag = content.range(of: "<payload", options: .caseInsensitive),
                  let closeAngle = content.range(of: ">", range: openTag.upperBound..<content.endIndex),
                  let closeTag = content.range(of: "</payload>", options: .caseInsensitive,
                                               range: closeAngle.upperBound..<content.endIndex)
            else { continue }

            let b64 = content[closeAngle.upperBound..<closeTag.lowerBound]
                .components(separatedBy: .whitespacesAndNewlines).joined()
            guard let data = Data(base64Encoded: b64),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let storedCitations = json["citations"] as? [[String: Any]] ?? []
            var map: [String: [CitationDocumentItemOption]] = [:]
            for c in storedCitations {
                guard let citationId = c["citationId"] as? String,
                      let items = CitationDocumentItemOption.decodeArray(fromJSONObject: c["citationItems"]),
                      !items.isEmpty else { continue }
                map[citationId] = items
            }
            return map
        }
        return [:]
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

    private static let citationMarkerRegex = try! NSRegularExpression(
        pattern: #"[［\[\【]\s*([0-9]+(?:\s*[-–—]\s*[0-9]+)?(?:\s*[,，、]\s*[0-9]+(?:\s*[-–—]\s*[0-9]+)?)*)\s*[］\]\】]"#,
        options: []
    )

    private static let citationNumberListCharacters = CharacterSet(charactersIn: "0123456789,，、-–— \t\r\n")

    // MARK: - Footnote citation support (word/footnotes.xml)

    private struct FootnoteSwiftLibCitation {
        let citationID: String
        let style: String
        let referenceIDs: [Int64]
    }

    /// Scans footnotes.xml for SwiftLib citation markers embedded as hidden (`<w:vanish/>`) runs.
    /// Format inserted by the Word add-in:
    ///   `<w:r><w:rPr><w:vanish/></w:rPr><w:t>swiftlib:v3:cite:UUID:style:ids</w:t></w:r>`
    private static func scanFootnoteCitations(in xml: String) -> [FootnoteSwiftLibCitation] {
        footnoteTagScanRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: xml) else { return nil }
            let rawTag = xmlUnescaped(String(xml[tagRange]))
            guard let parsed = parseCitationTag(rawTag, controlXML: "") else { return nil }
            return FootnoteSwiftLibCitation(
                citationID: parsed.citationID,
                style: parsed.style,
                referenceIDs: parsed.referenceIDs
            )
        }
    }

    /// Refreshes the visible citation text in each SwiftLib footnote paragraph.
    /// Replaces everything after the hidden marker run (up to `</w:p>`) with a new run
    /// containing the rendered citation text. Returns the updated XML and the count of
    /// successfully refreshed footnotes.
    private static func refreshFootnotesXML(
        _ xml: String,
        citationTexts: [String: String]
    ) -> (xml: String, count: Int) {
        let matches = footnoteMarkerRunRegex.matches(
            in: xml, range: NSRange(xml.startIndex..., in: xml)
        ).sorted(by: { $0.range.location > $1.range.location })

        let mutable = NSMutableString(string: xml)
        var count = 0

        for match in matches {
            guard let tagRange = Range(match.range(at: 2), in: xml),
                  let visibleRange = Range(match.range(at: 3), in: xml) else { continue }

            let rawTag = xmlUnescaped(String(xml[tagRange]))
            guard let parsed = parseCitationTag(rawTag, controlXML: ""),
                  let text = citationTexts[parsed.citationID],
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let newRun = "<w:r><w:t xml:space=\"preserve\"> \(xmlEscaped(text))</w:t></w:r>"
            mutable.replaceCharacters(in: NSRange(visibleRange, in: xml), with: newRun)
            count += 1
        }

        return (mutable as String, count)
    }

    // Matches a vanished SwiftLib marker run in footnotes.xml and captures:
    //   group 1 — the entire hidden run (to preserve)
    //   group 2 — the SwiftLib tag text inside <w:t>
    //   group 3 — everything after the hidden run before </w:p> (the visible text to replace)
    private static let footnoteMarkerRunRegex = try! NSRegularExpression(
        pattern: #"(<w:r\b[^>]*>(?:(?!</w:r>).)*?<w:vanish\b[^>]*/?>"# +
                 #"(?:(?!</w:r>).)*?<w:t\b[^>]*>(swiftlib:v3:cite:[^<]+)</w:t>"# +
                 #"(?:(?!</w:r>).)*?</w:r>)((?:(?!</w:p>).)*)"#,
        options: [.dotMatchesLineSeparators]
    )

    // Lighter scan: just finds the tag text inside a hidden (vanished) run
    private static let footnoteTagScanRegex = try! NSRegularExpression(
        pattern: #"<w:vanish\b[^>]*/?>(?:(?!</w:r>).)*?<w:t\b[^>]*>(swiftlib:v3:cite:[^<]+)</w:t>"#,
        options: [.dotMatchesLineSeparators]
    )
}
