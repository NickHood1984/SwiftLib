import Foundation
import GRDB

public enum ReferenceType: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case journalArticle = "Journal Article"
    case magazineArticle = "Magazine Article"
    case newspaperArticle = "Newspaper Article"
    case preprint = "Preprint"
    case book = "Book"
    case bookSection = "Book Section"
    case conferencePaper = "Conference Paper"
    case thesis = "Thesis"
    case dataset = "Dataset"
    case software = "Software"
    case standard = "Standard"
    case manuscript = "Manuscript"
    case interview = "Interview"
    case presentation = "Presentation"
    case blogPost = "Blog Post"
    case forumPost = "Forum Post"
    case legalCase = "Legal Case"
    case legislation = "Legislation"
    case webpage = "Web Page"
    case report = "Report"
    case patent = "Patent"
    case other = "Other"

    public var icon: String {
        switch self {
        case .journalArticle: return "doc.text"
        case .magazineArticle: return "doc.text.image"
        case .newspaperArticle: return "newspaper"
        case .preprint: return "doc.text.magnifyingglass"
        case .book: return "book.closed"
        case .bookSection: return "book"
        case .conferencePaper: return "person.3"
        case .thesis: return "graduationcap"
        case .dataset: return "tablecells"
        case .software: return "app.connected.to.app.below.fill"
        case .standard: return "checklist"
        case .manuscript: return "doc.plaintext"
        case .interview: return "person.text.rectangle"
        case .presentation: return "rectangle.on.rectangle"
        case .blogPost: return "text.bubble"
        case .forumPost: return "bubble.left.and.bubble.right"
        case .legalCase: return "building.columns"
        case .legislation: return "scroll"
        case .webpage: return "globe"
        case .report: return "doc.richtext"
        case .patent: return "seal"
        case .other: return "doc"
        }
    }
}

public struct AuthorName: Codable, Hashable, Sendable {
    public var given: String
    public var family: String

    public init(given: String, family: String) {
        self.given = given
        self.family = family
    }

    /// "Given Family" display form
    public var displayName: String {
        given.isEmpty ? family : "\(given) \(family)"
    }

    /// "Family, G." short form
    public var shortName: String {
        let initials = given.components(separatedBy: " ")
            .map { String($0.prefix(1)) + "." }
            .joined(separator: " ")
        return initials.isEmpty ? family : "\(family), \(initials)"
    }

    /// Parse a free-text name like "John Smith" → AuthorName(given: "John", family: "Smith")
    /// Also handles "Smith, John" (comma-separated family-first)
    public static func parse(_ text: String) -> AuthorName {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let commaIdx = trimmed.firstIndex(of: ",") {
            let family = String(trimmed[..<commaIdx]).trimmingCharacters(in: .whitespaces)
            let given = String(trimmed[trimmed.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            return AuthorName(given: given, family: family)
        }
        let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return AuthorName(given: parts.dropLast().joined(separator: " "), family: parts.last!)
        }
        return AuthorName(given: "", family: trimmed)
    }

    /// Parse a plain-text authors string into structured array.
    /// Handles separators: "and", ";", and smart comma handling.
    public static func parseList(_ text: String) -> [AuthorName] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // First split by ";" or " and "
        let segments: [String]
        if trimmed.contains(";") {
            segments = trimmed.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        } else if trimmed.lowercased().contains(" and ") {
            segments = trimmed.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            // Comma-separated: could be "Smith, John, Doe, Jane" (family-first pairs)
            // or "John Smith, Jane Doe" (full names). Detect by checking if first segment
            // looks like a single word (family name).
            let parts = trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                let looksLikeFamilyGivenPairs =
                    (parts.count == 2 && !parts[0].contains(" ")) ||
                    (parts.count.isMultiple(of: 2) &&
                        stride(from: 0, to: parts.count, by: 2).allSatisfy { !parts[$0].contains(" ") })

                if looksLikeFamilyGivenPairs {
                    // Likely "Family, Given" pairs — group by twos
                    var result: [AuthorName] = []
                    var i = 0
                    while i < parts.count {
                        if i + 1 < parts.count {
                            result.append(AuthorName(given: parts[i + 1], family: parts[i]))
                            i += 2
                        } else {
                            result.append(AuthorName(given: "", family: parts[i]))
                            i += 1
                        }
                    }
                    return result.filter { !$0.family.isEmpty }
                }

                // Otherwise each comma-separated part is a full name
                segments = parts
            } else {
                segments = parts
            }
        }

