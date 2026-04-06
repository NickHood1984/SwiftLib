import Foundation
import PDFKit

public enum PDFService {
    /// Import PDF file to app storage, returns relative path
    public static func importPDF(from sourceURL: URL) throws -> String {
        let storageDir = AppDatabase.pdfStorageURL
        let fileName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destURL = storageDir.appendingPathComponent(fileName)

        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        return fileName
    }

    /// Get full URL for stored PDF
    public static func pdfURL(for relativePath: String) -> URL {
        AppDatabase.pdfStorageURL.appendingPathComponent(relativePath)
    }

    /// Delete stored PDF
    public static func deletePDF(at relativePath: String) {
        let url = pdfURL(for: relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Metadata Extraction

    public struct ExtractedMetadata {
        public var title: String?
        public var authors: [AuthorName]
        public var year: Int?
        public var doi: String?
        public var abstract: String?
        public var journal: String?
        public var isbn: String?
        public var issn: String?
        public var publisher: String?
        public var edition: String?
        public var language: String?
        public var textSnippet: String?
        public var workKindHint: MetadataWorkKind

        public init(
            title: String? = nil,
            authors: [AuthorName],
            year: Int? = nil,
            doi: String? = nil,
            abstract: String? = nil,
            journal: String? = nil,
            isbn: String? = nil,
            issn: String? = nil,
            publisher: String? = nil,
            edition: String? = nil,
            language: String? = nil,
            textSnippet: String? = nil,
            workKindHint: MetadataWorkKind = .unknown
        ) {
            self.title = title
            self.authors = authors
            self.year = year
            self.doi = doi
            self.abstract = abstract
            self.journal = journal
            self.isbn = isbn
            self.issn = issn
            self.publisher = publisher
            self.edition = edition
            self.language = language
            self.textSnippet = textSnippet
            self.workKindHint = workKindHint
        }
    }

    /// Extract literature metadata from a PDF file
    public static func extractMetadata(from url: URL) -> ExtractedMetadata {
        guard let document = PDFDocument(url: url) else {
            return ExtractedMetadata(authors: [])
        }

        var metadata = ExtractedMetadata(authors: [])

        // 1. Try PDF document attributes first
        if let attrs = document.documentAttributes {
            if let title = attrs[PDFDocumentAttribute.titleAttribute] as? String,
               isUsefulDocumentTitle(title) {
                metadata.title = cleanTitle(title)
            }
            if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String,
               isUsefulDocumentAuthor(author) {
                metadata.authors = AuthorName.parseList(author)
            }
        }

        // 2. Extract text from first 3 pages for analysis (title page, copyright page, contents)
        let maxPages = min(document.pageCount, 3)
        var fullText = ""
        for i in 0..<maxPages {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }

        fullText = normalizePDFText(fullText)
        guard !fullText.isEmpty else { return metadata }
        metadata.textSnippet = String(fullText.prefix(800)).swiftlib_nilIfBlank

        // 3. Extract DOI
        if metadata.doi == nil {
            metadata.doi = extractDOI(from: fullText)
        }

        metadata.isbn = extractISBN(from: fullText)
        metadata.issn = extractISSN(from: fullText)
        metadata.publisher = extractPublisher(from: fullText)
        metadata.edition = extractEdition(from: fullText)
        metadata.language = MetadataResolution.containsHanCharacters(fullText) ? "zh-CN" : "en"

        // 4. Extract year if not found
        if metadata.year == nil {
            metadata.year = extractYear(from: fullText)
        }

        // 5. Try to extract title from first page text if not in attributes
        if metadata.title == nil || metadata.title?.isEmpty == true {
            metadata.title = extractTitle(from: fullText)
        } else {
            metadata.title = metadata.title.flatMap(cleanTitle(_:))
        }

        // 6. Try to extract authors from the first page body
        let bodyAuthors = extractAuthors(from: fullText, title: metadata.title)
        if bodyAuthors.count > metadata.authors.count {
            metadata.authors = bodyAuthors
        }

        // 7. Try to extract journal / source
        if metadata.journal == nil {
            metadata.journal = extractJournal(from: fullText, title: metadata.title)
        }

        // 8. Try to find abstract
        metadata.abstract = extractAbstract(from: fullText)
        metadata.workKindHint = detectWorkKind(from: fullText, metadata: metadata)

        return metadata
    }

    private static func extractISBN(from text: String) -> String? {
        let patterns = [
            #"ISBN[\s:：]*((?:97[89][-\s]?)?\d(?:[-\s]?\d){8,16}[\dXx])"#,
            #"\b((?:97[89][-\s]?)?\d(?:[-\s]?\d){8,16}[\dXx])\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let normalized = String(text[range]).replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression)
                if normalized.count == 10 || normalized.count == 13 {
                    return normalized.uppercased()
                }
            }
        }
        return nil
    }

    private static func extractISSN(from text: String) -> String? {
        let pattern = #"ISSN[\s:：]*([0-9]{4}-?[0-9Xx]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let normalized = String(text[range]).uppercased().replacingOccurrences(of: "-", with: "")
        guard normalized.count == 8 else { return nil }
        return "\(normalized.prefix(4))-\(normalized.suffix(4))"
    }

    private static func extractPublisher(from text: String) -> String? {
        let patterns = [
            #"([^\n]{2,40}出版社)"#,
            #"出版(?:社|单位)[\s:：]*([^\n]{2,40})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines).swiftlib_nilIfBlank
            }
        }
        return nil
    }

