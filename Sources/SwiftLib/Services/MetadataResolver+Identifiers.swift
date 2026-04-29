import Foundation
import SwiftLibCore

// MARK: - Identifier Resolution, Verification, Evidence & Helpers

extension MetadataResolver {

    // MARK: Verification

    nonisolated func verifyFetchedRecord(
        _ record: AuthoritativeMetadataRecord,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        defaultRejectMessage: String
    ) -> MetadataResolutionResult {
        let decision = MetadataVerifier.verify(reference: record.reference, seed: seed, evidence: record.evidence)
        switch decision {
        case .verified(let envelope):
            let mergedReference = fallback.map { MetadataResolution.mergeReference(primary: envelope.reference, fallback: $0) } ?? envelope.reference
            return .verified(VerifiedEnvelope(reference: mergedReference, evidence: envelope.evidence))

        case .candidate(let envelope):
            let current = fallback.map { MetadataResolution.mergeReference(primary: envelope.currentReference ?? record.reference, fallback: $0) }
                ?? envelope.currentReference
                ?? record.reference
            return .candidate(
                CandidateEnvelope(
                    seed: seed ?? envelope.seed,
                    fallbackReference: fallback ?? envelope.fallbackReference,
                    currentReference: current,
                    candidates: envelope.candidates,
                    message: envelope.message,
                    evidence: envelope.evidence ?? record.evidence
                )
            )

        case .blocked(let envelope):
            return .blocked(
                BlockedEnvelope(
                    seed: seed ?? envelope.seed,
                    fallbackReference: fallback ?? envelope.fallbackReference,
                    currentReference: envelope.currentReference ?? record.reference,
                    candidates: envelope.candidates,
                    reason: envelope.reason,
                    message: envelope.message,
                    evidence: envelope.evidence ?? record.evidence
                )
            )

        case .rejected(let envelope):
            let mergedCurrent = fallback.map { MetadataResolution.mergeReference(primary: envelope.currentReference ?? record.reference, fallback: $0) }
                ?? envelope.currentReference
                ?? record.reference
            return .rejected(
                RejectedEnvelope(
                    seed: seed ?? envelope.seed,
                    fallbackReference: fallback ?? envelope.fallbackReference,
                    currentReference: mergedCurrent,
                    reason: envelope.reason,
                    message: envelope.message.isEmpty ? defaultRejectMessage : envelope.message,
                    evidence: envelope.evidence ?? record.evidence
                )
            )
        }
    }