        return segments
            .filter { !$0.isEmpty }
            .map { parse($0) }
            .filter { !$0.family.isEmpty }
    }
}

extension Array where Element == AuthorName {
    /// Display string for UI: "Given Family, Given Family"
    public var displayString: String {
        if isEmpty { return "" }
        return map { $0.displayName }.joined(separator: ", ")
    }

    /// Lowercased, whitespace-normalized author string for search/dedup.
    public var normalizedSearchString: String {
        map { $0.displayName.lowercased() }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Reference: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64?
    public var title: String
    public var authors: [AuthorName]
    public var year: Int?
    public var journal: String?
    public var volume: String?
    public var issue: String?
    public var pages: String?
    public var doi: String?
    public var url: String?
    public var abstract: String?
    public var dateAdded: Date
    public var dateModified: Date
    public var pdfPath: String?
    public var notes: String?
    public var webContent: String?
    public var siteName: String?
    public var favicon: String?
    public var referenceType: ReferenceType
    public var metadataSource: MetadataSource?
    public var verificationStatus: VerificationStatus
    public var acceptedByRuleID: String?
    public var recordKey: String?
    public var verificationSourceURL: String?
    public var evidenceBundleHash: String?
    public var verifiedAt: Date?
    public var reviewedBy: String?
    public var collectionId: Int64?

    // MARK: - Extended metadata (P0)
    public var publisher: String?
    public var publisherPlace: String?
    public var edition: String?
    /// JSON-encoded array of AuthorName: [{"given":"John","family":"Smith"}]
    public var editors: String?
    public var isbn: String?
    public var issn: String?
    /// ISO 8601 date string for "accessed" date
    public var accessedDate: String?
    public var issuedMonth: Int?
    public var issuedDay: Int?

    // MARK: - Extended metadata (P1)
    /// JSON-encoded array of AuthorName for translators
    public var translators: String?
    public var eventTitle: String?
    public var eventPlace: String?
    /// e.g. "Doctoral dissertation", "Master's thesis"
    public var genre: String?
    public var institution: String?
    /// Report/patent number
    public var number: String?
    public var collectionTitle: String?
    public var numberOfPages: String?

    // MARK: - Extended metadata (P2)
    /// ISO 639-1 language code
    public var language: String?
    public var pmid: String?
    public var pmcid: String?

    public init(
        id: Int64? = nil,
        title: String,
        authors: [AuthorName] = [],
        year: Int? = nil,
        journal: String? = nil,
        volume: String? = nil,
        issue: String? = nil,
        pages: String? = nil,
        doi: String? = nil,
        url: String? = nil,
        abstract: String? = nil,
        dateAdded: Date = Date(),
        dateModified: Date = Date(),
        pdfPath: String? = nil,
        notes: String? = nil,
        webContent: String? = nil,
        siteName: String? = nil,
        favicon: String? = nil,
        referenceType: ReferenceType = .journalArticle,
        metadataSource: MetadataSource? = nil,
        verificationStatus: VerificationStatus = .legacy,
        acceptedByRuleID: String? = nil,
        recordKey: String? = nil,
        verificationSourceURL: String? = nil,
        evidenceBundleHash: String? = nil,
        verifiedAt: Date? = nil,
        reviewedBy: String? = nil,
        collectionId: Int64? = nil,
        // Extended metadata (P0)
        publisher: String? = nil,
        publisherPlace: String? = nil,
        edition: String? = nil,
        editors: String? = nil,
        isbn: String? = nil,
        issn: String? = nil,
        accessedDate: String? = nil,
        issuedMonth: Int? = nil,
        issuedDay: Int? = nil,
        // Extended metadata (P1)
        translators: String? = nil,
        eventTitle: String? = nil,
        eventPlace: String? = nil,
        genre: String? = nil,
        institution: String? = nil,
        number: String? = nil,
        collectionTitle: String? = nil,
        numberOfPages: String? = nil,
        // Extended metadata (P2)
        language: String? = nil,
        pmid: String? = nil,
        pmcid: String? = nil
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.year = year
        self.journal = journal
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.doi = doi
        self.url = url
        self.abstract = abstract
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.pdfPath = pdfPath
        self.notes = notes
        self.webContent = webContent
        self.siteName = siteName
        self.favicon = favicon
        self.referenceType = referenceType
        self.metadataSource = metadataSource
        self.verificationStatus = verificationStatus
        self.acceptedByRuleID = acceptedByRuleID
        self.recordKey = recordKey
        self.verificationSourceURL = verificationSourceURL
        self.evidenceBundleHash = evidenceBundleHash
        self.verifiedAt = verifiedAt
        self.reviewedBy = reviewedBy
        self.collectionId = collectionId
        // Extended metadata (P0)
        self.publisher = publisher
        self.publisherPlace = publisherPlace
        self.edition = edition
        self.editors = editors
        self.isbn = isbn
        self.issn = issn
        self.accessedDate = accessedDate
        self.issuedMonth = issuedMonth
        self.issuedDay = issuedDay
        // Extended metadata (P1)
        self.translators = translators
        self.eventTitle = eventTitle
        self.eventPlace = eventPlace
        self.genre = genre
        self.institution = institution
        self.number = number
        self.collectionTitle = collectionTitle
        self.numberOfPages = numberOfPages
        // Extended metadata (P2)
        self.language = language
        self.pmid = pmid
        self.pmcid = pmcid
    }

    // MARK: - Parsed name helpers

    /// Decode editors JSON string into [AuthorName]
    public var parsedEditors: [AuthorName] {
        guard let json = editors, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AuthorName].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Decode translators JSON string into [AuthorName]
    public var parsedTranslators: [AuthorName] {
        guard let json = translators, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AuthorName].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Encode [AuthorName] to JSON string for storage
    public static func encodeNames(_ names: [AuthorName]) -> String? {
        guard !names.isEmpty,
              let data = try? JSONEncoder().encode(names),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

extension Reference {
    public static func == (lhs: Reference, rhs: Reference) -> Bool {
        switch (lhs.id, rhs.id) {
        case let (.some(leftID), .some(rightID)):
            return leftID == rightID
        case (.none, .none):
            guard lhs.title == rhs.title,
                  lhs.authors == rhs.authors,
                  lhs.year == rhs.year,
                  lhs.journal == rhs.journal,
                  lhs.volume == rhs.volume,
                  lhs.issue == rhs.issue,
                  lhs.pages == rhs.pages,
                  lhs.doi == rhs.doi,
                  lhs.url == rhs.url,
                  lhs.abstract == rhs.abstract,
                  lhs.dateAdded == rhs.dateAdded,
                  lhs.dateModified == rhs.dateModified,
                  lhs.pdfPath == rhs.pdfPath,
                  lhs.notes == rhs.notes,
                  lhs.webContent == rhs.webContent,
                  lhs.siteName == rhs.siteName,
                  lhs.favicon == rhs.favicon,
                  lhs.referenceType == rhs.referenceType,
                  lhs.metadataSource == rhs.metadataSource,
                  lhs.verificationStatus == rhs.verificationStatus,
                  lhs.acceptedByRuleID == rhs.acceptedByRuleID,
                  lhs.recordKey == rhs.recordKey,
                  lhs.verificationSourceURL == rhs.verificationSourceURL,
                  lhs.evidenceBundleHash == rhs.evidenceBundleHash,
                  lhs.verifiedAt == rhs.verifiedAt,
                  lhs.reviewedBy == rhs.reviewedBy,
                  lhs.collectionId == rhs.collectionId else {
                return false
            }

            guard lhs.publisher == rhs.publisher,
                  lhs.publisherPlace == rhs.publisherPlace,
                  lhs.edition == rhs.edition,
                  lhs.editors == rhs.editors,
                  lhs.isbn == rhs.isbn,
                  lhs.issn == rhs.issn,
                  lhs.accessedDate == rhs.accessedDate,
                  lhs.issuedMonth == rhs.issuedMonth,
                  lhs.issuedDay == rhs.issuedDay,
                  lhs.translators == rhs.translators,
                  lhs.eventTitle == rhs.eventTitle,
                  lhs.eventPlace == rhs.eventPlace,
                  lhs.genre == rhs.genre,
                  lhs.institution == rhs.institution,
                  lhs.number == rhs.number,
                  lhs.collectionTitle == rhs.collectionTitle,
                  lhs.numberOfPages == rhs.numberOfPages,
                  lhs.language == rhs.language,
                  lhs.pmid == rhs.pmid,
                  lhs.pmcid == rhs.pmcid else {
                return false
            }

            return true
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        if let id {
            hasher.combine(id)
            return
        }

        hasher.combine(title)
        hasher.combine(authors)
        hasher.combine(year)
        hasher.combine(journal)
        hasher.combine(volume)
        hasher.combine(issue)
        hasher.combine(pages)
        hasher.combine(doi)
        hasher.combine(url)
        hasher.combine(abstract)
        hasher.combine(dateAdded)
        hasher.combine(dateModified)
        hasher.combine(pdfPath)
        hasher.combine(notes)
        hasher.combine(webContent)
        hasher.combine(siteName)
        hasher.combine(favicon)
        hasher.combine(referenceType)
        hasher.combine(metadataSource)
        hasher.combine(verificationStatus)
        hasher.combine(acceptedByRuleID)
        hasher.combine(recordKey)
        hasher.combine(verificationSourceURL)
        hasher.combine(evidenceBundleHash)
        hasher.combine(verifiedAt)
        hasher.combine(reviewedBy)
        hasher.combine(collectionId)
        hasher.combine(publisher)
        hasher.combine(publisherPlace)
        hasher.combine(edition)
        hasher.combine(editors)
        hasher.combine(isbn)
        hasher.combine(issn)
        hasher.combine(accessedDate)
        hasher.combine(issuedMonth)
        hasher.combine(issuedDay)
        hasher.combine(translators)
        hasher.combine(eventTitle)
        hasher.combine(eventPlace)
        hasher.combine(genre)
        hasher.combine(institution)
        hasher.combine(number)
        hasher.combine(collectionTitle)
        hasher.combine(numberOfPages)
        hasher.combine(language)
        hasher.combine(pmid)
        hasher.combine(pmcid)
    }
}

extension Reference {
    public static let lightColumns: [any SQLSelectable] = [
        Columns.id,
        Columns.title,
        Columns.authors,
        Columns.year,
        Columns.journal,
        Columns.volume,
        Columns.issue,
        Columns.pages,
        Columns.doi,
        Columns.url,
        Columns.abstract,
        Columns.dateAdded,
        Columns.dateModified,
        Columns.pdfPath,
        Columns.notes,
        Columns.siteName,
        Columns.favicon,
        Columns.referenceType,
        Columns.metadataSource,
        Columns.verificationStatus,
        Columns.acceptedByRuleID,
        Columns.recordKey,
        Columns.verificationSourceURL,
        Columns.evidenceBundleHash,
        Columns.verifiedAt,
        Columns.reviewedBy,
        Columns.collectionId,
        Columns.publisher,
        Columns.publisherPlace,
        Columns.edition,
        Columns.editors,
        Columns.isbn,
        Columns.issn,
        Columns.accessedDate,
        Columns.issuedMonth,
        Columns.issuedDay,
        Columns.translators,
        Columns.eventTitle,
        Columns.eventPlace,
        Columns.genre,
        Columns.institution,
        Columns.number,
        Columns.collectionTitle,
        Columns.numberOfPages,
        Columns.language,
        Columns.pmid,
        Columns.pmcid,
    ]

    public var authorsNormalized: String {
        authors.normalizedSearchString
    }

    public enum WebContentFormat: String, Codable, Hashable {
        case markdown
        case html
    }

    public struct DecodedWebContent: Hashable {
        public var body: String
        public var format: WebContentFormat

        public init(body: String, format: WebContentFormat) {
            self.body = body
            self.format = format
        }
    }

    private static let htmlWebContentPrefix = "<!-- swiftlib:web-content:html -->"

    public static func encodeWebContent(_ body: String?, format: WebContentFormat) -> String? {
        guard let raw = body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        switch format {
        case .markdown:
            return raw
        case .html:
            return htmlWebContentPrefix + "\n" + raw
        }
    }

    public static func decodeWebContent(_ raw: String?) -> DecodedWebContent? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix(htmlWebContentPrefix) {
            let body = trimmed
                .dropFirst(htmlWebContentPrefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return DecodedWebContent(body: body, format: .html)
        }

        if looksLikeHTMLWebContent(trimmed) {
            return DecodedWebContent(body: trimmed, format: .html)
        }

        return DecodedWebContent(body: trimmed, format: .markdown)
    }

    public var decodedWebContent: DecodedWebContent? {
        Self.decodeWebContent(webContent)
    }

    public var canEnterFeedback: Bool {
        verificationStatus == .verifiedAuto || verificationStatus == .verifiedManual
    }

    public var canAutoFeedback: Bool {
        verificationStatus == .verifiedAuto
            && acceptedByRuleID?.swiftlib_nilIfBlank != nil
            && evidenceBundleHash?.swiftlib_nilIfBlank != nil
    }

    private static func looksLikeHTMLWebContent(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") {
            return true
        }
        let markers = [
            "<article", "<section", "<div", "<p", "<figure", "<img", "<blockquote",
            "<details", "<iframe", "<ul", "<ol", "<table", "<h1", "<h2", "<h3"
        ]
        let markerHits = markers.reduce(into: 0) { partialResult, marker in
            if lower.contains(marker) {
                partialResult += 1
            }
        }
        return markerHits >= 2 || (lower.hasPrefix("<") && lower.contains("</"))
    }

    /// 在线阅读可用的原文链接：优先 `url`，否则尝试 `siteName` / `journal`（剪藏模板常把链接写在 `source` 并落入 siteName）。
    public func resolvedWebReaderURLString() -> String? {
        for raw in [url, siteName, journal] {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
            guard let u = URL(string: s), let scheme = u.scheme?.lowercased() else { continue }
            guard scheme == "http" || scheme == "https" else { continue }
            return s
        }
        return nil
    }

    /// 是否可打开内置网页阅读器：有剪藏正文，或有可用的 http(s) 原文链接（走「剪藏正文」或「在线阅读」）。
    public var canOpenWebReader: Bool {
        guard referenceType == .webpage else { return false }
        let clip = webContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !clip.isEmpty { return true }
        let urlStr = resolvedWebReaderURLString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !urlStr.isEmpty && URL(string: urlStr) != nil
    }

    /// 与 `isLikelyYouTubeWatchURL` 一致，供仅有 URL 字符串的场景使用（如从网页导入、Clipper 抓取调度）。
    public static func isLikelyYouTubeWatchURL(urlString: String) -> Bool {
        var r = Reference(title: "x", referenceType: .webpage)
        r.url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isLikelyYouTubeWatchURL
    }

    /// YouTube 观看类 URL。应用内 WKWebView 无浏览器扩展的 Referer/DNR 修复，嵌入播放器常被拦；需延迟抽取或专用降级页。
    public var isLikelyYouTubeWatchURL: Bool {
        guard let s = resolvedWebReaderURLString(),
              let u = URL(string: s),
              let host = u.host?.lowercased() else { return false }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") { return true }
        guard host.contains("youtube.com") else { return false }
        let path = u.path.lowercased()
        if path.hasPrefix("/watch") { return true }
        if path.hasPrefix("/shorts/") { return true }
        if path.hasPrefix("/live/") { return true }
        if path.hasPrefix("/embed/") { return true }
        return u.query?.contains("v=") == true
    }

    /// 从当前条目的可解析原文链接中提取 YouTube 视频 ID（用于 timedtext / 字幕拉取）。
    public var youTubeVideoId: String? {
        guard let s = resolvedWebReaderURLString() else { return nil }
        return Self.parseYouTubeVideoId(from: s)
    }

    public static func parseYouTubeVideoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let id = raw.split(separator: "?").first.map(String.init) ?? raw
            return id.isEmpty ? nil : id
        }
        guard host.contains("youtube.com") else { return nil }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let path = url.path.lowercased()
        for prefix in ["/shorts/", "/live/", "/embed/"] {
            if path.hasPrefix(prefix) {
                let rest = String(path.dropFirst(prefix.count)).split(separator: "/").first.map(String.init) ?? ""
                return rest.isEmpty ? nil : rest
            }
        }
        return nil
    }
}

// MARK: - GRDB Record
extension Reference: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "reference"

