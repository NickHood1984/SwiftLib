import Foundation

// ---------------------------------------------------------------------------
// CSLItem
//
// A typed, Codable representation of a CSL-JSON bibliographic item as
// defined by the CSL specification and expected by citeproc-js.
//
// Using a typed struct instead of [String: Any] prevents silent field
// erasure (e.g. DOI stored as `doi:` URL prefix leaking into output) and
// makes field mapping auditable via Codable's CodingKeys.
//
// Reference: https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
// ---------------------------------------------------------------------------

// MARK: - Name

/// CSL name variable (author, editor, translator).
/// Supports both person names and institutional/literal names.
public struct CSLName: Codable, Equatable, Sendable {
    // Person name components
    /// Family / last name. Nil for literal institutional names.
    public var family: String?
    /// Given / first name.
    public var given: String?
    /// Lowercase particle that stays with the family name on sort
    /// (e.g. "van" in "van Gogh"). Value: "van", "de", "de la", …
    public var nonDroppingParticle: String?
    /// Lowercase particle that is dropped on sort
    /// (e.g. "de" in "Charles de Gaulle" when sorted as "Gaulle, de").
    public var droppingParticle: String?
    /// Suffix appended after the given name (e.g. "Jr.", "III").
    public var suffix: String?

    // Institutional / literal name (mutually exclusive with family+given)
    /// Full name as a single string — used for corporate/institutional authors
    /// that should not be split into given/family parts.
    /// Example: "World Health Organization", "OpenAI"
    public var literal: String?

    public enum CodingKeys: String, CodingKey {
        case family
        case given
        case nonDroppingParticle = "non-dropping-particle"
        case droppingParticle = "dropping-particle"
        case suffix
        case literal
    }

    public init(
        family: String? = nil,
        given: String? = nil,
        nonDroppingParticle: String? = nil,
        droppingParticle: String? = nil,
        suffix: String? = nil,
        literal: String? = nil
    ) {
        self.family = family
        self.given = given
        self.nonDroppingParticle = nonDroppingParticle
        self.droppingParticle = droppingParticle
        self.suffix = suffix
        self.literal = literal
    }

    /// Convenience: person name without particles.
    public static func person(given: String, family: String) -> CSLName {
        CSLName(family: family.swiftlib_nilIfBlank, given: given.swiftlib_nilIfBlank)
    }

    /// Convenience: institutional / literal name.
    public static func institution(_ name: String) -> CSLName {
        CSLName(literal: name)
    }
}

// MARK: - Date

/// CSL date variable.
/// Supports the `date-parts` array format and the `raw` string format.
public struct CSLDate: Codable, Equatable, Sendable {
    /// Nested date-parts: [[year, month?, day?], [year, month?, day?]?]
    /// The outer array holds one or two date points (start and end for ranges).
    public var dateParts: [[Int]]?
    /// Raw date string accepted by citeproc-js date parser (fallback).
    public var raw: String?
    /// Whether the date is approximate ("circa").
    public var circa: Bool?

    public enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
        case raw
        case circa
    }

    public init(dateParts: [[Int]]? = nil, raw: String? = nil, circa: Bool? = nil) {
        self.dateParts = dateParts
        self.raw = raw
        self.circa = circa
    }

    /// Convenience: year only.
    public static func year(_ year: Int) -> CSLDate {
        CSLDate(dateParts: [[year]])
    }

    /// Convenience: year + month.
    public static func yearMonth(_ year: Int, _ month: Int) -> CSLDate {
        CSLDate(dateParts: [[year, month]])
    }

    /// Convenience: full date.
    public static func full(_ year: Int, _ month: Int, _ day: Int) -> CSLDate {
        CSLDate(dateParts: [[year, month, day]])
    }

    /// Parse an ISO 8601 date string ("2024-03-15", "2024-03", "2024").
    public static func from(isoString: String) -> CSLDate? {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard !parts.isEmpty else { return CSLDate(raw: isoString) }
        return CSLDate(dateParts: [parts])
    }
}

// MARK: - Item

/// A CSL-JSON bibliographic item suitable for citeproc-js.
///
/// Fields are a subset of the CSL 1.0.1 specification variables, covering all
/// types produced by SwiftLib's Reference model. Unknown fields are silently
/// ignored by citeproc-js, so it is safe to add new keys in future versions.
///
/// CodingKeys deliberately use the hyphenated CSL variable names (e.g.
/// "container-title") so that `JSONEncoder` produces valid CSL-JSON directly.
public struct CSLItem: Codable, Sendable {

    // MARK: - Required

    /// Unique string identifier within this rendering context.
    /// Must be stable within a single render call.
    public var id: String

    /// CSL item type. See `ReferenceType.cslType` for the mapping.
    public var type: String

    // MARK: - Title variables

    public var title: String?
    /// Abbreviated title (for styles that use journal abbreviations in citations).
    public var titleShort: String?
    /// Container title: journal name, book title, conference proceedings name.
    public var containerTitle: String?
    /// Abbreviated container title (e.g. "Phys. Rev. Lett." for "Physical Review Letters").
    public var containerTitleShort: String?
    /// Collection / series title.
    public var collectionTitle: String?

    // MARK: - Name variables

    public var author: [CSLName]?
    public var editor: [CSLName]?
    public var translator: [CSLName]?

    // MARK: - Date variables

    public var issued: CSLDate?
    public var accessed: CSLDate?
    /// Original publication date (for reprints, translations).
    public var originalDate: CSLDate?

    // MARK: - Number variables

    public var volume: String?
    public var issue: String?
    public var page: String?
    public var edition: String?
    public var number: String?
    public var numberOfPages: String?

    // MARK: - Standard variables

