import Foundation

/// Multi-source consensus engine for Chinese academic metadata.
///
/// When multiple sources (CNKI, Wanfang, VIP, CrossRef, OpenAlex) return metadata
/// for the same work, this engine merges them using field-level voting and
/// source-priority weighting to produce the most accurate composite Reference.
public enum ChineseMetadataConsensus {

    /// A metadata contribution from a single source.
    public struct SourceContribution: Sendable {
        public let source: MetadataSource
        public let reference: Reference
        public let titleScore: Double // similarity to seed title
        public let priority: Int // lower = more authoritative
    }

    /// Source priority ranking for Chinese metadata.
    /// Lower values = higher priority.
    private static func sourcePriority(_ source: MetadataSource) -> Int {
        switch source {
        case .cnki: return 1
        case .wanfang: return 2
        case .vip: return 3
        case .crossRef: return 4
        case .openAlex: return 5
        default: return 10
        }
    }

    /// Build a consensus Reference from multiple source contributions.
    ///
    /// Strategy:
    /// 1. **Chinese-text fields** (title, journal, abstract): prefer Chinese database sources
    /// 2. **Structured fields** (DOI, year, pages, volume, issue): prefer the highest-priority source with non-empty value
    /// 3. **Enrichment fields** (keywords, OA status, citations): merge from any available source
    /// 4. **Authors**: prefer the source with the most complete Chinese author names
    public static func buildConsensus(
        seed: MetadataResolutionSeed?,
        contributions: [SourceContribution]
    ) -> Reference? {
        guard !contributions.isEmpty else { return nil }

        // Sort by priority (lower = better)
        let sorted = contributions.sorted { $0.priority < $1.priority }
        guard var consensus = sorted.first?.reference else { return nil }

        // Title: prefer Han-text source with highest title similarity
        let chineseContribs = sorted.filter { MetadataResolution.containsHanCharacters($0.reference.title) }
        if let bestChinese = chineseContribs.max(by: { $0.titleScore < $1.titleScore }) {
            consensus.title = bestChinese.reference.title
        }

        // Journal: prefer Chinese database source
        for contrib in sorted {
            if let journal = contrib.reference.journal?.swiftlib_nilIfBlank,
               MetadataResolution.containsHanCharacters(journal) {
                consensus.journal = journal
                break
            }
        }

        // Abstract: prefer longest Chinese abstract
        let chineseAbstracts = sorted.compactMap { contrib -> (String, Int)? in
            guard let abs = contrib.reference.abstract?.swiftlib_nilIfBlank,
                  MetadataResolution.containsHanCharacters(abs) else { return nil }
            return (abs, abs.count)
        }
        if let longest = chineseAbstracts.max(by: { $0.1 < $1.1 }) {
            consensus.abstract = longest.0
        } else {
            // Fallback to any non-empty abstract
            for contrib in sorted {
                if let abs = contrib.reference.abstract?.swiftlib_nilIfBlank {
                    consensus.abstract = abs
                    break
                }
            }
        }

        // Authors: prefer source with most complete Chinese author names
        let authorSets = sorted.map { ($0.reference.authors, $0.source) }
        if let bestAuthors = authorSets.max(by: { lhs, rhs in
            let lhsChinese = lhs.0.filter { MetadataResolution.containsHanCharacters($0.displayName) }.count
            let rhsChinese = rhs.0.filter { MetadataResolution.containsHanCharacters($0.displayName) }.count
            return lhsChinese < rhsChinese
        }) {
            consensus.authors = bestAuthors.0
        }

        // Structured fields: fill from highest-priority source
        for contrib in sorted {
            let ref = contrib.reference
            if consensus.doi == nil { consensus.doi = ref.doi?.swiftlib_nilIfBlank }
            if consensus.year == nil { consensus.year = ref.year }
            if consensus.volume == nil { consensus.volume = ref.volume?.swiftlib_nilIfBlank }
            if consensus.issue == nil { consensus.issue = ref.issue?.swiftlib_nilIfBlank }
            if consensus.pages == nil { consensus.pages = ref.pages?.swiftlib_nilIfBlank }
            if consensus.publisher == nil { consensus.publisher = ref.publisher?.swiftlib_nilIfBlank }
            if consensus.issn == nil { consensus.issn = ref.issn?.swiftlib_nilIfBlank }
            if consensus.pmid == nil { consensus.pmid = ref.pmid?.swiftlib_nilIfBlank }
            if consensus.institution == nil { consensus.institution = ref.institution?.swiftlib_nilIfBlank }
        }

        // Enrichment fields: merge from any source
        for contrib in sorted {
            let ref = contrib.reference
            if consensus.keywords == nil { consensus.keywords = ref.keywords }
            if consensus.topics == nil { consensus.topics = ref.topics }
            if consensus.isOpenAccess == nil { consensus.isOpenAccess = ref.isOpenAccess }
            if consensus.oaUrl == nil { consensus.oaUrl = ref.oaUrl }
            if consensus.citedByCount == nil { consensus.citedByCount = ref.citedByCount }
            if consensus.fundingInfo == nil { consensus.fundingInfo = ref.fundingInfo }
        }

        consensus.language = "zh-CN"
        consensus.metadataSource = sorted.first?.source

        return consensus
    }

    /// Build contributions from available fetched references.
    public static func makeContributions(
        seed: MetadataResolutionSeed?,
        sources: [(MetadataSource, Reference)]
    ) -> [SourceContribution] {
        sources.map { source, ref in
            let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", ref.title)
            return SourceContribution(
                source: source,
                reference: ref,
                titleScore: titleScore,
                priority: sourcePriority(source)
            )
        }
    }
}