    nonisolated func blockedOrRejectedResult(
        error: CNKIMetadataProvider.CNKIError,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        message: String
    ) -> MetadataResolutionResult {
        switch error {
        case .blockedByVerification:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .verificationRequired,
                    message: message
                )
            )
        case .verificationCancelled:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .verificationRequired,
                    message: message
                )
            )
        case .timedOut:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .timedOut,
                    message: message
                )
            )
        default:
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: message
                )
            )
        }
    }

    // MARK: Identifier Resolution

    nonisolated func resolveIdentifierValue(
        _ rawIdentifier: String,
        as identifier: MetadataFetcher.Identifier,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        existingReference: Reference?
    ) async -> MetadataResolutionResult {
        resolverTrace("resolveIdentifierValue 标识符=\"\(rawIdentifier)\" -> 本地标识符解析")
        return await resolveIdentifierLocally(identifier, seed: seed, fallback: fallback)
    }

    nonisolated func resolveIdentifierLocally(
        _ identifier: MetadataFetcher.Identifier,
        seed: MetadataResolutionSeed?,
        fallback: Reference?
    ) async -> MetadataResolutionResult {
        resolverTrace("resolveIdentifierLocally -> \(String(describing: identifier))")
        let fetchResult = await ParallelSourceFetcher.shared.fetchByIdentifier(identifier)
        guard !fetchResult.sources.isEmpty else {
            resolverTrace("resolveIdentifierLocally failed: 所有并发源均无结果")
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: "未从标识符源获得可用元数据。"
                )
            )
        }

        return await self.resolveParallelFetchResult(
            fetchResult,
            seed: seed,
            fallback: fallback,
            fetchMode: .identifier,
            exactIdentifierMatch: true,
            defaultRejectMessage: "标识符命中，但仍未满足自动验证规则。"
        )
    }

    // MARK: Evidence Building

    nonisolated func buildGenericEvidence(
        for reference: Reference,
        source: MetadataSource,
        fetchMode: FetchMode,
        origin: EvidenceOrigin,
        recordKey: String?,
        exactIdentifierMatch: Bool
    ) -> EvidenceBundle {
        var fields: [FieldEvidence] = [FieldEvidence(field: "title", value: reference.title, origin: origin)]
        if !reference.authors.isEmpty {
            fields.append(FieldEvidence(field: "authors", value: reference.authors.displayString, origin: origin))
        }
        if let year = reference.year {
            fields.append(FieldEvidence(field: "year", value: String(year), origin: origin))
        }
        if let journal = reference.journal?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "journal", value: journal, origin: origin))
        }
        if let pages = reference.pages?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "pages", value: pages, origin: origin))
        }
        if let doi = reference.doi?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "doi", value: doi, origin: origin))
        }
        if let isbn = reference.isbn?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "isbn", value: isbn, origin: origin))
        }
        if let institution = reference.institution?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "institution", value: institution, origin: origin))
        }
        if let thesisType = reference.genre?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "thesisType", value: thesisType, origin: origin))
        }

        return EvidenceBundle(
            source: source,
            recordKey: recordKey,
            sourceURL: reference.url,
            fetchMode: fetchMode,
            fieldEvidence: fields,
            verificationHints: VerificationHints(
                hasStructuredTitle: !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasStructuredAuthors: !reference.authors.isEmpty,
                hasStructuredJournal: reference.journal?.swiftlib_nilIfBlank != nil,
                hasStructuredInstitution: reference.institution?.swiftlib_nilIfBlank != nil,
                hasStructuredPages: reference.pages?.swiftlib_nilIfBlank != nil,
                hasStructuredThesisType: reference.genre?.swiftlib_nilIfBlank != nil,
                hasStableRecordKey: recordKey?.swiftlib_nilIfBlank != nil,
                usedStructuredExport: fetchMode == .export,
                usedStructuredDetail: fetchMode == .detail,
                usedIdentifierFetch: fetchMode == .identifier,
                exactIdentifierMatch: exactIdentifierMatch
            )
        )
    }

    // MARK: Debug Labels

    nonisolated func debugLabel(for result: MetadataResolutionResult) -> String {
        switch result {
        case .verified(let envelope):
            return "verified(title=\"\(envelope.reference.title)\")"
        case .candidate(let envelope):
            let count = envelope.candidates.count
            let title = envelope.currentReference?.title ?? envelope.candidates.first?.title ?? "(无)"
            return "candidate(count=\(count), title=\"\(title)\")"
        case .blocked(let envelope):
            return "blocked(reason=\(envelope.reason.rawValue), message=\"\(envelope.message)\")"
        case .seedOnly(let envelope):
            return "seedOnly(message=\"\(envelope.message)\")"
        case .rejected(let envelope):
            return "rejected(reason=\(envelope.reason.rawValue), message=\"\(envelope.message)\")"
        }
    }

    nonisolated func debugLabel(for result: ReferenceMetadataRefreshResult) -> String {
        switch result {
        case .refreshed(let reference):
            return "refreshed(title=\"\(reference.title)\")"
        case .pending(let resolution):
            return "pending(\(debugLabel(for: resolution)))"
        case .skipped(let message):
            return "skipped(message=\"\(message)\")"
        case .failed(let message):
            return "failed(message=\"\(message)\")"
        }
    }

    // MARK: Correction Seed

    nonisolated static func correctionSeed(
        for reference: Reference,
        preferredSeed: MetadataResolutionSeed?,
        inputURL: URL?
    ) -> MetadataResolutionSeed {
        var seed = preferredSeed ?? MetadataResolutionSeed.fromReference(reference)
        if seed.sourceURL == nil {
            seed.sourceURL = inputURL?.absoluteString ?? reference.url
        }
        if seed.doi == nil {
            seed.doi = reference.doi?.swiftlib_nilIfBlank
        }
        if seed.title == nil || !MetadataResolution.containsHanCharacters(seed.title) {
            let chineseTitle = reference.title.swiftlib_nilIfBlank
            if MetadataResolution.containsHanCharacters(chineseTitle) {
                seed.title = chineseTitle
            }
        }
        if seed.journal == nil || !MetadataResolution.containsHanCharacters(seed.journal) {
            let chineseJournal = reference.journal.swiftlib_nilIfBlank
            if MetadataResolution.containsHanCharacters(chineseJournal) {
                seed.journal = chineseJournal
            }
        }

        if !MetadataResolution.containsHanCharacters(seed.title),
           let doi = seed.doi?.swiftlib_nilIfBlank {
            seed.title = nil
            seed.fileName = doi
        }

        let preferredAuthor = reference.authors.first?.displayName.swiftlib_nilIfBlank
        if MetadataResolution.containsHanCharacters(seed.firstAuthor) == false {
            seed.firstAuthor = MetadataResolution.containsHanCharacters(preferredAuthor) ? preferredAuthor : nil
        }

        seed.languageHint = .chinese
        return seed
    }

    // MARK: Utilities

    nonisolated func identifierString(_ identifier: MetadataFetcher.Identifier) -> String {
        switch identifier {
        case .doi(let value), .pmid(let value), .arxiv(let value), .isbn(let value):
            return value
        }
    }

    nonisolated func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated func normalizedHTTPURL(from value: String?) -> URL? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    nonisolated func isCNKIURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return MetadataResolution.metadataSource(for: url.absoluteString, fallback: .translationServer) == .cnki
    }
}
