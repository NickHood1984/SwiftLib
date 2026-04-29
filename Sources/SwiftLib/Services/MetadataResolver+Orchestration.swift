import Foundation
import SwiftLibCore

extension MetadataResolver {
    func resolveTitleSeedThroughParallelSources(
        _ seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> MetadataResolutionResult? {
        guard let title = seed.title?.swiftlib_nilIfBlank else { return nil }
        guard !MetadataRoutePlanner.isBookLike(seed) else { return nil }
        guard !seed.shouldSearchCNKI else { return nil }

        resolverTrace("resolveTitleSeedThroughParallelSources → 标题并发抓取: \(title)")
        let fetchResult = await ParallelSourceFetcher.shared.fetchByTitle(title)
        guard !fetchResult.sources.isEmpty else {
            resolverTrace("resolveTitleSeedThroughParallelSources → 无可用源")
            return nil
        }

        return await resolveParallelFetchResult(
            fetchResult,
            seed: seed,
            fallback: fallback,
            fetchMode: .searchToDetail,
            exactIdentifierMatch: false,
            defaultRejectMessage: "标题搜索命中，但仍未满足自动验证规则。"
        )
    }

    func resolveParallelFetchResult(
        _ fetchResult: ParallelSourceFetcher.FetchResult,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        fetchMode: FetchMode,
        exactIdentifierMatch: Bool,
        defaultRejectMessage: String
    ) async -> MetadataResolutionResult {
        guard !fetchResult.sources.isEmpty else {
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: "未从并发源获得可用元数据。"
                )
            )
        }

        let base = fallback ?? Reference(title: seed?.title ?? "Untitled")
        let (merged, enrichment) = FieldLevelMerger.merge(sources: fetchResult.sources, existing: base)

        var reference = fallback.map {
            MetadataResolution.mergeReference(primary: merged, fallback: $0)
        } ?? merged
        reference = MetadataResolution.applyEnrichment(enrichment, to: reference)

        // easyScholar journal-rank enrichment
        let secretKey = SwiftLibPreferences.easyScholarSecretKey
        if !secretKey.isEmpty, let journal = reference.journal, !journal.isEmpty {
            let rankResponse = await MetadataFetcher.enrichWithEasyScholar(journal: journal, secretKey: secretKey)
            reference = MetadataResolution.applyEasyScholarEnrichment(rankResponse, to: reference)
        }

        reference = await mergeChineseConsensusIfAvailable(
            primary: reference,
            seed: seed,
            fallback: fallback,
            fetchResult: fetchResult
        )

        // Enrich seed with discovered identifiers from the fetched reference.
        // When the user searches by title or enters a bare DOI string, the
        // upstream seed may be nil or may lack identifiers.  The verifier
        // compares seed vs. reference to decide whether the fetched record
        // matches the user's intent; if the seed is empty the match always
        // fails (even though the reference itself carries a DOI from the
        // authoritative source).  Back-filling from the reference lets the
        // verifier treat "whatever the source returned" as the user's implicit
        // expectation when no explicit value was provided.
        var enrichedSeed = seed
        if enrichedSeed == nil {
            enrichedSeed = MetadataResolutionSeed.fromReference(reference)
        } else {
            if enrichedSeed?.doi == nil, let doi = reference.doi?.swiftlib_nilIfBlank {
                enrichedSeed?.doi = doi
            }
            if enrichedSeed?.isbn == nil, let isbn = reference.isbn?.swiftlib_nilIfBlank {
                enrichedSeed?.isbn = isbn
            }
            if enrichedSeed?.year == nil, let year = reference.year {
                enrichedSeed?.year = year
            }
            if enrichedSeed?.journal == nil, let journal = reference.journal?.swiftlib_nilIfBlank {
                enrichedSeed?.journal = journal
            }
            if enrichedSeed?.firstAuthor == nil, let firstAuthor = reference.authors.first?.displayName.swiftlib_nilIfBlank {
                enrichedSeed?.firstAuthor = firstAuthor
            }
        }

        let evidence = buildParallelEvidence(
            for: reference,
            sources: fetchResult.sources,
            fetchMode: fetchMode,
            exactIdentifierMatch: exactIdentifierMatch,
            discoveredDOI: fetchResult.discoveredDOI
        )

        let record = AuthoritativeMetadataRecord(reference: reference, evidence: evidence)
        let result = verifyFetchedRecord(
            record,
            seed: enrichedSeed,
            fallback: fallback,
            defaultRejectMessage: defaultRejectMessage
        )

