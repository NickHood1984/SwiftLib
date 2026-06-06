import Foundation

public enum ReferenceLibraryAuditIssueKind: String, Codable, Sendable {
    case doiHasURLPrefix
    case stableJournalHasAccessedDate
    case suspiciousAuthorName
    case suspiciousAuthorSwap
    case repeatedAuthorSequence
    case journalEvidenceWithOtherType
    case probableDuplicateTranslation
}

public struct ReferenceLibraryAuditIssue: Codable, Equatable, Sendable {
    public let referenceID: Int64?
    public let title: String
    public let kind: ReferenceLibraryAuditIssueKind
    public let message: String

    public init(referenceID: Int64?, title: String, kind: ReferenceLibraryAuditIssueKind, message: String) {
        self.referenceID = referenceID
        self.title = title
        self.kind = kind
        self.message = message
    }
}

public struct ReferenceLibraryAuditReport: Codable, Equatable, Sendable {
    public let referenceCount: Int
    public let issueCount: Int
    public let issues: [ReferenceLibraryAuditIssue]

    public init(referenceCount: Int, issues: [ReferenceLibraryAuditIssue]) {
        self.referenceCount = referenceCount
        self.issueCount = issues.count
        self.issues = issues
    }
}

public enum ReferenceLibraryAuditor {
    public static func audit(_ references: [Reference]) -> ReferenceLibraryAuditReport {
        var issues: [ReferenceLibraryAuditIssue] = []

        for reference in references {
            issues.append(contentsOf: audit(reference))
        }
        issues.append(contentsOf: probableDuplicateTranslationIssues(in: references))

        return ReferenceLibraryAuditReport(referenceCount: references.count, issues: issues)
    }

    public static func audit(_ reference: Reference) -> [ReferenceLibraryAuditIssue] {
        var issues: [ReferenceLibraryAuditIssue] = []

        if let doi = reference.doi?.swiftlib_nilIfBlank, DOIIdentifier(doi) != nil {
            let lower = doi.lowercased()
            if lower.hasPrefix("http://doi.org/")
                || lower.hasPrefix("https://doi.org/")
                || lower.hasPrefix("http://dx.doi.org/")
                || lower.hasPrefix("https://dx.doi.org/")
                || lower.hasPrefix("doi:") {
                issues.append(issue(
                    reference,
                    kind: .doiHasURLPrefix,
                    message: "DOI should be stored and rendered as a bare DOI, not with a URL or DOI: prefix."
                ))
            }
        }

        if isStableJournalLike(reference),
           hasStablePublicationDetails(reference),
           reference.accessedDate?.swiftlib_nilIfBlank != nil {
            issues.append(issue(
                reference,
                kind: .stableJournalHasAccessedDate,
                message: "Stable journal-like records with volume/issue/pages should not render an accessed date."
            ))
        }

        let authorIssues = AuthorName.validationIssues(in: reference.authors)
        for authorIssue in authorIssues {
            issues.append(issue(
                reference,
                kind: .suspiciousAuthorName,
                message: "Suspicious author #\(authorIssue.index + 1) '\(authorIssue.displayName)': \(authorIssue.message)."
            ))
        }

        let deduplicatedAuthors = AuthorName.deduplicatingRepeatedSequence(reference.authors)
        if deduplicatedAuthors != reference.authors {
            issues.append(issue(
                reference,
                kind: .repeatedAuthorSequence,
                message: "Author list appears to repeat the same ordered sequence; citation output should keep only the first sequence."
            ))
        }

        let swapIssues = AuthorName.pinyinSwapIssues(in: reference.authors)
        for swapIssue in swapIssues {
            issues.append(issue(
                reference,
                kind: .suspiciousAuthorSwap,
                message: "Author #\(swapIssue.index + 1) '\(swapIssue.displayName)': \(swapIssue.message)."
            ))
        }

        if reference.referenceType == .other,
           hasJournalEvidence(reference) {
            issues.append(issue(
                reference,
                kind: .journalEvidenceWithOtherType,
                message: "Record has journal evidence but is typed as Other; GB/T rendering may mark it as [A] unless inferred as a journal article."
            ))
        }

        return issues
    }

