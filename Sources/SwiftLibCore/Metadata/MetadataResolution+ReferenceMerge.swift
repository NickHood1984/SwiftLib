import Foundation

extension MetadataResolution {
    public static func mergeReference(primary: Reference, fallback: Reference) -> Reference {
        var merged = primary
        merged.title = primary.title.swiftlib_nilIfBlank ?? fallback.title
        merged.authors = preferredAuthors(primary: primary.authors, fallback: fallback.authors)
        merged.year = primary.year ?? fallback.year
        merged.journal = primary.journal.swiftlib_nilIfBlank ?? fallback.journal
        merged.volume = primary.volume.swiftlib_nilIfBlank ?? fallback.volume
        merged.issue = primary.issue.swiftlib_nilIfBlank ?? fallback.issue
        merged.pages = primary.pages.swiftlib_nilIfBlank ?? fallback.pages
        merged.doi = primary.doi.swiftlib_nilIfBlank ?? fallback.doi
        merged.url = primary.url.swiftlib_nilIfBlank ?? fallback.url
        merged.abstract = primary.abstract.swiftlib_nilIfBlank ?? fallback.abstract
        merged.notes = primary.notes.swiftlib_nilIfBlank ?? fallback.notes
        merged.pdfPath = primary.pdfPath.swiftlib_nilIfBlank ?? fallback.pdfPath
        merged.siteName = primary.siteName.swiftlib_nilIfBlank ?? fallback.siteName
        merged.metadataSource = primary.metadataSource ?? fallback.metadataSource
        merged.verificationStatus = primary.verificationStatus
        merged.acceptedByRuleID = primary.acceptedByRuleID ?? fallback.acceptedByRuleID
        merged.recordKey = primary.recordKey.swiftlib_nilIfBlank ?? fallback.recordKey
        merged.verificationSourceURL = primary.verificationSourceURL.swiftlib_nilIfBlank ?? fallback.verificationSourceURL
        merged.evidenceBundleHash = primary.evidenceBundleHash.swiftlib_nilIfBlank ?? fallback.evidenceBundleHash
        merged.verifiedAt = primary.verifiedAt ?? fallback.verifiedAt
        merged.reviewedBy = primary.reviewedBy.swiftlib_nilIfBlank ?? fallback.reviewedBy
        merged.referenceType = primary.referenceType == .other ? fallback.referenceType : primary.referenceType
        merged.publisher = primary.publisher.swiftlib_nilIfBlank ?? fallback.publisher
        merged.publisherPlace = primary.publisherPlace.swiftlib_nilIfBlank ?? fallback.publisherPlace
        merged.edition = primary.edition.swiftlib_nilIfBlank ?? fallback.edition
        merged.editors = primary.editors.swiftlib_nilIfBlank ?? fallback.editors
        merged.isbn = primary.isbn.swiftlib_nilIfBlank ?? fallback.isbn
        merged.issn = primary.issn.swiftlib_nilIfBlank ?? fallback.issn
        merged.accessedDate = primary.accessedDate.swiftlib_nilIfBlank ?? fallback.accessedDate
        merged.issuedMonth = primary.issuedMonth ?? fallback.issuedMonth
        merged.issuedDay = primary.issuedDay ?? fallback.issuedDay
        merged.translators = primary.translators.swiftlib_nilIfBlank ?? fallback.translators
        merged.eventTitle = primary.eventTitle.swiftlib_nilIfBlank ?? fallback.eventTitle
        merged.eventPlace = primary.eventPlace.swiftlib_nilIfBlank ?? fallback.eventPlace
        merged.genre = primary.genre.swiftlib_nilIfBlank ?? fallback.genre
        merged.institution = primary.institution.swiftlib_nilIfBlank ?? fallback.institution
        merged.number = primary.number.swiftlib_nilIfBlank ?? fallback.number
        merged.collectionTitle = primary.collectionTitle.swiftlib_nilIfBlank ?? fallback.collectionTitle
        merged.numberOfPages = primary.numberOfPages.swiftlib_nilIfBlank ?? fallback.numberOfPages
        merged.language = primary.language.swiftlib_nilIfBlank ?? fallback.language
        merged.pmid = primary.pmid.swiftlib_nilIfBlank ?? fallback.pmid
        merged.pmcid = primary.pmcid.swiftlib_nilIfBlank ?? fallback.pmcid
        merged.dateAdded = fallback.dateAdded
        merged.dateModified = Date()
        return merged
    }