    public static let collection = belongsTo(Collection.self)
    public var collection: QueryInterfaceRequest<Collection> {
        request(for: Reference.collection)
    }

    public static let referenceTagPivot = hasMany(ReferenceTag.self)
    public static let tags = hasMany(Tag.self, through: referenceTagPivot, using: ReferenceTag.tag)
    public var tags: QueryInterfaceRequest<Tag> {
        request(for: Reference.tags)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Custom row decoding: handles both legacy plain-text and JSON-array authors
    public init(row: Row) {
        id = row["id"]
        title = row["title"]

        // Authors: try JSON array first, fall back to legacy plain text
        if let jsonStr = row["authors"] as String?,
           let data = jsonStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AuthorName].self, from: data) {
            authors = decoded
        } else if let plain = row["authors"] as String? {
            authors = AuthorName.parseList(plain)
        } else {
            authors = []
        }

        year = row["year"]
        journal = row["journal"]
        volume = row["volume"]
        issue = row["issue"]
        pages = row["pages"]
        doi = row["doi"]
        url = row["url"]
        abstract = row["abstract"]
        dateAdded = row["dateAdded"]
        dateModified = row["dateModified"]
        pdfPath = row["pdfPath"]
        notes = row["notes"]
        webContent = row["webContent"]
        siteName = row["siteName"]
        favicon = row["favicon"]
        referenceType = row["referenceType"]
        metadataSource = row["metadataSource"]
        verificationStatus = row["verificationStatus"] ?? .legacy
        acceptedByRuleID = row["acceptedByRuleID"]
        recordKey = row["recordKey"]
        verificationSourceURL = row["verificationSourceURL"]
        evidenceBundleHash = row["evidenceBundleHash"]
        verifiedAt = row["verifiedAt"]
        reviewedBy = row["reviewedBy"]
        collectionId = row["collectionId"]

