import Foundation

public enum ReferenceCanonicalizationChangeKind: String, Codable, Sendable {
    case trimmedTextFields
    case normalizedDOI
    case removedStableJournalAccessedDate
    case normalizedAuthorNames
    case normalizedEditorNames
    case normalizedTranslatorNames
    case removedRepeatedAuthorSequence
    case repairedAuthorSwap
    case inferredJournalArticleType
    case normalizedLanguage
}

public struct ReferenceCanonicalizationChange: Codable, Equatable, Sendable {
    public let kind: ReferenceCanonicalizationChangeKind
    public let before: String?
    public let after: String?

    public init(kind: ReferenceCanonicalizationChangeKind, before: String?, after: String?) {
        self.kind = kind
        self.before = before
        self.after = after
    }
}

public struct ReferenceCanonicalizationResult: Sendable {
    public var reference: Reference
    public var changes: [ReferenceCanonicalizationChange]

    public init(reference: Reference, changes: [ReferenceCanonicalizationChange]) {
        self.reference = reference
        self.changes = changes
    }
}

/// Single Core entry point for normalizing imported, refreshed, repaired, and
/// citation-exported references before they enter a durable/rendered workflow.
public enum ReferenceIntakeCanonicalizer {
    public struct Options: Sendable {
        public var normalizeTextFields: Bool
        public var normalizeDOI: Bool
        public var normalizeAuthors: Bool
        public var normalizeEditors: Bool
        public var normalizeTranslators: Bool
        public var removeRepeatedAuthorSequences: Bool
        public var repairPinyinSwaps: Bool
        public var inferJournalArticleType: Bool
        public var removeStableJournalAccessedDate: Bool
        public var normalizeLanguage: Bool

        public init(
            normalizeTextFields: Bool = true,
            normalizeDOI: Bool = true,
            normalizeAuthors: Bool = true,
            normalizeEditors: Bool = true,
            normalizeTranslators: Bool = true,
            removeRepeatedAuthorSequences: Bool = true,
            repairPinyinSwaps: Bool = true,
            inferJournalArticleType: Bool = true,
            removeStableJournalAccessedDate: Bool = true,
            normalizeLanguage: Bool = true
        ) {
            self.normalizeTextFields = normalizeTextFields
            self.normalizeDOI = normalizeDOI
            self.normalizeAuthors = normalizeAuthors
            self.normalizeEditors = normalizeEditors
            self.normalizeTranslators = normalizeTranslators
            self.removeRepeatedAuthorSequences = removeRepeatedAuthorSequences
            self.repairPinyinSwaps = repairPinyinSwaps
            self.inferJournalArticleType = inferJournalArticleType
            self.removeStableJournalAccessedDate = removeStableJournalAccessedDate
            self.normalizeLanguage = normalizeLanguage
        }

        public static let storage = Options()
        public static let citationExport = Options()
        public static let repair = Options()
    }