    private static func issue(
        _ reference: Reference,
        kind: ReferenceLibraryAuditIssueKind,
        message: String
    ) -> ReferenceLibraryAuditIssue {
        ReferenceLibraryAuditIssue(
            referenceID: reference.id,
            title: reference.title,
            kind: kind,
            message: message
        )
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

    private static func probableDuplicateTranslationIssues(in references: [Reference]) -> [ReferenceLibraryAuditIssue] {
        let chineseBooks = references.filter(isChineseBookCandidate)
        let latinBooks = references.filter(isLatinBookCandidate)
        guard !chineseBooks.isEmpty, !latinBooks.isEmpty else { return [] }

        var issues: [ReferenceLibraryAuditIssue] = []
        for latin in latinBooks {
            for chinese in chineseBooks where latin.year == chinese.year {
                guard let evidence = probableDuplicateEvidence(latin: latin, chinese: chinese) else { continue }
                issues.append(issue(
                    latin,
                    kind: .probableDuplicateTranslation,
                    message: "Possible duplicate translation of reference \(chinese.id.map(String.init) ?? "unsaved") '\(chinese.title)' (\(evidence)); verify before merging or deleting either record."
                ))
            }
        }
        return issues
    }

    private static func isChineseBookCandidate(_ reference: Reference) -> Bool {
        reference.referenceType == .book
            && containsHan(reference.title)
            && reference.year != nil
    }

    private static func isLatinBookCandidate(_ reference: Reference) -> Bool {
        reference.referenceType == .book
            && !containsHan(reference.title)
            && containsLatinLetter(reference.title)
            && reference.year != nil
    }

    private static func probableDuplicateEvidence(latin: Reference, chinese: Reference) -> String? {
        if let sharedIdentifier = sharedIdentifierEvidence(latin: latin, chinese: chinese) {
            return sharedIdentifier
        }

        let authorOverlapCount = translatedAuthorOverlapCount(latin.authors, chinese.authors)
        let publisherMatches = transliteratedTextMatches(latin.publisher, chinese.publisher)
        let placeMatches = transliteratedTextMatches(latin.publisherPlace, chinese.publisherPlace)

        if authorOverlapCount >= 2 {
            return "same year and \(authorOverlapCount) transliterated author matches"
        }
        if authorOverlapCount >= 1, publisherMatches || placeMatches {
            let venue = publisherMatches && placeMatches
                ? "publisher/place"
                : (publisherMatches ? "publisher" : "place")
            return "same year, transliterated author match, and matching \(venue)"
        }
        return nil
    }

    private static func sharedIdentifierEvidence(latin: Reference, chinese: Reference) -> String? {
        if let left = latin.doi.flatMap(DOIIdentifier.canonical(for:)),
           let right = chinese.doi.flatMap(DOIIdentifier.canonical(for:)),
           left == right {
            return "same DOI"
        }
        if let left = normalizedISBN(latin.isbn),
           let right = normalizedISBN(chinese.isbn),
           left == right {
            return "same ISBN"
        }
        if let left = normalizedURL(latin.url),
           let right = normalizedURL(chinese.url),
           left == right {
            return "same URL"
        }
        return nil
    }

    private static func translatedAuthorOverlapCount(_ latinAuthors: [AuthorName], _ chineseAuthors: [AuthorName]) -> Int {
        let latinKeys = Set(latinAuthors.compactMap(latinAuthorKey))
        let chineseKeys = Set(chineseAuthors.compactMap(hanAuthorKey))
        return latinKeys.intersection(chineseKeys).count
    }

    private static func latinAuthorKey(_ author: AuthorName) -> String? {
        let family = normalizedLatinText(author.family)
        guard !family.isEmpty else { return nil }
        let givenTokens = normalizedLatinText(author.given)
            .split(separator: " ")
            .map(String.init)
        let initials = givenTokens.compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? family : "\(family):\(initials)"
    }

    private static func hanAuthorKey(_ author: AuthorName) -> String? {
        let name = normalizedHanText(author.family + author.given)
        guard name.count >= 2 else { return nil }
        let transliterated = transliteratedHanTokens(name)
        guard transliterated.count >= 2 else { return nil }
        let family = transliterated[0]
        let initials = transliterated.dropFirst().compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? family : "\(family):\(initials)"
    }

    private static func transliteratedTextMatches(_ latinText: String?, _ chineseText: String?) -> Bool {
        guard let latinText = latinText?.swiftlib_nilIfBlank,
              let chineseText = chineseText?.swiftlib_nilIfBlank else { return false }
        let latin = normalizedCompactLatinText(latinText)
        let chinese = normalizedCompactLatinText(transliteratedHanText(chineseText))
        return !latin.isEmpty && latin == chinese
    }

    private static func normalizedISBN(_ value: String?) -> String? {
        guard let raw = value?.swiftlib_nilIfBlank else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        return (normalized.count == 10 || normalized.count == 13) ? normalized : nil
    }

    private static func normalizedURL(_ value: String?) -> String? {
        value?.swiftlib_nilIfBlank?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func normalizedLatinText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedCompactLatinText(_ text: String) -> String {
        normalizedLatinText(text)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private static func normalizedHanText(_ text: String) -> String {
        text.replacingOccurrences(of: #"[^\p{Han}]+"#, with: "", options: .regularExpression)
    }

    private static func transliteratedHanText(_ text: String) -> String {
        (text.applyingTransform(.toLatin, reverse: false) ?? text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func transliteratedHanTokens(_ text: String) -> [String] {
        normalizedLatinText(transliteratedHanText(text))
            .split(separator: " ")
            .map(String.init)
    }

    private static func containsHan(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private static func containsLatinLetter(_ text: String) -> Bool {
        text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }
}