        // Extended metadata (P0)
        publisher = row["publisher"]
        publisherPlace = row["publisherPlace"]
        edition = row["edition"]
        editors = row["editors"]
        isbn = row["isbn"]
        issn = row["issn"]
        accessedDate = row["accessedDate"]
        issuedMonth = row["issuedMonth"]
        issuedDay = row["issuedDay"]

        // Extended metadata (P1)
        translators = row["translators"]
        eventTitle = row["eventTitle"]
        eventPlace = row["eventPlace"]
        genre = row["genre"]
        institution = row["institution"]
        number = row["number"]
        collectionTitle = row["collectionTitle"]
        numberOfPages = row["numberOfPages"]

        // Extended metadata (P2)
        language = row["language"]
        pmid = row["pmid"]
        pmcid = row["pmcid"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        // Encode authors as JSON string
        if let data = try? JSONEncoder().encode(authors),
           let json = String(data: data, encoding: .utf8) {
            container["authors"] = json
        } else {
            container["authors"] = ""
        }
        container["authorsNormalized"] = authorsNormalized
        container["year"] = year
        container["journal"] = journal
        container["volume"] = volume
        container["issue"] = issue
        container["pages"] = pages
        container["doi"] = doi
        container["url"] = url
        container["abstract"] = abstract
        container["dateAdded"] = dateAdded
        container["dateModified"] = dateModified
        container["pdfPath"] = pdfPath
        container["notes"] = notes
        container["webContent"] = webContent
        container["siteName"] = siteName
        container["favicon"] = favicon
        container["referenceType"] = referenceType
        container["metadataSource"] = metadataSource
        container["verificationStatus"] = verificationStatus
        container["acceptedByRuleID"] = acceptedByRuleID
        container["recordKey"] = recordKey
        container["verificationSourceURL"] = verificationSourceURL
        container["evidenceBundleHash"] = evidenceBundleHash
        container["verifiedAt"] = verifiedAt
        container["reviewedBy"] = reviewedBy
        container["collectionId"] = collectionId

        // Extended metadata (P0)
        container["publisher"] = publisher
        container["publisherPlace"] = publisherPlace
        container["edition"] = edition
        container["editors"] = editors
        container["isbn"] = isbn
        container["issn"] = issn
        container["accessedDate"] = accessedDate
        container["issuedMonth"] = issuedMonth
        container["issuedDay"] = issuedDay

        // Extended metadata (P1)
        container["translators"] = translators
        container["eventTitle"] = eventTitle
        container["eventPlace"] = eventPlace
        container["genre"] = genre
        container["institution"] = institution
        container["number"] = number
        container["collectionTitle"] = collectionTitle
        container["numberOfPages"] = numberOfPages

        // Extended metadata (P2)
        container["language"] = language
        container["pmid"] = pmid
        container["pmcid"] = pmcid

        // Normalized dedup columns (v11) — written on every save so the
        // persisted values stay in sync with the source fields.
        container["doiNormalized"] = Self.normalizeForDedupDOI(doi)
        container["isbnNormalized"] = Self.normalizeForDedupISBN(isbn)
        container["issnNormalized"] = Self.normalizeForDedupISSN(issn)
        container["pmcidNormalized"] = Self.normalizeForDedupPMCID(pmcid)
    }

