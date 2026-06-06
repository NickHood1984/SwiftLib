import Foundation

/// Authoritative conversion from SwiftLib's `Reference` model to citeproc-ready
/// CSL data. App previews, Word/WPS, DOCX refresh, and CLI should all use this
/// service so that field normalization and CSL mapping cannot drift.
public enum CSLExportService {
    public static func cslItem(for reference: Reference) -> CSLItem {
        let ref = ReferenceIntakeCanonicalizer.canonicalized(reference, options: .citationExport)
        guard let nid = ref.id else {
            return CSLItem(id: "unsaved", type: ReferenceIntakeCanonicalizer.inferredCSLType(for: ref))
        }

        let cslAuthors = cslNames(from: ref.authors)
        let cslEditors = cslNames(from: ref.parsedEditors)
        let cslTranslators = cslNames(from: ref.parsedTranslators)

        let issuedDate: CSLDate? = {
            guard let y = ref.year else { return nil }
            if let m = ref.issuedMonth, (1...12).contains(m) {
                if let d = ref.issuedDay, (1...31).contains(d) { return .full(y, m, d) }
                return .yearMonth(y, m)
            }
            return .year(y)
        }()

        let accessedDate = ReferenceIntakeCanonicalizer.shouldExportAccessedDateToCSL(ref)
            ? ref.accessedDate.flatMap { CSLDate.from(isoString: $0) }
            : nil

        let cleanDOI = ref.doi.flatMap { DOIIdentifier($0)?.cslString } ?? ref.doi?.swiftlib_nilIfBlank
        let cslURL = ref.referenceType == .webpage ? ref.url?.swiftlib_nilIfBlank : nil
        let language = ref.language?.swiftlib_nilIfBlank
            .flatMap { Reference.normalizeCSLLanguageTag($0) ?? $0 }
            ?? Reference.autoDetectCSLLanguage(title: ref.title)

        var noteParts: [String] = []
        if let arXivURL = ref.url, arXivURL.lowercased().contains("arxiv.org"),
           let arxivID = ArxivIDIdentifier(arXivURL) {
            noteParts.append(arxivID.cslNote)
        }
        if let pm = ref.pmid?.swiftlib_nilIfBlank, cleanDOI == nil {
            noteParts.append("PMID:\(pm)")
        }
        if let pmc = ref.pmcid?.swiftlib_nilIfBlank {
            noteParts.append("PMCID:\(pmc)")
        }

        let publisher = ref.publisher?.swiftlib_nilIfBlank ?? (
            ref.referenceType == .thesis ? ref.institution?.swiftlib_nilIfBlank : nil
        )
        let containerTitle = ref.journal?.swiftlib_nilIfBlank ?? (
            ref.referenceType == .webpage ? ref.siteName?.swiftlib_nilIfBlank : nil
        )

        return CSLItem(
            id: String(nid),
            type: ReferenceIntakeCanonicalizer.inferredCSLType(for: ref),
            title: ref.title.swiftlib_nilIfBlank,
            containerTitle: containerTitle,
            collectionTitle: ref.collectionTitle?.swiftlib_nilIfBlank,
            author: cslAuthors,
            editor: cslEditors,
            translator: cslTranslators,
            issued: issuedDate,
            accessed: accessedDate,
            volume: ref.volume?.swiftlib_nilIfBlank,
            issue: ref.issue?.swiftlib_nilIfBlank,
            page: ref.pages?.swiftlib_nilIfBlank,
            edition: ref.edition?.swiftlib_nilIfBlank,
            number: ref.number?.swiftlib_nilIfBlank,
            numberOfPages: ref.numberOfPages?.swiftlib_nilIfBlank,
            publisher: publisher,
            publisherPlace: ref.publisherPlace?.swiftlib_nilIfBlank,
            eventTitle: ref.eventTitle?.swiftlib_nilIfBlank,
            eventPlace: ref.eventPlace?.swiftlib_nilIfBlank,
            genre: ref.genre?.swiftlib_nilIfBlank,
            archive: ref.referenceType == .thesis ? ref.institution?.swiftlib_nilIfBlank : nil,
            abstract: ref.abstract?.swiftlib_nilIfBlank,
            language: language,
            DOI: cleanDOI,
            URL: cslURL,
            ISBN: ref.isbn?.swiftlib_nilIfBlank,
            ISSN: ref.issn?.swiftlib_nilIfBlank,
            PMID: ref.pmid?.swiftlib_nilIfBlank,
            PMCID: ref.pmcid?.swiftlib_nilIfBlank,
            note: noteParts.isEmpty ? nil : noteParts.joined(separator: "; ")
        )
    }

    public static func cslJSONObject(for reference: Reference) -> [String: Any] {
        jsonObject(from: cslItem(for: reference))
    }

    public static func cslJSONObjects(for references: [Reference]) -> [[String: Any]] {
        references.compactMap { reference in
            guard reference.id != nil else { return nil }
            return cslJSONObject(for: reference)
        }
    }

    public static func jsonObject(from item: CSLItem) -> [String: Any] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(item),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func cslNames(from authors: [AuthorName]) -> [CSLName]? {
        let normalized = AuthorName.deduplicatingRepeatedSequence(
            AuthorName.normalizedForCitation(authors)
        )
        guard !normalized.isEmpty else { return nil }
        return normalized.map { author in
            if shouldUseLiteralName(author) {
                return .institution(author.displayName)
            }
            return .person(given: author.given, family: author.family)
        }
    }

    private static func shouldUseLiteralName(_ author: AuthorName) -> Bool {
        let family = author.family.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = author.given.trimmingCharacters(in: .whitespacesAndNewlines)
        guard given.isEmpty else { return false }
        let lower = family.lowercased()
        let organizationHints = [
            "university", "institute", "committee", "commission", "organization",
            "organisation", "ministry", "department", "agency", "center", "centre",
            "laboratory", "academy", "society", "association", "team", "group",
            "office", "bureau", "council", "foundation",
        ]
        if organizationHints.contains(where: { lower.contains($0) }) { return true }
        if family.range(of: #"(大学|学院|研究所|委员会|中心|部|厅|局|院|协会|学会|课题组|编委会)"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
