import Foundation
import GRDB

// MARK: - Reference Support
extension AppDatabase {
    func normalizedDOI(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    func normalizedPMID(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    func normalizedPMCID(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.uppercased()
    }

    func normalizedISBN(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        guard normalized.count == 10 || normalized.count == 13 else { return nil }
        return normalized
    }

    func normalizedISSN(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        guard normalized.count == 8 else { return nil }
        return normalized
    }

    func normalizeForDedup(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let folded = (raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return folded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedTitleKey(_ value: String?) -> String? {
        guard let normalized = normalizeForDedup(value) else { return nil }
        return normalized
            .replacingOccurrences(of: #"[[:punct:]\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizeForDirectLibrarySave(_ reference: inout Reference) throws {
        guard reference.id == nil,
              !reference.verificationStatus.isLibraryReady,
              reference.metadataSource == nil else {
            return
        }

        reference = MetadataVerifier.manuallyVerified(reference, reviewedBy: "direct-save")
    }

    func ensureLibraryReady(_ reference: Reference) throws {
        guard reference.verificationStatus.isLibraryReady else {
            throw NSError(
                domain: "SwiftLib.AppDatabase",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "只有 verifiedAuto 或 verifiedManual 条目可写入正式资料库。"]
            )
        }
    }
    func findDuplicateReferenceID(for reference: Reference, db: Database) throws -> Int64? {
        if let doi = normalizedDOI(reference.doi),
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE doiNormalized = ? LIMIT 1", arguments: [doi]) {
            return id
        }

        if let pmid = normalizedPMID(reference.pmid),
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE pmid = ? LIMIT 1", arguments: [pmid]) {
            return id
        }

        if let pmcid = normalizedPMCID(reference.pmcid),
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE pmcidNormalized = ? LIMIT 1", arguments: [pmcid]) {
            return id
        }

        if let isbn = normalizedISBN(reference.isbn),
           let id = try Int64.fetchOne(
            db,
            sql: "SELECT id FROM reference WHERE isbnNormalized = ? LIMIT 1",
            arguments: [isbn]
           ) {
            return id
        }

        if let url = reference.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE url = ? LIMIT 1", arguments: [url]) {
            return id
        }

        if let issn = normalizedISSN(reference.issn),
           let normalizedTitle = normalizedTitleKey(reference.title), !normalizedTitle.isEmpty,
           let year = reference.year {
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title
                    FROM reference
                    WHERE issnNormalized = ?
                      AND year = ?
                    LIMIT 20
                    """,
                arguments: [issn, year]
            )
            if let match = rows.first(where: { normalizedTitleKey(($0["title"] as String?)) == normalizedTitle }) {
                return match["id"]
            }
        }

        if let normalizedTitle = normalizedTitleKey(reference.title), !normalizedTitle.isEmpty,
           let year = reference.year,
           let normalizedAuthors = normalizeForDedup(reference.authorsNormalized), !normalizedAuthors.isEmpty {
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title
                    FROM reference
                    WHERE year = ?
                      AND authorsNormalized = ?
                    LIMIT 50
                    """,
                arguments: [year, normalizedAuthors]
            )
            if let match = rows.first(where: { normalizedTitleKey(($0["title"] as String?)) == normalizedTitle }) {
                return match["id"]
            }
        }

        return nil
    }

    func mergedReference(existing: Reference, incoming: Reference) -> Reference {
        func preferred(_ incoming: String?, over existing: String?) -> String? {
            let candidate = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let candidate, !candidate.isEmpty { return candidate }
            return existing
        }

        func preferredLongest(_ incoming: String?, over existing: String?) -> String? {
            let lhs = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (lhs?.isEmpty == false ? lhs : nil, rhs?.isEmpty == false ? rhs : nil) {
            case let (l?, r?): return l.count >= r.count ? l : r
            case let (l?, nil): return l
            case let (nil, r?): return r
            default: return nil
            }
        }

        var merged = existing
        merged.title = preferred(incoming.title, over: existing.title) ?? existing.title
        merged.authors = incoming.authors.isEmpty ? existing.authors : incoming.authors
        merged.year = incoming.year ?? existing.year
        merged.journal = preferred(incoming.journal, over: existing.journal)
        merged.volume = preferred(incoming.volume, over: existing.volume)
        merged.issue = preferred(incoming.issue, over: existing.issue)
        merged.pages = preferred(incoming.pages, over: existing.pages)
        merged.doi = preferred(incoming.doi, over: existing.doi)
        merged.url = preferred(incoming.url, over: existing.url)
        merged.abstract = preferredLongest(incoming.abstract, over: existing.abstract)
        merged.pdfPath = preferred(incoming.pdfPath, over: existing.pdfPath)
        merged.notes = preferredLongest(incoming.notes, over: existing.notes)
        merged.webContent = preferredLongest(incoming.webContent, over: existing.webContent)
        merged.siteName = preferred(incoming.siteName, over: existing.siteName)
        merged.favicon = preferred(incoming.favicon, over: existing.favicon)
        if existing.referenceType == .other || existing.referenceType == .webpage {
            merged.referenceType = incoming.referenceType
        }
        merged.metadataSource = incoming.metadataSource ?? existing.metadataSource
        merged.verificationStatus = incoming.verificationStatus.isLibraryReady ? incoming.verificationStatus : existing.verificationStatus
        merged.acceptedByRuleID = preferred(incoming.acceptedByRuleID, over: existing.acceptedByRuleID)
        merged.recordKey = preferred(incoming.recordKey, over: existing.recordKey)
        merged.verificationSourceURL = preferred(incoming.verificationSourceURL, over: existing.verificationSourceURL)
        merged.evidenceBundleHash = preferred(incoming.evidenceBundleHash, over: existing.evidenceBundleHash)
        merged.verifiedAt = incoming.verifiedAt ?? existing.verifiedAt
        merged.reviewedBy = preferred(incoming.reviewedBy, over: existing.reviewedBy)
        merged.collectionId = incoming.collectionId ?? existing.collectionId
        merged.publisher = preferred(incoming.publisher, over: existing.publisher)
        merged.publisherPlace = preferred(incoming.publisherPlace, over: existing.publisherPlace)
        merged.edition = preferred(incoming.edition, over: existing.edition)
        merged.editors = preferred(incoming.editors, over: existing.editors)
        merged.isbn = preferred(incoming.isbn, over: existing.isbn)
        merged.issn = preferred(incoming.issn, over: existing.issn)
        merged.accessedDate = preferred(incoming.accessedDate, over: existing.accessedDate)
        merged.issuedMonth = incoming.issuedMonth ?? existing.issuedMonth
        merged.issuedDay = incoming.issuedDay ?? existing.issuedDay
        merged.translators = preferred(incoming.translators, over: existing.translators)
        merged.eventTitle = preferred(incoming.eventTitle, over: existing.eventTitle)
        merged.eventPlace = preferred(incoming.eventPlace, over: existing.eventPlace)
        merged.genre = preferred(incoming.genre, over: existing.genre)
        merged.institution = preferred(incoming.institution, over: existing.institution)
        merged.number = preferred(incoming.number, over: existing.number)
        merged.collectionTitle = preferred(incoming.collectionTitle, over: existing.collectionTitle)
        merged.numberOfPages = preferred(incoming.numberOfPages, over: existing.numberOfPages)
        merged.language = preferred(incoming.language, over: existing.language)
        merged.pmid = preferred(incoming.pmid, over: existing.pmid)
        merged.pmcid = preferred(incoming.pmcid, over: existing.pmcid)
        merged.dateAdded = existing.dateAdded
        merged.dateModified = Date()
        return merged
    }
}