    // MARK: - Static normalization helpers (shared with migration)

    public static func normalizeForDedupDOI(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    public static func normalizeForDedupISBN(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        guard normalized.count == 10 || normalized.count == 13 else { return nil }
        return normalized
    }

    public static func normalizeForDedupISSN(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        guard normalized.count == 8 else { return nil }
        return normalized
    }

    public static func normalizeForDedupPMCID(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.uppercased()
    }

    public enum Columns: String, ColumnExpression {
        case id, title, authors, authorsNormalized, year, journal, volume, issue, pages
        case doi, url, abstract, dateAdded, dateModified
        case pdfPath, notes, webContent, siteName, favicon, referenceType, metadataSource
        case verificationStatus, acceptedByRuleID, recordKey, verificationSourceURL, evidenceBundleHash, verifiedAt, reviewedBy
        case collectionId
        // Extended metadata
        case publisher, publisherPlace, edition, editors, isbn, issn
        case accessedDate, issuedMonth, issuedDay
        case translators, eventTitle, eventPlace, genre, institution, number
        case collectionTitle, numberOfPages
        case language, pmid, pmcid
        // Normalized dedup columns (v11)
        case doiNormalized, isbnNormalized, issnNormalized, pmcidNormalized
    }
}

// MARK: - ReferenceListRow (lightweight model for list display)

/// A lightweight projection of `Reference` containing only the columns needed
/// for rendering list rows. This avoids loading `abstract`, `notes`, `webContent`,
/// `editors`, `translators`, and other heavy fields into memory.
public struct ReferenceListRow: Identifiable, Hashable, Sendable, FetchableRecord {
    public var id: Int64?
    public var title: String
    public var authors: [AuthorName]
    public var year: Int?
    public var journal: String?
    public var pdfPath: String?
    public var referenceType: ReferenceType
    public var verificationStatus: VerificationStatus
    public var dateAdded: Date
    public var dateModified: Date
    public var collectionId: Int64?

    /// The subset of columns required for list rendering.
    public static let listColumns: [any SQLSelectable] = [
        Reference.Columns.id,
        Reference.Columns.title,
        Reference.Columns.authors,
        Reference.Columns.year,
        Reference.Columns.journal,
        Reference.Columns.pdfPath,
        Reference.Columns.referenceType,
        Reference.Columns.verificationStatus,
        Reference.Columns.dateAdded,
        Reference.Columns.dateModified,
        Reference.Columns.collectionId,
    ]

    public init(row: Row) {
        id = row["id"]
        title = row["title"]

        if let jsonStr = row["authors"] as String?,
           let data = jsonStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AuthorName].self, from: data) {
            authors = decoded
        } else if let plain = row["authors"] as String? {
            authors = AuthorName.parseList(plain)
        } else {
            authors = []
        }

        year = row["year"]
        journal = row["journal"]
        pdfPath = row["pdfPath"]
        referenceType = row["referenceType"]
        verificationStatus = row["verificationStatus"] ?? .legacy
        dateAdded = row["dateAdded"]
        dateModified = row["dateModified"]
        collectionId = row["collectionId"]
    }
}
