import Foundation

public struct WordCitationMarkerReport: Codable {
    public let inputPath: String
    public let outputPath: String
    public let bibliographyEntryCount: Int
    public let mappedBibliographyEntryCount: Int
    public let taggedCitationCount: Int
    public let skippedCitationCount: Int
    public let unmatchedBibliographyNumbers: [Int]
    public let skippedCitationMarkers: [String]
}

public enum WordCitationMarkerError: LocalizedError {
    case missingDocumentXML
    case unsupportedExistingSwiftLibTags
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingDocumentXML:
            return "The .docx archive does not contain word/document.xml"
        case .unsupportedExistingSwiftLibTags:
            return "The document already contains SwiftLib citation tags; this command only handles plain-text citations."
        case .processFailed(let message):
            return message
        }
    }
}

public enum WordCitationMarker {
    public struct BibliographyEntry: Equatable {
        public let number: Int
        public let text: String
    }

    public struct CitationMutationResult: Equatable {
        public let xml: String
        public let taggedCitationCount: Int
        public let skippedCitationMarkers: [String]
    }

    public static func markDOCX(
        at inputURL: URL,
        outputURL: URL,
        references: [Reference],
        style: String = "nature"
    ) throws -> WordCitationMarkerReport {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("swiftlib-docx-tag-\(UUID().uuidString)", isDirectory: true)
        let unpackedURL = tempRoot.appendingPathComponent("unzipped", isDirectory: true)

        try fileManager.createDirectory(at: unpackedURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", inputURL.path, unpackedURL.path]
        )

        let documentURL = unpackedURL.appendingPathComponent("word/document.xml")
        guard fileManager.fileExists(atPath: documentURL.path) else {
            throw WordCitationMarkerError.missingDocumentXML
        }

        var xml = try String(contentsOf: documentURL, encoding: .utf8)
        if xml.contains("swiftlib:v3:cite:") || xml.contains("swiftlib:v3:bib:") {
            throw WordCitationMarkerError.unsupportedExistingSwiftLibTags
        }

        let bibliographyEntries = extractBibliographyEntries(from: xml)
        let referenceNumberMap = buildReferenceNumberMap(from: bibliographyEntries, references: references)
        let mutation = markCitationRuns(in: xml, referenceNumberMap: referenceNumberMap, style: style)
        xml = mutation.xml

        try xml.write(to: documentURL, atomically: true, encoding: .utf8)

        let outputDir = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-qr", outputURL.path, "."],
            currentDirectoryURL: unpackedURL
        )

        let unmatchedNumbers = bibliographyEntries
            .map(\.number)
            .filter { referenceNumberMap[$0] == nil }

