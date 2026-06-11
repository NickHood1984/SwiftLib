import Foundation

/// Parallel multi-source metadata fetcher.
/// Queries CrossRef, OpenAlex, and Semantic Scholar concurrently,
/// then feeds results to FieldLevelMerger for confidence-based merging.
public actor ParallelSourceFetcher {

    public static let shared = ParallelSourceFetcher()

    /// A single source's fetch result.
    public struct SourceResult: Sendable {
        public var source: MetadataSource
        public var reference: Reference
        public var enrichment: MetadataFetcher.OpenAlexEnrichment?
        public var s2Paper: MetadataFetcher.S2PaperResult?

        public init(source: MetadataSource, reference: Reference,
                     enrichment: MetadataFetcher.OpenAlexEnrichment? = nil,
                     s2Paper: MetadataFetcher.S2PaperResult? = nil) {
            self.source = source
            self.reference = reference
            self.enrichment = enrichment
            self.s2Paper = s2Paper
        }
    }

    /// Combined output from all parallel sources.
    public struct FetchResult: Sendable {
        public var sources: [SourceResult]
        /// Best DOI discovered across all sources (for further lookups).
        public var discoveredDOI: String?

        public init(sources: [SourceResult], discoveredDOI: String?) {
            self.sources = sources
            self.discoveredDOI = discoveredDOI
        }
    }

    // MARK: - Per-source soft deadline

    /// Maximum time any single source may delay the combined result.
    ///
    /// Without this, the task group waits for the SLOWEST source: a 429-retry
    /// chain against Semantic Scholar (3s/6s/12s backoff × 10s timeouts) can
    /// stall a refresh for 30–40s even though CrossRef answered in under a
    /// second. When the deadline fires we cancel the stragglers and merge
    /// whatever already arrived — losing at worst some enrichment fields,
    /// never the primary bibliographic record.
    public static let defaultSourceDeadline: TimeInterval = 15

    // MARK: - DOI-based parallel fetch

    /// Fetch from all sources in parallel when DOI is available.
    /// `forceRefresh: true` bypasses CrossRef/OpenAlex/S2 caches so the user's
    /// explicit "Refresh Metadata" action actually re-hits the network.
    /// OpenAlex/S2 are view-only networks without caller-side cache, so
    /// forceRefresh only changes CrossRef behavior today but the signature
    /// propagates correctly if caches are added there later.
    public func fetchByDOI(
        _ doi: String,
        forceRefresh: Bool = false,
        includeCrossRef: Bool = true,
        sourceDeadline: TimeInterval = ParallelSourceFetcher.defaultSourceDeadline
    ) async -> FetchResult {
        // Use withTaskGroup instead of async let: async let inside an actor crashes
        // on swift_task_dealloc when the parent task is cancelled externally.
        enum DOIFetchOutput: @unchecked Sendable {
            case crossRef(Reference?)
            case openAlex((Reference, MetadataFetcher.OpenAlexEnrichment)?)
            case s2(MetadataFetcher.S2PaperResult?)
            case deadline
        }
        var crossRef: Reference?
        var openAlexPair: (Reference, MetadataFetcher.OpenAlexEnrichment)?
        var s2Paper: MetadataFetcher.S2PaperResult?

        await withTaskGroup(of: DOIFetchOutput.self) { group in
            var expected = 2
            if includeCrossRef {
                expected += 1
                group.addTask { .crossRef(try? await MetadataFetcher.fetchFromDOI(doi, forceRefresh: forceRefresh)) }
            }
            group.addTask { .openAlex(await MetadataFetcher.fetchFullFromOpenAlex(doi: doi)) }
            group.addTask { .s2(await MetadataFetcher.fetchFromSemanticScholar(doi: doi)) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(sourceDeadline, 1) * 1_000_000_000))
                return .deadline
            }
            var received = 0
            for await output in group {
                switch output {
                case .deadline:
                    // Stragglers past the deadline: cancel and proceed with
                    // whatever already arrived.
                    group.cancelAll()
                case .crossRef(let r): crossRef = r; received += 1
                case .openAlex(let r): openAlexPair = r; received += 1
                case .s2(let r): s2Paper = r; received += 1
                }
                if received == expected {
                    group.cancelAll() // all real sources done — stop the deadline timer
                }
            }
        }

        var results: [SourceResult] = []
        if let ref = crossRef {
            results.append(SourceResult(source: .crossRef, reference: ref))
        }
        if let (ref, enrichment) = openAlexPair {
            results.append(SourceResult(source: .openAlex, reference: ref, enrichment: enrichment))
        }
        if let paper = s2Paper {
            let ref = MetadataFetcher.referenceFromS2(paper)
            results.append(SourceResult(source: .semanticScholar, reference: ref, s2Paper: paper))
        }
        return FetchResult(sources: results, discoveredDOI: doi)
    }

    // MARK: - Title-based parallel fetch

    /// Fetch from all sources by title when no DOI is available.
    /// Uses S2 match + OpenAlex search in parallel, then if a DOI is discovered,
    /// optionally follows up with CrossRef.
    public func fetchByTitle(
        _ title: String,
        forceRefresh: Bool = false,
        includeCrossRef: Bool = true,
        sourceDeadline: TimeInterval = ParallelSourceFetcher.defaultSourceDeadline
    ) async -> FetchResult {
        // Use withTaskGroup instead of async let: async let inside an actor crashes
        // on swift_task_dealloc when the parent task is cancelled externally.
        enum TitleFetchOutput: @unchecked Sendable {
            case openAlex((Reference, MetadataFetcher.OpenAlexEnrichment)?)
            case s2(MetadataFetcher.S2PaperResult?)
            case deadline
        }
        var openAlexPair: (Reference, MetadataFetcher.OpenAlexEnrichment)?
        var s2Paper: MetadataFetcher.S2PaperResult?

        await withTaskGroup(of: TitleFetchOutput.self) { group in
            group.addTask { .openAlex(await MetadataFetcher.fetchFullFromOpenAlex(title: title)) }
            group.addTask { .s2(await MetadataFetcher.searchSemanticScholar(title: title)) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(sourceDeadline, 1) * 1_000_000_000))
                return .deadline
            }
            var received = 0
            for await output in group {
                switch output {
                case .deadline:
                    group.cancelAll()
                case .openAlex(let r): openAlexPair = r; received += 1
                case .s2(let r): s2Paper = r; received += 1
                }
                if received == 2 {
                    group.cancelAll() // both sources done — stop the deadline timer
                }
            }
        }

        var results: [SourceResult] = []
        var discoveredDOI: String?
        var discoveredDOIScore = 0.0

        if let (ref, enrichment) = openAlexPair {
            results.append(SourceResult(source: .openAlex, reference: ref, enrichment: enrichment))
            if let doi = ref.doi, !doi.isEmpty {
                discoveredDOI = doi
                // fetchFullFromOpenAlex already gated this row by title
                // similarity; recompute the exact score so DOI conflicts
                // between sources can be resolved by match strength.
                discoveredDOIScore = MetadataResolution.titleSimilarity(title, ref.title)
            }
        }
        if let paper = s2Paper {
            // Verify title similarity before accepting S2 result
            let score = MetadataResolution.titleSimilarity(title, paper.title)
            if score >= 0.55 {
                let ref = MetadataFetcher.referenceFromS2(paper)
                results.append(SourceResult(source: .semanticScholar, reference: ref, s2Paper: paper))
                if let doi = paper.externalIds?.doi, !doi.isEmpty,
                   discoveredDOI == nil || score > discoveredDOIScore {
                    // On DOI disagreement, trust the source whose title matches
                    // the query more strongly.
                    discoveredDOI = doi
                    discoveredDOIScore = score
                }
            }
        }

        // If we discovered a DOI from title search, follow up with CrossRef
        if includeCrossRef, let doi = discoveredDOI {
            if let crossRef = try? await MetadataFetcher.fetchFromDOI(doi, forceRefresh: forceRefresh) {
                // The DOI came from a title search, so verify it: CrossRef is
                // authoritative for what a DOI actually refers to. If its
                // record clearly doesn't match the query title, the discovered
                // DOI was wrong — without this gate the mismatched CrossRef
                // record would win FieldLevelMerger's top priority and
                // overwrite title/authors with a different paper entirely.
                let crossRefScore = MetadataResolution.titleSimilarity(title, crossRef.title)
                if crossRefScore >= 0.55 {
                    results.append(SourceResult(source: .crossRef, reference: crossRef))
                } else {
                    // Disproven DOI: drop it from the combined result and scrub
                    // it from any source reference that carried it, so the
                    // merge cannot propagate the wrong identifier.
                    discoveredDOI = nil
                    results = Self.scrubbingDisprovenDOI(doi, from: results)
                }
            }
        }

        return FetchResult(sources: results, discoveredDOI: discoveredDOI)
    }

    /// Remove a DOI that CrossRef has disproven (its record doesn't match the
    /// query title) from every source reference that carried it.
    /// Pure helper — extracted for unit testing.
    static func scrubbingDisprovenDOI(_ doi: String, from results: [SourceResult]) -> [SourceResult] {
        let badDOI = doi.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return results.map { sourceResult in
            var scrubbed = sourceResult
            if scrubbed.reference.doi?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == badDOI {
                scrubbed.reference.doi = nil
            }
            return scrubbed
        }
    }

    // MARK: - Identifier-based fetch

    /// Fetch by any identifier type, delegating to the appropriate API first,
    /// then supplementing with parallel enrichment sources.
    public func fetchByIdentifier(
        _ identifier: MetadataFetcher.Identifier,
        forceRefresh: Bool = false,
        includeCrossRef: Bool = true
    ) async -> FetchResult {
        switch identifier {
        case .doi(let doi):
            return await fetchByDOI(doi, forceRefresh: forceRefresh, includeCrossRef: includeCrossRef)

        case .pmid(let pmid):
            var results: [SourceResult] = []
            if let ref = try? await MetadataFetcher.fetchFromPMID(pmid, forceRefresh: forceRefresh) {
                results.append(SourceResult(source: .pubMed, reference: ref))
                // If PubMed gave us a DOI, enrich from OpenAlex + S2
                if let doi = ref.doi, !doi.isEmpty {
                    let enrichResult = await fetchByDOI(doi, forceRefresh: forceRefresh, includeCrossRef: includeCrossRef)
                    results.append(contentsOf: enrichResult.sources)
                    return FetchResult(sources: results, discoveredDOI: doi)
                }
            }
            return FetchResult(sources: results, discoveredDOI: nil)

        case .arxiv(let arxivId):
            var results: [SourceResult] = []
            if let ref = try? await MetadataFetcher.fetchFromArXiv(arxivId, forceRefresh: forceRefresh) {
                results.append(SourceResult(source: .arXiv, reference: ref))
                // arXiv often links to a DOI
                if let doi = ref.doi, !doi.isEmpty {
                    let enrichResult = await fetchByDOI(doi, forceRefresh: forceRefresh, includeCrossRef: includeCrossRef)
                    results.append(contentsOf: enrichResult.sources)
                    return FetchResult(sources: results, discoveredDOI: doi)
                }
            }
            return FetchResult(sources: results, discoveredDOI: nil)

        case .isbn(let isbn):
            var results: [SourceResult] = []
            if includeCrossRef, let ref = try? await MetadataFetcher.fetchFromISBN(isbn, forceRefresh: forceRefresh) {
                results.append(SourceResult(source: .crossRef, reference: ref))
            }
            return FetchResult(sources: results, discoveredDOI: nil)
        }
    }
}
