import Foundation

public enum ReferenceLibraryRepairChangeKind: String, Codable, Sendable {
    case normalizedDOI
    case removedStableJournalAccessedDate
    case normalizedAuthorNames
    case normalizedEditorNames
    case normalizedTranslatorNames
    case removedRepeatedAuthorSequence
    case repairedAuthorSwap
    case inferredJournalArticleType
}

public struct ReferenceLibraryRepairChange: Codable, Equatable, Sendable {
    public let kind: ReferenceLibraryRepairChangeKind
    public let before: String?
    public let after: String?

    public init(kind: ReferenceLibraryRepairChangeKind, before: String?, after: String?) {
        self.kind = kind
        self.before = before
        self.after = after
    }
}

public struct ReferenceLibraryRepairCandidate: Codable, Equatable, Sendable {
    public let referenceID: Int64?
    public let title: String
    public let changes: [ReferenceLibraryRepairChange]

    public init(referenceID: Int64?, title: String, changes: [ReferenceLibraryRepairChange]) {
        self.referenceID = referenceID
        self.title = title
        self.changes = changes
    }
}

public struct ReferenceLibraryRepairReport: Codable, Equatable, Sendable {
    public let referenceCount: Int
    public let candidateCount: Int
    public let appliedCount: Int
    public let displayedCount: Int
    public let candidates: [ReferenceLibraryRepairCandidate]

    public init(
        referenceCount: Int,
        candidateCount: Int? = nil,
        appliedCount: Int = 0,
        displayedCount: Int? = nil,
        candidates: [ReferenceLibraryRepairCandidate]
    ) {
        self.referenceCount = referenceCount
        self.candidateCount = candidateCount ?? candidates.count
        self.appliedCount = appliedCount
        self.displayedCount = displayedCount ?? candidates.count
        self.candidates = candidates
    }
}

public enum ReferenceLibraryRepairer {
    public static func repairPlan(for references: [Reference]) -> ReferenceLibraryRepairReport {
        let candidates = references.compactMap { reference -> ReferenceLibraryRepairCandidate? in
            let repaired = repairedReference(reference)
            let changes = changes(from: reference, to: repaired)
            guard !changes.isEmpty else { return nil }
            return ReferenceLibraryRepairCandidate(
                referenceID: reference.id,
                title: reference.title,
                changes: changes
            )
        }
        return ReferenceLibraryRepairReport(referenceCount: references.count, candidates: candidates)
    }

    public static func repairedReference(_ reference: Reference) -> Reference {
        ReferenceIntakeCanonicalizer.canonicalized(reference, options: .repair)
    }

    private static func changes(from original: Reference, to repaired: Reference) -> [ReferenceLibraryRepairChange] {
        var changes: [ReferenceLibraryRepairChange] = []

        if original.doi != repaired.doi {
            changes.append(.init(
                kind: .normalizedDOI,
                before: original.doi,
                after: repaired.doi
            ))
        }

        if original.accessedDate != repaired.accessedDate {
            changes.append(.init(
                kind: .removedStableJournalAccessedDate,
                before: original.accessedDate,
                after: repaired.accessedDate
            ))
        }

        // Track author changes: distinguish normalizedAuthorNames from repairedAuthorSwap
        // so the UI can show a more precise explanation to the user.
        if original.authors != repaired.authors {
            let hasSwap = zip(original.authors, repaired.authors).contains { orig, rep in
                orig.given == rep.family && orig.family == rep.given
            }
            let removedRepeatedSequence = AuthorName.deduplicatingRepeatedSequence(original.authors) == repaired.authors
            changes.append(.init(
                kind: removedRepeatedSequence
                    ? .removedRepeatedAuthorSequence
                    : (hasSwap ? .repairedAuthorSwap : .normalizedAuthorNames),
                before: authorRepairDisplayString(original.authors),
                after: authorRepairDisplayString(repaired.authors)
            ))
        }

        if original.editors != repaired.editors {
            changes.append(.init(
                kind: .normalizedEditorNames,
                before: authorRepairDisplayString(original.parsedEditors),
                after: authorRepairDisplayString(repaired.parsedEditors)
            ))
        }

        if original.translators != repaired.translators {
            changes.append(.init(
                kind: .normalizedTranslatorNames,
                before: authorRepairDisplayString(original.parsedTranslators),
                after: authorRepairDisplayString(repaired.parsedTranslators)
            ))
        }

        if original.referenceType != repaired.referenceType {
            changes.append(.init(
                kind: .inferredJournalArticleType,
                before: original.referenceType.rawValue,
                after: repaired.referenceType.rawValue
            ))
        }

        return changes
    }

    private static func isStableJournalLike(_ reference: Reference) -> Bool {
        switch reference.referenceType {
        case .journalArticle, .magazineArticle, .newspaperArticle, .preprint, .other:
            return hasJournalEvidence(reference)
        default:
            return false
        }
    }

    private static func hasJournalEvidence(_ reference: Reference) -> Bool {
        reference.journal?.swiftlib_nilIfBlank != nil
            || reference.volume?.swiftlib_nilIfBlank != nil
            || reference.issue?.swiftlib_nilIfBlank != nil
            || reference.pages?.swiftlib_nilIfBlank != nil
            || reference.issn?.swiftlib_nilIfBlank != nil
    }

    private static func hasStablePublicationDetails(_ reference: Reference) -> Bool {
        reference.volume?.swiftlib_nilIfBlank != nil
            || reference.issue?.swiftlib_nilIfBlank != nil
            || reference.pages?.swiftlib_nilIfBlank != nil
    }

    private static func authorRepairDisplayString(_ authors: [AuthorName]) -> String {
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
}
