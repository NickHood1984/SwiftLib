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
        includeCrossRef: Bool = true
    ) async -> FetchResult {
        // Use withTaskGroup instead of async let: async let inside an actor crashes
        // on swift_task_dealloc when the parent task is cancelled externally.
        enum DOIFetchOutput: @unchecked Sendable {
            case crossRef(Reference?)
            case openAlex((Reference, MetadataFetcher.OpenAlexEnrichment)?)
            case s2(MetadataFetcher.S2PaperResult?)
        }
        var crossRef: Reference?
        var openAlexPair: (Reference, MetadataFetcher.OpenAlexEnrichment)?
        var s2Paper: MetadataFetcher.S2PaperResult?

        await withTaskGroup(of: DOIFetchOutput.self) { group in
            if includeCrossRef {
                group.addTask { .crossRef(try? await MetadataFetcher.fetchFromDOI(doi, forceRefresh: forceRefresh)) }
            }
            group.addTask { .openAlex(await MetadataFetcher.fetchFullFromOpenAlex(doi: doi)) }
            group.addTask { .s2(await MetadataFetcher.fetchFromSemanticScholar(doi: doi)) }
            for await output in group {
                switch output {
                case .crossRef(let r): crossRef = r
                case .openAlex(let r): openAlexPair = r
                case .s2(let r): s2Paper = r
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
        includeCrossRef: Bool = true
    ) async -> FetchResult {
        // Use withTaskGroup instead of async let: async let inside an actor crashes
        // on swift_task_dealloc when the parent task is cancelled externally.
        enum TitleFetchOutput: @unchecked Sendable {
            case openAlex((Reference, MetadataFetcher.OpenAlexEnrichment)?)
            case s2(MetadataFetcher.S2PaperResult?)
        }
        var openAlexPair: (Reference, MetadataFetcher.OpenAlexEnrichment)?
        var s2Paper: MetadataFetcher.S2PaperResult?

        await withTaskGroup(of: TitleFetchOutput.self) { group in
            group.addTask { .openAlex(await MetadataFetcher.fetchFullFromOpenAlex(title: title)) }
            group.addTask { .s2(await MetadataFetcher.searchSemanticScholar(title: title)) }
            for await output in group {
                switch output {
                case .openAlex(let r): openAlexPair = r
                case .s2(let r): s2Paper = r
                }
            }
        }

        var results: [SourceResult] = []
        var discoveredDOI: String?

        if let (ref, enrichment) = openAlexPair {
            results.append(SourceResult(source: .openAlex, reference: ref, enrichment: enrichment))
            if let doi = ref.doi, !doi.isEmpty { discoveredDOI = doi }
        }
        if let paper = s2Paper {
            // Verify title similarity before accepting S2 result
            let score = MetadataResolution.titleSimilarity(title, paper.title)
            if score >= 0.55 {
                let ref = MetadataFetcher.referenceFromS2(paper)
                results.append(SourceResult(source: .semanticScholar, reference: ref, s2Paper: paper))
                if discoveredDOI == nil, let doi = paper.externalIds?.doi, !doi.isEmpty {
                    discoveredDOI = doi
                }
            }
        }

        // If we discovered a DOI from title search, follow up with CrossRef
        if includeCrossRef, let doi = discoveredDOI {
            if let crossRef = try? await MetadataFetcher.fetchFromDOI(doi, forceRefresh: forceRefresh) {
                results.append(SourceResult(source: .crossRef, reference: crossRef))
            }
        }

        return FetchResult(sources: results, discoveredDOI: discoveredDOI)
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