    /// Publisher name.
    public var publisher: String?
    /// Publisher location / place.
    public var publisherPlace: String?
    /// Event title (for conference papers).
    public var eventTitle: String?
    /// Event location.
    public var eventPlace: String?
    /// Genre / document sub-type (e.g. "Doctoral dissertation", "Technical Report").
    public var genre: String?
    /// Archive or holding institution. Used by some thesis/report styles.
    public var archive: String?
    /// Abstract text.
    public var abstract: String?
    /// BCP-47 language tag (e.g. "en-US", "zh-CN").
    /// Controls title-case / sentence-case conversion in citeproc-js.
    public var language: String?

    // MARK: - Identifier variables

    /// DOI **without** the `https://doi.org/` prefix.
    /// Example: "10.1103/PhysRevLett.132.041601"
    public var DOI: String?
    public var URL: String?
    public var ISBN: String?
    public var ISSN: String?
    public var PMID: String?
    public var PMCID: String?

    // MARK: - Miscellaneous

    /// Free-text note field. Used to carry secondary identifiers (arXiv ID, PMID)
    /// when no dedicated CSL variable exists, following pandoc/Zotero conventions.
    public var note: String?

    public enum CodingKeys: String, CodingKey {
        case id, type
        case title
        case titleShort = "title-short"
        case containerTitle = "container-title"
        case containerTitleShort = "container-title-short"
        case collectionTitle = "collection-title"
        case author, editor, translator
        case issued, accessed
        case originalDate = "original-date"
        case volume, issue, page, edition, number
        case numberOfPages = "number-of-pages"
        case publisher
        case publisherPlace = "publisher-place"
        case eventTitle = "event-title"
        case eventPlace = "event-place"
        case genre, archive, abstract, language
        case DOI, URL, ISBN, ISSN, PMID, PMCID
        case note
    }

    public init(
        id: String,
        type: String,
        title: String? = nil,
        titleShort: String? = nil,
        containerTitle: String? = nil,
        containerTitleShort: String? = nil,
        collectionTitle: String? = nil,
        author: [CSLName]? = nil,
        editor: [CSLName]? = nil,
        translator: [CSLName]? = nil,
        issued: CSLDate? = nil,
        accessed: CSLDate? = nil,
        originalDate: CSLDate? = nil,
        volume: String? = nil,
        issue: String? = nil,
        page: String? = nil,
        edition: String? = nil,
        number: String? = nil,
        numberOfPages: String? = nil,
        publisher: String? = nil,
        publisherPlace: String? = nil,
        eventTitle: String? = nil,
        eventPlace: String? = nil,
        genre: String? = nil,
        archive: String? = nil,
        abstract: String? = nil,
        language: String? = nil,
        DOI: String? = nil,
        URL: String? = nil,
        ISBN: String? = nil,
        ISSN: String? = nil,
        PMID: String? = nil,
        PMCID: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.titleShort = titleShort
        self.containerTitle = containerTitle
        self.containerTitleShort = containerTitleShort
        self.collectionTitle = collectionTitle
        self.author = author
        self.editor = editor
        self.translator = translator
        self.issued = issued
        self.accessed = accessed
        self.originalDate = originalDate
        self.volume = volume
        self.issue = issue
        self.page = page
        self.edition = edition
        self.number = number
        self.numberOfPages = numberOfPages
        self.publisher = publisher
        self.publisherPlace = publisherPlace
        self.eventTitle = eventTitle
        self.eventPlace = eventPlace
        self.genre = genre
        self.archive = archive
        self.abstract = abstract
        self.language = language
        self.DOI = DOI
        self.URL = URL
        self.ISBN = ISBN
        self.ISSN = ISSN
        self.PMID = PMID
        self.PMCID = PMCID
        self.note = note
    }

    // MARK: - JSON serialisation for citeproc-js

    /// Serialise to a JSON string suitable for passing to citeproc-js via JSContext.
    /// Returns nil if encoding fails (should never happen in practice).
    public func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // compact
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - CSLItem + Validation

extension CSLItem {
    /// Field-level issues mirroring the `Reference.cslFieldIssues` check but
    /// operating on the already-mapped CSL representation.
    /// Used by CitationRenderer as a pre-flight guard.
    public var cslIssues: [CSLFieldIssue] {
        var issues: [CSLFieldIssue] = []

        if title?.swiftlib_nilIfBlank == nil {
            issues.append(.init(fieldKey: "title", displayName: "标题", severity: .critical))
        }
        if issued == nil {
            issues.append(.init(fieldKey: "issued", displayName: "出版年份", severity: .critical))
        }
        // Type-specific checks mirroring Reference+CSLJSON
        switch type {
        case "article-journal", "article-magazine", "article-newspaper":
            if author.isNilOrEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .critical))
            }
        case "book", "chapter":
            if author.isNilOrEmpty && editor.isNilOrEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者/编者", severity: .critical))
            }
            if publisher?.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "publisher", displayName: "出版社", severity: .critical))
            }
        case "thesis":
            if author.isNilOrEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .critical))
            }
            if publisher?.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "publisher", displayName: "授予单位", severity: .critical))
            }
        default:
            break
        }

        return issues.sorted { $0.severity == .critical && $1.severity != .critical }
    }

    public var cslCompleteness: CSLCompleteness {
        let issues = cslIssues
        if issues.isEmpty { return .complete }
        if issues.contains(where: { $0.severity == .critical }) { return .critical }
        return .incomplete
    }
}

// MARK: - Helpers

// Note: swiftlib_nilIfBlank is already defined in Utilities/String+NilIfBlank.swift;
// we use it above for CSLItem+Validation. No duplicate needed here.

private extension Optional where Wrapped == [CSLName] {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let arr): return arr.isEmpty
        }
    }
}