    public static func mergeRefreshedReference(primary: Reference, existing: Reference) -> Reference {
        // Refresh strategy: authoritative fetched metadata should replace the old
        // bibliographic fields, while local state (library id, collection, notes,
        // attachments, cached reader content) must survive the refresh.
        var merged = mergeReference(primary: primary, fallback: existing)
        merged.id = existing.id
        merged.collectionId = existing.collectionId
        merged.notes = existing.notes.swiftlib_nilIfBlank ?? primary.notes
        merged.pdfPath = existing.pdfPath.swiftlib_nilIfBlank ?? primary.pdfPath
        merged.metadataSource = primary.metadataSource ?? existing.metadataSource
        merged.webContent = primary.webContent ?? existing.webContent
        merged.favicon = primary.favicon ?? existing.favicon
        merged.verificationStatus = primary.verificationStatus
        merged.acceptedByRuleID = primary.acceptedByRuleID ?? existing.acceptedByRuleID
        merged.recordKey = primary.recordKey.swiftlib_nilIfBlank ?? existing.recordKey
        merged.verificationSourceURL = primary.verificationSourceURL.swiftlib_nilIfBlank ?? existing.verificationSourceURL
        merged.evidenceBundleHash = primary.evidenceBundleHash.swiftlib_nilIfBlank ?? existing.evidenceBundleHash
        merged.verifiedAt = primary.verifiedAt ?? existing.verifiedAt
        merged.reviewedBy = primary.reviewedBy.swiftlib_nilIfBlank ?? existing.reviewedBy
        merged.dateModified = Date()
        merged.lastRefreshedAt = Date()
        return merged
    }

    public static func hasMeaningfulRefreshChanges(original: Reference, refreshed: Reference) -> Bool {
        var comparableOriginal = original
        var comparableRefreshed = refreshed
        comparableOriginal.id = nil
        comparableRefreshed.dateModified = comparableOriginal.dateModified
        comparableRefreshed.dateAdded = comparableOriginal.dateAdded
        comparableRefreshed.lastRefreshedAt = comparableOriginal.lastRefreshedAt
        comparableRefreshed.id = nil
        return comparableOriginal != comparableRefreshed
    }


    private static func preferredAuthors(primary: [AuthorName], fallback: [AuthorName]) -> [AuthorName] {
        let normalizedPrimary = normalizedAuthors(primary)
        let normalizedFallback = normalizedAuthors(fallback)

        guard !normalizedPrimary.isEmpty else { return normalizedFallback }
        guard !normalizedFallback.isEmpty else { return normalizedPrimary }

        let primaryScore = authorCompletenessScore(normalizedPrimary)
        let fallbackScore = authorCompletenessScore(normalizedFallback)

        if primaryScore > fallbackScore + 0.15 {
            return normalizedPrimary
        }
        if fallbackScore > primaryScore + 0.15 {
            return normalizedFallback
        }
        if normalizedPrimary.count > normalizedFallback.count && !containsEtAl(normalizedPrimary) {
            return normalizedPrimary
        }
        if normalizedFallback.count > normalizedPrimary.count && !containsEtAl(normalizedFallback) {
            return normalizedFallback
        }
        return normalizedFallback
    }

    private static func normalizedAuthors(_ authors: [AuthorName]) -> [AuthorName] {
        var seen = Set<String>()
        return authors.filter { author in
            let display = author.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { return false }
            return seen.insert(display).inserted
        }
    }

    private static func authorCompletenessScore(_ authors: [AuthorName]) -> Double {
        guard !authors.isEmpty else { return 0 }

        let countScore = min(Double(authors.count), 8)
        let personalRatio = 1 - institutionalAuthorRatio(for: authors)
        let etAlPenalty = containsEtAl(authors) ? 1.2 : 0
        let suspiciousPenalty = Double(authors.filter { obviousNonAuthorHanToken($0.displayName) || looksLikeNonAuthorLatinToken($0.displayName) }.count) * 0.8

        return countScore + (personalRatio * 0.8) - etAlPenalty - suspiciousPenalty
    }

    private static func containsEtAl(_ authors: [AuthorName]) -> Bool {
        authors.contains { author in
            let display = author.displayName.lowercased()
            return display.contains("等") || display.contains("et al")
        }
    }
}