    private static func extractEdition(from text: String) -> String? {
        let pattern = #"((?:第\s*\d+\s*版)|(?:\d+\s*版))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private static func detectWorkKind(from text: String, metadata: ExtractedMetadata) -> MetadataWorkKind {
        let normalized = text.lowercased()
        if metadata.isbn != nil || metadata.publisher != nil || metadata.edition != nil {
            return .book
        }
        let thesisTokens = ["博士学位论文", "硕士学位论文", "学位授予单位", "答辩日期", "导师"]
        if thesisTokens.contains(where: text.contains) {
            return .thesis
        }
        let conferenceTokens = ["会议论文", "研讨会", "proceedings", "conference"]
        if conferenceTokens.contains(where: normalized.contains) {
            return .conferencePaper
        }
        let reportTokens = ["研究报告", "技术报告", "report"]
        if reportTokens.contains(where: normalized.contains) {
            return .report
        }
        if metadata.doi != nil || metadata.issn != nil || metadata.journal != nil {
            return .journalArticle
        }
        return .unknown
    }

    private static func extractDOI(from text: String) -> String? {
        let patterns = [
            #"(?:doi|DOI)[\s:：]*\s*(10\.\d{4,9}\/[^\s]+[^\s\.,;\]\)])"#,
            #"(10\.\d{4,9}\/[^\s]+[^\s\.,;\]\)])"#,
            #"https?://(?:dx\.)?doi\.org/(10\.\d{4,9}\/[^\s]+[^\s\.,;\]\)])"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                var doi = String(text[range])
                while doi.hasSuffix(".") || doi.hasSuffix(",") || doi.hasSuffix(")") {
                    doi = String(doi.dropLast())
                }
                return doi
            }
        }
        return nil
    }

    private static func extractYear(from text: String) -> Int? {
        let prefix = String(text.prefix(2000))
        let pattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
              let range = Range(match.range(at: 1), in: prefix) else {
            return nil
        }
        return Int(prefix[range])
    }

    private static func extractTitle(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidates = Array(lines.prefix(20))
        guard !candidates.isEmpty else { return nil }

        let scored = candidates.enumerated().compactMap { index, line -> (String, Int)? in
            let cleaned = line
                .replacingOccurrences(of: #"[①②③④⑤⑥⑦⑧⑨⑩\*\†\‡]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            guard cleaned.count >= 6, cleaned.count <= 140 else { return nil }

            let lowered = cleaned.lowercased()
            let blockedTokens = [
                "abstract", "摘要", "关键词", "keyword", "doi", "issn", "作者", "author",
                "收稿日期", "中图分类号", "基金项目", "email", "e-mail"
            ]
            guard !blockedTokens.contains(where: lowered.contains) else { return nil }

            var score = 0
            if MetadataResolution.containsHanCharacters(cleaned) { score += 24 }
            if index < 4 { score += 20 - (index * 4) }
            if cleaned.count >= 10 && cleaned.count <= 40 { score += 18 }
            if !lowered.contains("university") && !cleaned.contains("@") { score += 8 }
            if lowered.contains("研究") || lowered.contains("analysis") || lowered.contains("study") { score += 6 }
            return (cleanTitle(cleaned), score)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private static func extractAbstract(from text: String) -> String? {
        let patterns = [
            #"摘\s*要\s*[:：]?\s*([\s\S]{40,2000}?)(?=\n\s*(?:关键词|关键字|1[\.\s、]|一、|引言|Abstract))"#,
            #"(?i)abstract\s*[\n\r:.\-—]+\s*([\s\S]{50,2000}?)(?=\n\s*(?:keywords?|introduction|1[\.\s]|i[\.\s]))"#,
            #"(?i)abstract\s*[\n\r:.\-—]+\s*(.{50,1500})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let abstract = String(text[range])
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if abstract.count >= 50 {
                    return String(abstract.prefix(2000))
                }
            }
        }
        return nil
    }

    private static func extractAuthors(from text: String, title: String?) -> [AuthorName] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let titleLineIndex = title.flatMap { target in
            let normalizedTarget = MetadataResolution.normalizedComparableText(target)
            return lines.firstIndex { MetadataResolution.normalizedComparableText($0) == normalizedTarget }
        }

        let start = min(max((titleLineIndex ?? -1) + 1, 0), lines.count)
        let candidateLines = Array(lines.dropFirst(start).prefix(8))

        for (index, line) in candidateLines.enumerated() {
            if isLikelyAuthorNoise(line) { continue }

            var combined = line
            if index + 1 < candidateLines.count {
                let next = candidateLines[index + 1]
                if looksLikeAuthorContinuation(next) {
                    combined += " " + next
                }
            }

            if let chineseAuthors = extractChineseAuthors(from: combined), !chineseAuthors.isEmpty {
                return chineseAuthors
            }

            let normalized = combined
                .replacingOccurrences(of: #"作者[:：]?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[\d\*\†\‡#]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

            let parsed = AuthorName.parseList(normalized)
            if !parsed.isEmpty, parsed.count <= 8, parsed.allSatisfy({ !$0.family.isEmpty }) {
                return parsed
            }
        }

        return []
    }

    private static func extractJournal(from text: String, title: String?) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let titleNormalized = title.map(MetadataResolution.normalizedComparableText(_:))

        for line in lines.prefix(12) {
            if let range = line.range(of: #"[（(]([^()（）]+(?:学报|杂志|期刊|科学|工程|大学|学院|报|论坛|学刊))[)）]"#, options: .regularExpression) {
                let matched = String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                if !matched.isEmpty {
                    return matched
                }
            }
            let normalized = MetadataResolution.normalizedComparableText(line)
            if let titleNormalized, normalized == titleNormalized { continue }
            if line.range(of: #"(?:学报|杂志|期刊|科学|工程|大学|学院|报|论坛|学刊)"#, options: .regularExpression) != nil,
               !line.contains("关键词"),
               !line.contains("摘要"),
               line.count <= 40 {
                return line
            }
        }

        return nil
    }

    private static func normalizePDFText(_ text: String) -> String {
        let folded = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return folded
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\s*[∗\*\†\‡]+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulDocumentTitle(_ title: String) -> Bool {
        let cleaned = cleanTitle(title)
        return !MetadataResolution.isSuspiciousExtractedTitle(cleaned)
    }

    private static func isUsefulDocumentAuthor(_ author: String) -> Bool {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        let blocked = ["cnki", "anonymous", "作者", "author"]
        guard !blocked.contains(where: lowered.contains) else { return false }

        if let chineseAuthors = extractChineseAuthors(from: trimmed), !chineseAuthors.isEmpty {
            return true
        }

        let parsed = AuthorName.parseList(trimmed)
        return !parsed.isEmpty && parsed.count <= 8 && parsed.allSatisfy { !$0.family.isEmpty }
    }

    private static func isLikelyAuthorNoise(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.range(of: #"^[∗\*\†\‡]+$"#, options: .regularExpression) != nil { return true }

        let lowered = trimmed.lowercased()
        let blockedTokens = [
            "摘要", "abstract", "关键词", "keyword", "doi", "收稿日期", "基金项目",
            "大学", "学院", "研究所", "实验室", "department", "university", "institute", "@"
        ]
        return blockedTokens.contains(where: lowered.contains)
    }

    private static func looksLikeAuthorContinuation(_ line: String) -> Bool {
        if isLikelyAuthorNoise(line) { return false }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("，") || trimmed.hasPrefix(",") { return true }
        return extractChineseAuthors(from: trimmed)?.isEmpty == false
    }

    private static func extractChineseAuthors(from text: String) -> [AuthorName]? {
        var normalized = normalizePDFText(text)
        normalized = normalized.replacingOccurrences(of: #"(?<=\p{Han})\s+(?=\p{Han})"#, with: "", options: .regularExpression)
        normalized = normalized
            .replacingOccurrences(of: #"作者[:：]?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\d∗\*\†\‡#]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[，,；;/＆&]+"#, with: "|", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        let segments = normalized.split(separator: "|").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let names = segments.filter {
            $0.range(of: #"^[\p{Han}]{2,4}(?:·[\p{Han}]{1,6})?$"#, options: .regularExpression) != nil
        }
        guard !names.isEmpty else { return nil }
        return names.map { AuthorName(given: "", family: $0) }
    }

    /// Import PDF and extract metadata, returning a pre-filled Reference
    public static func importPDFWithMetadata(from sourceURL: URL) throws -> (pdfPath: String, reference: Reference) {
        let prepared = try prepareImportedPDF(from: sourceURL)
        return (prepared.pdfPath, prepared.reference)
    }

    public static func prepareImportedPDF(from sourceURL: URL) throws -> (pdfPath: String, extracted: ExtractedMetadata, reference: Reference) {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let meta = extractMetadata(from: sourceURL)

        let storageDir = AppDatabase.pdfStorageURL
        let fileName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destURL = storageDir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let ref = Reference(
            title: meta.title ?? sourceURL.deletingPathExtension().lastPathComponent,
            authors: meta.authors,
            year: meta.year,
            journal: meta.journal,
            doi: meta.doi,
            abstract: meta.abstract,
            pdfPath: fileName,
            referenceType: meta.workKindHint.referenceType,
            publisher: meta.publisher,
            edition: meta.edition,
            isbn: meta.isbn,
            issn: meta.issn,
            language: meta.language
        )

        return (fileName, meta, ref)
    }
}