    public static func canonicalize(
        _ reference: Reference,
        options: Options = .storage
    ) -> ReferenceCanonicalizationResult {
        var ref = reference
        var changes: [ReferenceCanonicalizationChange] = []

        if options.normalizeTextFields {
            let before = snapshotTextFields(ref)
            normalizeTextFields(&ref)
            let after = snapshotTextFields(ref)
            if before != after {
                changes.append(.init(kind: .trimmedTextFields, before: before, after: after))
            }
        }

        if options.normalizeDOI, let doi = ref.doi?.swiftlib_nilIfBlank {
            let normalized = DOIIdentifier(doi)?.cslString ?? doi
            if normalized != ref.doi {
                changes.append(.init(kind: .normalizedDOI, before: ref.doi, after: normalized))
                ref.doi = normalized
            }
        }

        if options.removeStableJournalAccessedDate,
           isStableJournalLike(ref),
           hasStablePublicationDetails(ref),
           ref.accessedDate?.swiftlib_nilIfBlank != nil {
            changes.append(.init(
                kind: .removedStableJournalAccessedDate,
                before: ref.accessedDate,
                after: nil
            ))
            ref.accessedDate = nil
        }

        if options.normalizeAuthors {
            let normalizedAuthors = AuthorName.normalizedForCitation(ref.authors)
            if normalizedAuthors != ref.authors {
                changes.append(.init(
                    kind: .normalizedAuthorNames,
                    before: authorDisplayString(ref.authors),
                    after: authorDisplayString(normalizedAuthors)
                ))
                ref.authors = normalizedAuthors
            }
        }

        if options.removeRepeatedAuthorSequences {
            let deduplicatedAuthors = AuthorName.deduplicatingRepeatedSequence(ref.authors)
            if deduplicatedAuthors != ref.authors {
                changes.append(.init(
                    kind: .removedRepeatedAuthorSequence,
                    before: authorDisplayString(ref.authors),
                    after: authorDisplayString(deduplicatedAuthors)
                ))
                ref.authors = deduplicatedAuthors
            }
        }

        if options.normalizeEditors {
            normalizeEncodedNames(
                &ref.editors,
                kind: .normalizedEditorNames,
                changes: &changes
            )
        }

        if options.normalizeTranslators {
            normalizeEncodedNames(
                &ref.translators,
                kind: .normalizedTranslatorNames,
                changes: &changes
            )
        }

        if options.repairPinyinSwaps {
            let repaired = ref.authors.map { author in
                AuthorName.pinyinSwapIssues(in: [author]).isEmpty ? author : author.pinyinSwapRepaired()
            }
            if repaired != ref.authors {
                changes.append(.init(
                    kind: .repairedAuthorSwap,
                    before: authorDisplayString(ref.authors),
                    after: authorDisplayString(repaired)
                ))
                ref.authors = repaired
            }
        }

        if options.inferJournalArticleType,
           ref.referenceType == .other,
           hasJournalEvidence(ref) {
            changes.append(.init(
                kind: .inferredJournalArticleType,
                before: ref.referenceType.rawValue,
                after: ReferenceType.journalArticle.rawValue
            ))
            ref.referenceType = .journalArticle
        }

        if options.normalizeLanguage, let language = ref.language?.swiftlib_nilIfBlank {
            let normalized = Reference.normalizeCSLLanguageTag(language) ?? language
            if normalized != ref.language {
                changes.append(.init(kind: .normalizedLanguage, before: ref.language, after: normalized))
                ref.language = normalized
            }
        }

        return ReferenceCanonicalizationResult(reference: ref, changes: changes)
    }

    public static func canonicalized(
        _ reference: Reference,
        options: Options = .storage
    ) -> Reference {
        canonicalize(reference, options: options).reference
    }

    static func hasJournalEvidence(_ reference: Reference) -> Bool {
        reference.journal?.swiftlib_nilIfBlank != nil ||
            reference.volume?.swiftlib_nilIfBlank != nil ||
            reference.issue?.swiftlib_nilIfBlank != nil ||
            reference.pages?.swiftlib_nilIfBlank != nil ||
            reference.issn?.swiftlib_nilIfBlank != nil
    }

    static func hasStablePublicationDetails(_ reference: Reference) -> Bool {
        reference.volume?.swiftlib_nilIfBlank != nil ||
            reference.issue?.swiftlib_nilIfBlank != nil ||
            reference.pages?.swiftlib_nilIfBlank != nil
    }

    static func shouldExportAccessedDateToCSL(_ reference: Reference) -> Bool {
        guard reference.accessedDate?.swiftlib_nilIfBlank != nil else { return false }
        if reference.referenceType == .webpage { return true }

        switch inferredCSLType(for: reference) {
        case ReferenceType.journalArticle.cslType,
             ReferenceType.magazineArticle.cslType,
             ReferenceType.newspaperArticle.cslType,
             ReferenceType.preprint.cslType:
            return !hasStablePublicationDetails(reference)
        default:
            return reference.url?.swiftlib_nilIfBlank != nil &&
                reference.doi?.swiftlib_nilIfBlank == nil
        }
    }

