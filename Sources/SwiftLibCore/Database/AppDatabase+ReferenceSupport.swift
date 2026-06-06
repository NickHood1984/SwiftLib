import Foundation
import GRDB

// MARK: - Reference Support
extension AppDatabase {
    func normalizedDOI(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return DOIIdentifier.canonical(for: raw) ?? raw.lowercased()
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

    func normalizeReferenceFieldsForStorage(_ reference: inout Reference) {
        reference = ReferenceIntakeCanonicalizer.canonicalized(reference, options: .storage)
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
        // .legacy is allowed: it represents either migrated historical records or
        // file-imported references (BibTeX/RIS) that are trusted but not
        // authoritative-verified. All other non-library-ready statuses (candidate,
        // seedOnly, blocked) must go through the pending queue instead.
        guard reference.verificationStatus.isLibraryReady || reference.verificationStatus == .legacy else {
            throw NSError(
                domain: "SwiftLib.AppDatabase",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "只有 verifiedAuto、verifiedManual 或 legacy 条目可写入正式资料库。"]
            )
        }
    }

    /// Normalize a reference for a file-batch import (BibTeX / RIS).
    ///
    /// Unlike `normalizeForDirectLibrarySave`, this does NOT promote the record to
    /// `verifiedManual`. File imports are trusted but not authoritative-verified, so
    /// they remain `.legacy` — distinguishable from pipeline-verified entries in
    /// health stats, CSL-completeness badges, and the library dashboard.
    func normalizeForFileBatchImport(_ reference: inout Reference) {
        guard reference.id == nil, reference.verificationStatus == .legacy else { return }
        reference.verifiedAt = reference.verifiedAt ?? Date()
        reference.reviewedBy = reference.reviewedBy ?? "file-import"
    }
    func findDuplicateReferenceID(for reference: Reference, db: Database) throws -> Int64? {
        if let doi = normalizedDOI(reference.doi) {
            let variants = doiLookupVariants(for: doi)
            let placeholders = Array(repeating: "?", count: variants.count).joined(separator: ",")
            if let id = try Int64.fetchOne(
                db,
                sql: """
                    SELECT id
                    FROM reference
                    WHERE doiNormalized IN (\(placeholders))
                       OR LOWER(TRIM(doi)) IN (\(placeholders))
                    LIMIT 1
                    """,
                arguments: StatementArguments(variants + variants)
            ) {
                return id
            }
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

    private func doiLookupVariants(for canonicalDOI: String) -> [String] {
        let bare = canonicalDOI.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !bare.isEmpty else { return [] }
        return [
            bare,
            "https://doi.org/\(bare)",
            "http://doi.org/\(bare)",
            "https://dx.doi.org/\(bare)",
            "http://dx.doi.org/\(bare)",
            "doi:\(bare)",
        ]
    }

    func mergedReference(existing: Reference, incoming: Reference) -> Reference {
        func preferred(_ incoming: String?, over existing: String?) -> String? {
            let candidate = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let candidate, !candidate.isEmpty { return candidate }
            return existing
        }

        // Prefer the existing value if it is non-empty; fill from incoming only when
        // existing is nil/blank.  Used when the existing record has stronger provenance.
        func preferExisting(_ existing: String?, over incoming: String?) -> String? {
            let candidate = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let candidate, !candidate.isEmpty { return candidate }
            return incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // When the existing record is verified (auto or manual) and the incoming is
        // weaker (e.g. a file import with .legacy status), protect authoritative
        // bibliographic fields from being silently overwritten by the weaker source.
        let existingIsStronger: Bool = {
            let existingVerified = existing.verificationStatus == .verifiedAuto
                || existing.verificationStatus == .verifiedManual
            let incomingVerified = incoming.verificationStatus == .verifiedAuto
                || incoming.verificationStatus == .verifiedManual
            return existingVerified && !incomingVerified
        }()

        // Choose the field-level merge strategy based on relative record quality.
        // For bibliographic core fields: prefer incoming when both are unverified;
        // prefer existing when it is already verified and incoming is weaker.
        func bibField(_ inc: String?, _ ext: String?) -> String? {
            existingIsStronger ? preferExisting(ext, over: inc) : preferred(inc, over: ext)
        }
        func bibYear(_ inc: Int?, _ ext: Int?) -> Int? {
            existingIsStronger ? (ext ?? inc) : (inc ?? ext)
        }

        var merged = existing
        merged.title = bibField(incoming.title, existing.title) ?? existing.title
        merged.authors = existingIsStronger
            ? (existing.authors.isEmpty ? incoming.authors : existing.authors)
            : (incoming.authors.isEmpty ? existing.authors : incoming.authors)
        // Bibliographic core — when existing is verified and incoming is weaker, protect
        // the authoritative values and only fill genuinely missing fields from incoming.
        merged.year = bibYear(incoming.year, existing.year)
        merged.journal = bibField(incoming.journal, existing.journal)
        merged.volume = bibField(incoming.volume, existing.volume)
        merged.issue = bibField(incoming.issue, existing.issue)
        merged.pages = bibField(incoming.pages, existing.pages)
        merged.doi = bibField(incoming.doi, existing.doi)
            .flatMap { DOIIdentifier($0)?.cslString ?? $0.swiftlib_nilIfBlank }
        merged.url = bibField(incoming.url, existing.url)

        // Attachment and user-accumulated text: always prefer the richer value
        // regardless of verification strength (the user may add a PDF or longer
        // abstract at any time).
        merged.abstract = preferredLongest(incoming.abstract, over: existing.abstract)
        merged.pdfPath = preferred(incoming.pdfPath, over: existing.pdfPath)
        merged.notes = preferredLongest(incoming.notes, over: existing.notes)
        merged.webContent = preferredLongest(incoming.webContent, over: existing.webContent)
        merged.siteName = bibField(incoming.siteName, existing.siteName)
        merged.favicon = bibField(incoming.favicon, existing.favicon)

        // Type upgrade: allow incoming to improve a generic type, but only when
        // existing has not been verified against a specific type.
        if !existingIsStronger && (existing.referenceType == .other || existing.referenceType == .webpage) {
            merged.referenceType = incoming.referenceType
        }

        // Verification provenance — protect when existing is the stronger record.
        merged.metadataSource = existingIsStronger
            ? (existing.metadataSource ?? incoming.metadataSource)
            : (incoming.metadataSource ?? existing.metadataSource)
        merged.verificationStatus = incoming.verificationStatus.isLibraryReady
            ? incoming.verificationStatus : existing.verificationStatus
        merged.acceptedByRuleID = bibField(incoming.acceptedByRuleID, existing.acceptedByRuleID)
        merged.recordKey = bibField(incoming.recordKey, existing.recordKey)
        merged.verificationSourceURL = bibField(incoming.verificationSourceURL, existing.verificationSourceURL)
        merged.evidenceBundleHash = bibField(incoming.evidenceBundleHash, existing.evidenceBundleHash)
        merged.verifiedAt = existingIsStronger
            ? (existing.verifiedAt ?? incoming.verifiedAt)
            : (incoming.verifiedAt ?? existing.verifiedAt)
        merged.reviewedBy = bibField(incoming.reviewedBy, existing.reviewedBy)

        // Collection placement: incoming wins (user may be importing into a target collection).
        merged.collectionId = incoming.collectionId ?? existing.collectionId

        // Remaining bibliographic fields.
        merged.publisher = bibField(incoming.publisher, existing.publisher)
        merged.publisherPlace = bibField(incoming.publisherPlace, existing.publisherPlace)
        merged.edition = bibField(incoming.edition, existing.edition)
        merged.editors = bibField(incoming.editors, existing.editors)
        merged.isbn = bibField(incoming.isbn, existing.isbn)
        merged.issn = bibField(incoming.issn, existing.issn)
        merged.accessedDate = preferred(incoming.accessedDate, over: existing.accessedDate)
        merged.issuedMonth = bibYear(incoming.issuedMonth, existing.issuedMonth)
        merged.issuedDay = bibYear(incoming.issuedDay, existing.issuedDay)
        merged.translators = bibField(incoming.translators, existing.translators)
        merged.eventTitle = bibField(incoming.eventTitle, existing.eventTitle)
        merged.eventPlace = bibField(incoming.eventPlace, existing.eventPlace)
        merged.genre = bibField(incoming.genre, existing.genre)
        merged.institution = bibField(incoming.institution, existing.institution)
        merged.number = bibField(incoming.number, existing.number)
        merged.collectionTitle = bibField(incoming.collectionTitle, existing.collectionTitle)
        merged.numberOfPages = bibField(incoming.numberOfPages, existing.numberOfPages)
        merged.language = bibField(incoming.language, existing.language)
        merged.pmid = bibField(incoming.pmid, existing.pmid)
        merged.pmcid = bibField(incoming.pmcid, existing.pmcid)
        merged.dateAdded = existing.dateAdded
        merged.dateModified = Date()
        return merged
    }
}