        return WordCitationMarkerReport(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            bibliographyEntryCount: bibliographyEntries.count,
            mappedBibliographyEntryCount: referenceNumberMap.count,
            taggedCitationCount: mutation.taggedCitationCount,
            skippedCitationCount: mutation.skippedCitationMarkers.count,
            unmatchedBibliographyNumbers: unmatchedNumbers,
            skippedCitationMarkers: mutation.skippedCitationMarkers
        )
    }

    public static func extractBibliographyEntries(from documentXML: String) -> [BibliographyEntry] {
        let paragraphs = paragraphRegex.matches(in: documentXML, range: NSRange(documentXML.startIndex..., in: documentXML))
        return paragraphs.compactMap { match in
            guard let range = Range(match.range, in: documentXML) else { return nil }
            let paragraphXML = String(documentXML[range])
            let text = paragraphText(from: paragraphXML)
            guard let prefixRange = text.range(of: #"^\[(\d+)\]\s*"#, options: .regularExpression) else {
                return nil
            }
            let prefix = String(text[prefixRange])
            guard let numberMatch = prefix.range(of: #"\d+"#, options: .regularExpression),
                  let number = Int(prefix[numberMatch]) else {
                return nil
            }
            let remainder = String(text[prefixRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remainder.isEmpty else { return nil }
            return BibliographyEntry(number: number, text: remainder)
        }
    }

    public static func buildReferenceNumberMap(
        from bibliographyEntries: [BibliographyEntry],
        references: [Reference]
    ) -> [Int: Int64] {
        var result: [Int: Int64] = [:]
        let candidates = references.compactMap { reference -> MatchCandidate? in
            guard let id = reference.id else { return nil }
            let titleKey = normalizedMatchKey(reference.title)
            guard titleKey.count >= 4 else { return nil }
            return MatchCandidate(
                id: id,
                titleKey: titleKey,
                doiKey: normalizedDOI(reference.doi),
                journalKey: normalizedMatchKey(reference.journal ?? ""),
                year: reference.year,
                authorKeys: reference.authors.prefix(4).flatMap { author in
                    [author.family, author.displayName]
                        .map(normalizedMatchKey)
                        .filter { !$0.isEmpty }
                }
            )
        }

        for entry in bibliographyEntries {
            let fingerprint = BibliographyFingerprint(entry.text)
            let best = candidates
                .map { candidate in
                    (candidate: candidate, score: candidate.score(against: fingerprint))
                }
                .filter { $0.score >= 3_600 }
                .sorted {
                    if $0.score == $1.score {
                        return $0.candidate.titleKey.count > $1.candidate.titleKey.count
                    }
                    return $0.score > $1.score
                }
                .first

            if let best {
                result[entry.number] = best.candidate.id
            }
        }

        return result
    }

    public static func markCitationRuns(
        in documentXML: String,
        referenceNumberMap: [Int: Int64],
        style: String
    ) -> CitationMutationResult {
        let mutableXML = NSMutableString(string: documentXML)
        let matches = citationRunMatches(in: documentXML)
        var taggedCitationCount = 0
        var skippedCitationMarkers: [String] = []

        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: documentXML),
                  let textRange = Range(match.range(at: 1), in: documentXML) else {
                continue
            }

            let runXML = String(documentXML[fullRange])
            let markerText = String(documentXML[textRange])
            if isBibliographyPrefixRun(markerText, runRange: fullRange, in: documentXML) {
                continue
            }
            guard let numbers = parseCitationNumbers(from: markerText), !numbers.isEmpty else {
                skippedCitationMarkers.append(markerText)
                continue
            }

            let referenceIDs = numbers.compactMap { referenceNumberMap[$0] }
            guard referenceIDs.count == numbers.count else {
                skippedCitationMarkers.append(markerText)
                continue
            }

            let citationID = UUID().uuidString.lowercased()
            let encodedStyle = encodeURIComponent(style)
            let fullTag = "swiftlib:v3:cite:\(citationID):\(encodedStyle):\(referenceIDs.map(String.init).joined(separator: ","))"
            // Word rejects content-control tags longer than ~220 characters.
            // When the full tag exceeds this limit, fall back to a short tag
            // (UUID only) and embed the style+ids as a placeholder payload so
            // the add-in can recover them during Refresh.
            let maxTagLength = 220
            let useShortTag = fullTag.count > maxTagLength
            let tag = useShortTag ? "swiftlib:v3:cite:\(citationID)" : fullTag
            let controlID = Int.random(in: 100_000...999_999)
            let placeholderXML: String
            if useShortTag {
                let fallbackPayload = xmlEscaped("swiftlib:v3:payload:\(encodedStyle):\(referenceIDs.map(String.init).joined(separator: ","))")
                placeholderXML = "<w:placeholder><w:docPart w:val=\"\(fallbackPayload)\"/></w:placeholder>"
            } else {
                placeholderXML = ""
            }
            let replacement = """
            <w:sdt><w:sdtPr><w:id w:val="\(controlID)"/><w:alias w:val="SwiftLib Citation"/>\(placeholderXML)<w:tag w:val="\(xmlEscaped(tag))"/></w:sdtPr><w:sdtContent>\(runXML)</w:sdtContent></w:sdt>
            """
            mutableXML.replaceCharacters(in: match.range(at: 0), with: replacement)
            taggedCitationCount += 1
        }

        return CitationMutationResult(
            xml: mutableXML as String,
            taggedCitationCount: taggedCitationCount,
            skippedCitationMarkers: skippedCitationMarkers
        )
    }

    private static func paragraphText(from paragraphXML: String) -> String {
        let matches = textNodeRegex.matches(in: paragraphXML, range: NSRange(paragraphXML.startIndex..., in: paragraphXML))
        let pieces: [String] = matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: paragraphXML) else { return nil }
            return xmlUnescaped(String(paragraphXML[range]))
        }
        return pieces.joined()
    }

    private static func parseCitationNumbers(from markerText: String) -> [Int]? {
        let trimmed = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "[", trimmed.last == "]" else { return nil }
        let inner = trimmed.dropFirst().dropLast()
        var values: [Int] = []

        for part in inner.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { continue }

            if let rangeSeparator = token.firstIndex(where: { $0 == "-" || $0 == "–" || $0 == "—" }) {
                let startPart = token[..<rangeSeparator].trimmingCharacters(in: .whitespacesAndNewlines)
                let endPart = token[token.index(after: rangeSeparator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let start = Int(startPart), let end = Int(endPart), start <= end else { return nil }
                values.append(contentsOf: Array(start...end))
            } else {
                guard let value = Int(token) else { return nil }
                values.append(value)
            }
        }

        return values.isEmpty ? nil : values
    }

    private static func citationRunMatches(in documentXML: String) -> [NSTextCheckingResult] {
        citationRunRegex.matches(in: documentXML, range: NSRange(documentXML.startIndex..., in: documentXML))
    }

    private static func isBibliographyPrefixRun(
        _ markerText: String,
        runRange: Range<String.Index>,
        in documentXML: String
    ) -> Bool {
        guard let paragraphRange = paragraphRange(containing: runRange, in: documentXML) else {
            return false
        }

        let prefixXML = String(documentXML[paragraphRange.lowerBound..<runRange.lowerBound])
        let prefixText = paragraphText(from: prefixXML).trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefixText.isEmpty else {
            return false
        }

        let suffixXML = String(documentXML[runRange.upperBound..<paragraphRange.upperBound])
        let suffixText = paragraphText(from: suffixXML).trimmingCharacters(in: .whitespacesAndNewlines)
        return !suffixText.isEmpty && suffixText != markerText
    }

    private static func paragraphRange(
        containing range: Range<String.Index>,
        in documentXML: String
    ) -> Range<String.Index>? {
        guard let paragraphStart = documentXML[..<range.lowerBound].range(of: "<w:p", options: .backwards)?.lowerBound,
              let paragraphEnd = documentXML[range.upperBound...].range(of: "</w:p>")?.upperBound else {
            return nil
        }
        return paragraphStart..<paragraphEnd
    }

    private static func normalizedMatchKey(_ text: String) -> String {
        let transformed = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let lowered = transformed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let scalars = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || isCJKScalar(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func normalizedDOI(_ doi: String?) -> String {
        normalizedMatchKey(doi ?? "")
    }

    private static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
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

    private static func encodeURIComponent(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private static func bibliographyTitleText(from entryText: String) -> String {
        let preTypeMarker: String
        if let typeRange = entryText.range(of: #"\[[A-Z]\]"#, options: .regularExpression) {
            preTypeMarker = String(entryText[..<typeRange.lowerBound])
        } else {
            preTypeMarker = entryText
        }

        let delimiters = [". ", "．", "。"]
        for delimiter in delimiters {
            if let delimiterRange = preTypeMarker.range(of: delimiter, options: .backwards) {
                let candidate = preTypeMarker[delimiterRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count >= 4 {
                    return candidate
                }
            }
        }

        return preTypeMarker.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleBigrams(for text: String) -> [Substring] {
        guard text.count >= 2 else { return text.isEmpty ? [] : [Substring(text)] }
        let characters = Array(text)
        return (0..<(characters.count - 1)).map { index in
            Substring(String(characters[index...index + 1]))
        }
    }

    private static func multisetOverlapRatio(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        var lhsCounts: [Character: Int] = [:]
        var rhsCounts: [Character: Int] = [:]
        lhs.forEach { lhsCounts[$0, default: 0] += 1 }
        rhs.forEach { rhsCounts[$0, default: 0] += 1 }

        let overlap = Set(lhsCounts.keys).union(rhsCounts.keys).reduce(0) { partial, character in
            partial + min(lhsCounts[character, default: 0], rhsCounts[character, default: 0])
        }
        return Double(overlap) / Double(max(lhs.count, rhs.count))
    }

    private static func diceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        let lhsBigrams = titleBigrams(for: lhs)
        let rhsBigrams = titleBigrams(for: rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else { return 0 }

        var lhsCounts: [Substring: Int] = [:]
        var rhsCounts: [Substring: Int] = [:]
        lhsBigrams.forEach { lhsCounts[$0, default: 0] += 1 }
        rhsBigrams.forEach { rhsCounts[$0, default: 0] += 1 }

        let intersection = Set(lhsCounts.keys).union(rhsCounts.keys).reduce(0) { partial, token in
            partial + min(lhsCounts[token, default: 0], rhsCounts[token, default: 0])
        }
        return (2.0 * Double(intersection)) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func longestCommonSubsequenceRatio(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let rhsCharacters = Array(rhs)
        var previous = Array(repeating: 0, count: rhsCharacters.count + 1)

        for lhsCharacter in lhs {
            var current = [0]
            current.reserveCapacity(rhsCharacters.count + 1)
            for (index, rhsCharacter) in rhsCharacters.enumerated() {
                let nextValue: Int
                if lhsCharacter == rhsCharacter {
                    nextValue = previous[index] + 1
                } else {
                    nextValue = max(previous[index + 1], current[index])
                }
                current.append(nextValue)
            }
            previous = current
        }

        return Double(previous.last ?? 0) / Double(max(lhs.count, rhs.count))
    }

    private static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let overlap = multisetOverlapRatio(lhs, rhs)
        let dice = diceCoefficient(lhs, rhs)
        let lcs = longestCommonSubsequenceRatio(lhs, rhs)
        return max(lcs, (overlap * 0.55) + (dice * 0.45))
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
            throw WordCitationMarkerError.processFailed("\(executableURL.lastPathComponent) failed: \(output)")
        }
    }

    private struct MatchCandidate {
        let id: Int64
        let titleKey: String
        let doiKey: String
        let journalKey: String
        let year: Int?
        let authorKeys: [String]

        func score(against entry: BibliographyFingerprint) -> Int {
            var score = 0
            if !doiKey.isEmpty && entry.normalizedEntry.contains(doiKey) {
                score += 10_000
            }
            let journalMatch = !journalKey.isEmpty && entry.normalizedEntry.contains(journalKey)
            let yearMatch = year == entry.year
            let authorMatch = authorKeys.contains { key in
                !key.isEmpty && entry.normalizedEntry.contains(key)
            }

            if entry.titleKey.contains(titleKey) || titleKey.contains(entry.titleKey) {
                score += 5_000 + titleKey.count
            } else {
                let similarity = WordCitationMarker.titleSimilarity(titleKey, entry.titleKey)
                guard similarity >= 0.55 else {
                    return score
                }
                guard yearMatch || journalMatch || authorMatch else {
                    return score
                }
                score += 3_200 + Int(similarity * 1_000)
            }

            if journalMatch {
                score += 250
            }

            if yearMatch {
                score += 120
            }

            if authorMatch {
                score += 80
            }
            return score
        }
    }

    private struct BibliographyFingerprint {
        let rawEntry: String
        let normalizedEntry: String
        let titleKey: String
        let year: Int?

        init(_ rawEntry: String) {
            self.rawEntry = rawEntry
            normalizedEntry = WordCitationMarker.normalizedMatchKey(rawEntry)
            titleKey = WordCitationMarker.normalizedMatchKey(
                WordCitationMarker.bibliographyTitleText(from: rawEntry)
            )

            if let yearRange = rawEntry.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
                year = Int(rawEntry[yearRange])
            } else {
                year = nil
            }
        }
    }

    private static let paragraphRegex = try! NSRegularExpression(
        pattern: #"<w:p\b[^>]*>.*?</w:p>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let textNodeRegex = try! NSRegularExpression(
        pattern: #"<w:t\b[^>]*>(.*?)</w:t>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let citationRunRegex = try! NSRegularExpression(
        pattern: #"<w:r\b[^>]*>(?:(?!</w:r>).)*?<w:t\b[^>]*>(\[[0-9,\-\–\—\s]+\])</w:t>(?:(?!</w:r>).)*?</w:r>"#,
        options: [.dotMatchesLineSeparators]
    )
}
