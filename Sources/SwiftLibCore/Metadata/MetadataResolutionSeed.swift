import Foundation

public struct MetadataResolutionSeed: Hashable, Codable, Sendable {
    public var fileName: String
    public var title: String?
    public var firstAuthor: String?
    public var year: Int?
    public var doi: String?
    public var journal: String?
    public var isbn: String?
    public var issn: String?
    public var publisher: String?
    public var edition: String?
    public var languageHint: MetadataLanguageHint
    public var workKindHint: MetadataWorkKind
    public var textSnippet: String?
    public var sourceURL: String?

    public init(
        fileName: String,
        title: String? = nil,
        firstAuthor: String? = nil,
        year: Int? = nil,
        doi: String? = nil,
        journal: String? = nil,
        isbn: String? = nil,
        issn: String? = nil,
        publisher: String? = nil,
        edition: String? = nil,
        languageHint: MetadataLanguageHint = .unknown,
        workKindHint: MetadataWorkKind = .unknown,
        textSnippet: String? = nil,
        sourceURL: String? = nil
    ) {
        self.fileName = fileName
        self.title = title?.swiftlib_nilIfBlank
        self.firstAuthor = firstAuthor?.swiftlib_nilIfBlank
        self.year = year
        self.doi = doi?.swiftlib_nilIfBlank
        self.journal = journal?.swiftlib_nilIfBlank
        self.isbn = isbn?.swiftlib_nilIfBlank
        self.issn = issn?.swiftlib_nilIfBlank
        self.publisher = publisher?.swiftlib_nilIfBlank
        self.edition = edition?.swiftlib_nilIfBlank
        self.languageHint = languageHint
        self.workKindHint = workKindHint
        self.textSnippet = textSnippet?.swiftlib_nilIfBlank
        self.sourceURL = sourceURL?.swiftlib_nilIfBlank
    }

    public var normalizedTitle: String? {
        title.map(MetadataResolution.normalizedComparableText(_:)).swiftlib_nilIfBlank
    }

    public var containsChineseText: Bool {
        MetadataResolution.containsHanCharacters(title) || MetadataResolution.containsHanCharacters(fileName)
    }

    public var shouldSearchCNKI: Bool {
        languageHint == .chinese || containsChineseText
    }

    public static func fromImportedPDF(url: URL, extracted: PDFService.ExtractedMetadata) -> MetadataResolutionSeed {
        let originalFileName = url.deletingPathExtension().lastPathComponent
        let cleanedFileName = MetadataResolution.cleanPDFSeedFilename(originalFileName)
        let parsed = MetadataResolution.parsePDFFileNameSeed(cleanedFileName)

        let extractedTitle = extracted.title?.swiftlib_nilIfBlank
        let title: String?
        if let extractedTitle, !MetadataResolution.isSuspiciousExtractedTitle(extractedTitle) {
            title = extractedTitle
        } else {
            title = parsed.title ?? extractedTitle ?? cleanedFileName.swiftlib_nilIfBlank
        }

        let firstAuthor = extracted.authors.first?.displayName.swiftlib_nilIfBlank
            ?? parsed.firstAuthor
            ?? MetadataResolution.extractLikelyAuthorName(from: cleanedFileName)

        let languageHint: MetadataLanguageHint
        if MetadataResolution.containsHanCharacters(title) || MetadataResolution.containsHanCharacters(cleanedFileName) {
            languageHint = .chinese
        } else if let title, !title.isEmpty {
            languageHint = .nonChinese
        } else {
            languageHint = .unknown
        }

        let seed = MetadataResolutionSeed(
            fileName: cleanedFileName,
            title: title,
            firstAuthor: firstAuthor,
            year: extracted.year,
            doi: extracted.doi,
            journal: extracted.journal,
            isbn: extracted.isbn,
            issn: extracted.issn,
            publisher: extracted.publisher,
            edition: extracted.edition,
            languageHint: languageHint,
            workKindHint: extracted.workKindHint,
            textSnippet: extracted.textSnippet,
            sourceURL: url.absoluteString
        )
        MetadataResolution.metadataLog.debug("""
            🌱 [seed] PDF 种子构建完成
              文件名: \(cleanedFileName, privacy: .public)
              标题: \(title ?? "nil", privacy: .public)
              作者: \(firstAuthor ?? "nil", privacy: .public)
              年份: \(extracted.year.map(String.init) ?? "nil", privacy: .public)
              语言: \(languageHint.rawValue, privacy: .public) shouldSearchCNKI=\(seed.shouldSearchCNKI)
              DOI: \(extracted.doi ?? "nil", privacy: .public)
            """)
        return seed
    }

    public static func fromReference(_ reference: Reference) -> MetadataResolutionSeed {
        let fileNameSource: String = {
            if let pdfPath = reference.pdfPath?.swiftlib_nilIfBlank {
                return URL(fileURLWithPath: pdfPath).deletingPathExtension().lastPathComponent
            }
            return reference.title
        }()

        let cleanedFileName = MetadataResolution.cleanPDFSeedFilename(fileNameSource)
        let parsed = MetadataResolution.parsePDFFileNameSeed(cleanedFileName)

        let title: String?
        if !MetadataResolution.isSuspiciousExtractedTitle(reference.title) {
            title = reference.title.swiftlib_nilIfBlank
        } else {
            title = parsed.title ?? cleanedFileName.swiftlib_nilIfBlank
        }

        let firstAuthor = reference.authors.first?.displayName.swiftlib_nilIfBlank
            ?? parsed.firstAuthor
            ?? MetadataResolution.extractLikelyAuthorName(from: cleanedFileName)

        let languageHint: MetadataLanguageHint
        if MetadataResolution.containsHanCharacters(title) || MetadataResolution.containsHanCharacters(cleanedFileName) {
            languageHint = .chinese
        } else if let title, !title.isEmpty {
            languageHint = .nonChinese
        } else {
            languageHint = .unknown
        }

        return MetadataResolutionSeed(
            fileName: cleanedFileName,
            title: title,
            firstAuthor: firstAuthor,
            year: reference.year,
            doi: reference.doi,
            journal: reference.journal,
            isbn: reference.isbn,
            issn: reference.issn,
            publisher: reference.publisher,
            edition: reference.edition,
            languageHint: languageHint,
            workKindHint: MetadataResolution.workKind(for: reference.referenceType),
            textSnippet: reference.abstract,
            sourceURL: reference.url
        )
    }
}