    static func inferredCSLType(for reference: Reference) -> String {
        guard reference.referenceType == .other else { return reference.referenceType.cslType }
        return hasJournalEvidence(reference) ? ReferenceType.journalArticle.cslType : reference.referenceType.cslType
    }

    private static func isStableJournalLike(_ reference: Reference) -> Bool {
        switch reference.referenceType {
        case .journalArticle, .magazineArticle, .newspaperArticle, .preprint, .other:
            return hasJournalEvidence(reference)
        default:
            return false
        }
    }

    private static func normalizeTextFields(_ reference: inout Reference) {
        reference.title = normalizedRequired(reference.title, fallback: "Untitled")
        reference.journal = normalizedOptional(reference.journal)
        reference.volume = normalizedOptional(reference.volume)
        reference.issue = normalizedOptional(reference.issue)
        reference.pages = normalizedOptional(reference.pages)
        reference.doi = normalizedOptional(reference.doi)
        reference.url = normalizedOptional(reference.url)
        reference.abstract = normalizedOptional(reference.abstract)
        reference.publisher = normalizedOptional(reference.publisher)
        reference.publisherPlace = normalizedOptional(reference.publisherPlace)
        reference.edition = normalizedOptional(reference.edition)
        reference.isbn = normalizedOptional(reference.isbn)
        reference.issn = normalizedOptional(reference.issn)
        reference.accessedDate = normalizedOptional(reference.accessedDate)
        reference.eventTitle = normalizedOptional(reference.eventTitle)
        reference.eventPlace = normalizedOptional(reference.eventPlace)
        reference.genre = normalizedOptional(reference.genre)
        reference.institution = normalizedOptional(reference.institution)
        reference.number = normalizedOptional(reference.number)
        reference.collectionTitle = normalizedOptional(reference.collectionTitle)
        reference.numberOfPages = normalizedOptional(reference.numberOfPages)
        reference.language = normalizedOptional(reference.language)
        reference.pmid = normalizedOptional(reference.pmid)
        reference.pmcid = normalizedOptional(reference.pmcid)
        reference.siteName = normalizedOptional(reference.siteName)
        reference.oaUrl = normalizedOptional(reference.oaUrl)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .swiftlib_nilIfBlank
    }

    private static func normalizedRequired(_ value: String, fallback: String) -> String {
        normalizedOptional(value) ?? fallback
    }

    private static func normalizeEncodedNames(
        _ encoded: inout String?,
        kind: ReferenceCanonicalizationChangeKind,
        changes: inout [ReferenceCanonicalizationChange]
    ) {
        guard let encodedValue = encoded?.swiftlib_nilIfBlank,
              let data = encodedValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AuthorName].self, from: data) else {
            encoded = encoded?.swiftlib_nilIfBlank
            return
        }

        let normalized = AuthorName.normalizedForCitation(decoded)
        let reencoded = Reference.encodeNames(normalized)
        if reencoded != encoded {
            changes.append(.init(
                kind: kind,
                before: authorDisplayString(decoded),
                after: authorDisplayString(normalized)
            ))
            encoded = reencoded
        }
    }

    private static func authorDisplayString(_ authors: [AuthorName]) -> String {
        authors.map { author in
            let family = author.family.trimmingCharacters(in: .whitespacesAndNewlines)
            let given = author.given.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !given.isEmpty else { return family }
            guard !family.isEmpty else { return given }
            return "\(family) \(given)"
        }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private static func snapshotTextFields(_ reference: Reference) -> String {
        [
            reference.title,
            reference.journal,
            reference.volume,
            reference.issue,
            reference.pages,
            reference.doi,
            reference.url,
            reference.publisher,
            reference.publisherPlace,
            reference.language,
        ]
        .map { $0 ?? "" }
        .joined(separator: "\u{1F}")
    }
}