        if case .rejected(let envelope) = result,
           let staged = promoteRejectedRecordToInlineImport(
            reference: envelope.currentReference ?? reference,
            evidence: envelope.evidence ?? evidence,
            sourceCount: fetchResult.sources.count,
            exactIdentifierMatch: exactIdentifierMatch
           ) {
            return staged
        }

        return result
    }

    func mergeChineseConsensusIfAvailable(
        primary: Reference,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        fetchResult: ParallelSourceFetcher.FetchResult
    ) async -> Reference {
        guard let seed,
              seed.shouldSearchCNKI,
              !MetadataRoutePlanner.isBookLike(seed) else {
            return primary
        }

        let hasHanSeed = MetadataResolution.containsHanCharacters(seed.title)
            || MetadataResolution.containsHanCharacters(primary.title)
        guard hasHanSeed else { return primary }

        let correction = await resolveCNKISeed(seed, fallback: fallback, forceSearch: true)
        guard case .verified(let cnkiEnvelope) = correction else {
            return primary
        }

        var contributions = ChineseMetadataConsensus.makeContributions(
            seed: seed,
            sources: fetchResult.sources.map { ($0.source, $0.reference) }
        )
        contributions.append(
            contentsOf: ChineseMetadataConsensus.makeContributions(
                seed: seed,
                sources: [(.cnki, cnkiEnvelope.reference)]
            )
        )

        guard let consensus = ChineseMetadataConsensus.buildConsensus(seed: seed, contributions: contributions) else {
            return primary
        }

        resolverTrace("mergeChineseConsensusIfAvailable → 已融合 CNKI + 并发源字段共识")
        return MetadataResolution.mergeReference(primary: consensus, fallback: primary)
    }

    nonisolated func buildParallelEvidence(
        for reference: Reference,
        sources: [ParallelSourceFetcher.SourceResult],
        fetchMode: FetchMode,
        exactIdentifierMatch: Bool,
        discoveredDOI: String?
    ) -> EvidenceBundle {
        let sourcePriority: [MetadataSource] = [.crossRef, .pubMed, .openAlex, .semanticScholar, .arXiv, .cnki]
        let primarySource = sources
            .sorted { lhs, rhs in
                let li = sourcePriority.firstIndex(of: lhs.source) ?? sourcePriority.count
                let ri = sourcePriority.firstIndex(of: rhs.source) ?? sourcePriority.count
                return li < ri
            }
            .first?.source ?? reference.metadataSource ?? .translationServer

        let origin: EvidenceOrigin
        switch fetchMode {
        case .detail:
            origin = .structuredDetail
        case .export:
            origin = .structuredExport
        case .searchToDetail:
            origin = .searchResult
        case .manual:
            origin = .manual
        default:
            origin = .identifierAPI
        }

        var fieldEvidence: [FieldEvidence] = []
        for result in sources {
            let ref = result.reference
            fieldEvidence.append(FieldEvidence(field: "title", value: ref.title, origin: origin, selectorOrPath: result.source.rawValue))
            if !ref.authors.isEmpty {
                fieldEvidence.append(FieldEvidence(field: "authors", value: ref.authors.displayString, origin: origin, selectorOrPath: result.source.rawValue))
            }
            if let year = ref.year {
                fieldEvidence.append(FieldEvidence(field: "year", value: String(year), origin: origin, selectorOrPath: result.source.rawValue))
            }
            if let journal = ref.journal?.swiftlib_nilIfBlank {
                fieldEvidence.append(FieldEvidence(field: "journal", value: journal, origin: origin, selectorOrPath: result.source.rawValue))
            }
            if let doi = ref.doi?.swiftlib_nilIfBlank {
                fieldEvidence.append(FieldEvidence(field: "doi", value: doi, origin: origin, selectorOrPath: result.source.rawValue))
            }
            if let publisher = ref.publisher?.swiftlib_nilIfBlank {
                fieldEvidence.append(FieldEvidence(field: "publisher", value: publisher, origin: origin, selectorOrPath: result.source.rawValue))
            }
        }

        let recordKey = discoveredDOI?.swiftlib_nilIfBlank
            ?? reference.doi?.swiftlib_nilIfBlank
            ?? reference.pmid?.swiftlib_nilIfBlank
            ?? reference.isbn?.swiftlib_nilIfBlank

        return EvidenceBundle(
            source: primarySource,
            recordKey: recordKey,
            sourceURL: reference.url,
            fetchMode: fetchMode,
            fieldEvidence: fieldEvidence,
            verificationHints: VerificationHints(
                hasStructuredTitle: reference.title.swiftlib_nilIfBlank != nil,
                hasStructuredAuthors: !reference.authors.isEmpty,
                hasStructuredJournal: reference.journal?.swiftlib_nilIfBlank != nil,
                hasStructuredInstitution: reference.institution?.swiftlib_nilIfBlank != nil,
                hasStructuredPages: reference.pages?.swiftlib_nilIfBlank != nil,
                hasStructuredThesisType: reference.genre?.swiftlib_nilIfBlank != nil,
                hasStableRecordKey: recordKey?.swiftlib_nilIfBlank != nil,
                usedStructuredExport: fetchMode == .export,
                usedStructuredDetail: fetchMode == .detail,
                usedIdentifierFetch: exactIdentifierMatch || fetchMode == .identifier,
                exactIdentifierMatch: exactIdentifierMatch,
                competingCandidateCount: 0,
                hasFundingInfo: reference.fundingInfo?.swiftlib_nilIfBlank != nil,
                hasKeywords: reference.keywords?.swiftlib_nilIfBlank != nil,
                hasOaStatus: reference.isOpenAccess != nil || reference.oaUrl?.swiftlib_nilIfBlank != nil,
                hasTopics: reference.topics?.swiftlib_nilIfBlank != nil
            ),
            enrichmentSources: Array(Set(sources.map(\.source))).sorted { $0.rawValue < $1.rawValue },
            confidenceScore: reference.confidenceScore,
            keywords: MetadataVerificationCodec.decodeFromJSONString(reference.keywords, as: [String].self),
            topics: MetadataVerificationCodec.decodeFromJSONString(reference.topics, as: [String].self),
            isOpenAccess: reference.isOpenAccess,
            oaUrl: reference.oaUrl,
            fundingInfo: MetadataVerificationCodec.decodeFromJSONString(reference.fundingInfo, as: [String].self),
            citedByCount: reference.citedByCount
        )
    }

    nonisolated func promoteRejectedRecordToInlineImport(
        reference: Reference,
        evidence: EvidenceBundle,
        sourceCount: Int,
        exactIdentifierMatch: Bool
    ) -> MetadataResolutionResult? {
        let titleReady = reference.title.swiftlib_nilIfBlank != nil
        let authorsReady = !reference.authors.isEmpty
        let publicationReady = reference.year != nil
            || reference.journal?.swiftlib_nilIfBlank != nil
            || reference.publisher?.swiftlib_nilIfBlank != nil
        let identifierReady = reference.doi?.swiftlib_nilIfBlank != nil
            || reference.isbn?.swiftlib_nilIfBlank != nil
            || reference.pmid?.swiftlib_nilIfBlank != nil
        let structuredSignal = evidence.verificationHints.usedStructuredDetail
            || evidence.verificationHints.usedStructuredExport
            || evidence.verificationHints.usedIdentifierFetch
            || sourceCount >= 2
            || exactIdentifierMatch
        let confidence = max(reference.confidenceScore ?? 0, evidence.confidenceScore ?? 0)

        guard titleReady, structuredSignal else { return nil }
        guard identifierReady || (authorsReady && publicationReady) else { return nil }
        guard exactIdentifierMatch || evidence.verificationHints.usedStructuredExport || confidence >= 0.58 || sourceCount >= 2 else {
            return nil
        }

        // 英文文献必须有 DOI 才能被挽救为 verified；否则保持未验证（黄色）。
        // 中文文献不受此限制（知网等中文源可能没有 DOI）。
        let isChinese = MetadataResolution.containsHanCharacters(reference.title)
            || evidence.source == .cnki
            || evidence.source == .wanfang
            || evidence.source == .vip
        if !isChinese, reference.doi?.swiftlib_nilIfBlank == nil {
            resolverTrace("promoteRejectedRecordToInlineImport → 英文文献无 DOI，不挽救为补全中 title=\"\(reference.title)\"")
            return nil
        }

        var staged = reference
        staged.verificationStatus = .metadataEnriching
        staged.acceptedByRuleID = nil
        staged.recordKey = evidence.recordKey?.swiftlib_nilIfBlank ?? staged.recordKey
        staged.verificationSourceURL = evidence.sourceURL?.swiftlib_nilIfBlank ?? staged.verificationSourceURL
        staged.metadataSource = evidence.source
        staged.evidenceBundleHash = evidence.bundleHash ?? staged.evidenceBundleHash
        staged.verifiedAt = Date()
        staged.confidenceScore = confidence > 0 ? confidence : staged.confidenceScore

        resolverTrace("promoteRejectedRecordToInlineImport → 直接入库并标记为补全中 title=\"\(staged.title)\"")
        return .verified(VerifiedEnvelope(reference: staged, evidence: evidence))
    }
}
