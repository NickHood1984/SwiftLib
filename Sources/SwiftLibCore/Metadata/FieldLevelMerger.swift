import Foundation

/// Field-level confidence-based merger for multi-source metadata.
/// Stateless — all logic is in static functions.
///
/// Priority rules:
/// - Title/authors/year/journal/volume/issue/pages: CrossRef > OpenAlex > S2
/// - DOI: CrossRef > OpenAlex > S2 (first non-nil wins)
/// - Abstract: S2 > OpenAlex > CrossRef (S2 has best STEM coverage)
/// - TLDR: S2 only
/// - Keywords/topics/OA/funding: OpenAlex only
/// - Citation count: OpenAlex > S2 (OpenAlex is more comprehensive)
/// - Open Access URL: S2 (direct PDF) > OpenAlex
public enum FieldLevelMerger {

    /// Merge multiple source results into a single Reference + enrichment.
    /// Returns the merged Reference and the best OpenAlexEnrichment found.
    public static func merge(
        sources: [ParallelSourceFetcher.SourceResult],
        existing: Reference
    ) -> (Reference, MetadataFetcher.OpenAlexEnrichment?) {
        guard !sources.isEmpty else { return (existing, nil) }

        // Sort sources by priority for bibliographic fields
        let biblioPriority: [MetadataSource] = [.crossRef, .openAlex, .semanticScholar, .pubMed, .arXiv]

        let sorted = sources.sorted { a, b in
            let ai = biblioPriority.firstIndex(of: a.source) ?? biblioPriority.count
            let bi = biblioPriority.firstIndex(of: b.source) ?? biblioPriority.count
            return ai < bi
        }

        // Start from the highest-priority fetched source so refresh can replace
        // stale bibliographic fields instead of only filling blanks.
        var merged = sorted.first?.reference ?? existing

        // Bibliographic fields: take from highest-priority source that has non-empty value
        for result in sorted {
            let ref = result.reference
            if merged.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               merged.title == "Untitled" {
                merged.title = ref.title
            }
            if merged.authors.isEmpty && !ref.authors.isEmpty {
                merged.authors = ref.authors
            }
            if merged.year == nil { merged.year = ref.year }
            if merged.journal.swiftlib_nilIfBlank == nil { merged.journal = ref.journal }
            if merged.volume.swiftlib_nilIfBlank == nil { merged.volume = ref.volume }
            if merged.issue.swiftlib_nilIfBlank == nil { merged.issue = ref.issue }
            if merged.pages.swiftlib_nilIfBlank == nil { merged.pages = ref.pages }
            if merged.doi.swiftlib_nilIfBlank == nil { merged.doi = ref.doi }
            if merged.url.swiftlib_nilIfBlank == nil { merged.url = ref.url }
            if merged.pmid.swiftlib_nilIfBlank == nil { merged.pmid = ref.pmid }
            if merged.pmcid.swiftlib_nilIfBlank == nil { merged.pmcid = ref.pmcid }
            if merged.referenceType == .other || merged.referenceType == .journalArticle {
                if ref.referenceType != .other && ref.referenceType != .journalArticle {
                    merged.referenceType = ref.referenceType
                }
            }
        }

        // Title: prefer CrossRef title if substantially different
        if let crossRefResult = sorted.first(where: { $0.source == .crossRef }) {
            let crTitle = crossRefResult.reference.title
            if !crTitle.isEmpty && crTitle != "Untitled" {
                merged.title = crTitle
            }
        }

        // Authors: prefer CrossRef (most structured)
        if let crossRefResult = sorted.first(where: { $0.source == .crossRef }),
           !crossRefResult.reference.authors.isEmpty {
            merged.authors = crossRefResult.reference.authors
        }

        // Abstract: S2 > OpenAlex > CrossRef (S2 has best abstract coverage for STEM)
        let abstractPriority: [MetadataSource] = [.semanticScholar, .openAlex, .crossRef]
        for source in abstractPriority {
            if let result = sorted.first(where: { $0.source == source }),
               let abs = result.reference.abstract, !abs.isEmpty {
                merged.abstract = abs
                break
            }
        }

        // Open Access URL: S2 (direct PDF link) > OpenAlex
        if let s2Result = sorted.first(where: { $0.source == .semanticScholar }),
           let s2Paper = s2Result.s2Paper,
           let pdfUrl = s2Paper.openAccessPdfUrl, !pdfUrl.isEmpty {
            merged.oaUrl = pdfUrl
            merged.isOpenAccess = true
        }

        // Collect best enrichment (from OpenAlex source)
        var bestEnrichment = sorted.first(where: { $0.source == .openAlex })?.enrichment

        // Enhance enrichment with S2-specific data
        if let s2Result = sorted.first(where: { $0.source == .semanticScholar }),
           let s2Paper = s2Result.s2Paper {
            // TLDR from S2
            if let tldr = s2Paper.tldr, !tldr.isEmpty {
                // Store TLDR as a note appendix (or separate field if available)
                // For now, if abstract is missing and TLDR is available, use TLDR
                if (merged.abstract ?? "").isEmpty {
                    merged.abstract = tldr
                }
            }

            // Use S2 citation count if OpenAlex didn't provide one
            if bestEnrichment == nil {
                bestEnrichment = MetadataFetcher.OpenAlexEnrichment(
                    keywords: [],
                    topics: [],
                    isOpenAccess: s2Paper.isOpenAccess,
                    oaUrl: s2Paper.openAccessPdfUrl,
                    citedByCount: s2Paper.citationCount,
                    fundingInfo: [],
                    referenceType: nil,
                    openAlexId: nil,
                    abstract: s2Paper.abstract
                )
            }
        }

        // Compute confidence score based on source agreement
        merged.confidenceScore = computeConfidence(sources: sorted, merged: merged)
        merged.dateModified = Date()

        // Determine best metadataSource to record
        if sorted.contains(where: { $0.source == .crossRef }) {
            merged.metadataSource = .crossRef
        } else if sorted.contains(where: { $0.source == .openAlex }) {
            merged.metadataSource = .openAlex
        } else if let first = sorted.first {
            merged.metadataSource = first.source
        }

        return (merged, bestEnrichment)
    }

    // MARK: - Confidence Score

    /// Compute a 0–1 confidence score based on multi-source agreement.
    static func computeConfidence(
        sources: [ParallelSourceFetcher.SourceResult],
        merged: Reference
    ) -> Double {
        guard !sources.isEmpty else { return 0 }

        var score = 0.0
        let sourceCount = Double(sources.count)

        // Base: number of sources (more sources = higher base confidence)
        score += min(sourceCount / 3.0, 1.0) * 0.3  // up to 0.3 for 3+ sources

        // Has DOI: strong identifier
        if merged.doi.swiftlib_nilIfBlank != nil { score += 0.2 }

        // Title agreement across sources
        let titles = sources.map { $0.reference.title }
        if titles.count >= 2 {
            let titleScores = titles.combinations(ofCount: 2).map {
                MetadataResolution.titleSimilarity($0[0], $0[1])
            }
            let avgTitleScore = titleScores.reduce(0.0, +) / Double(titleScores.count)
            score += avgTitleScore * 0.2
        } else {
            score += 0.1  // Single source title
        }

        // Year agreement
        let years = sources.compactMap { $0.reference.year }
        if years.count >= 2 {
            let allSame = Set(years).count == 1
            score += allSame ? 0.15 : 0.05
        } else if !years.isEmpty {
            score += 0.1
        }

        // Has abstract
        if merged.abstract.swiftlib_nilIfBlank != nil { score += 0.1 }

        // Has authors
        if !merged.authors.isEmpty { score += 0.05 }

        return min(score, 1.0)
    }
}

// MARK: - Array combinatorics helper
private extension Array {
    func combinations(ofCount k: Int) -> [[Element]] {
        guard k > 0, k <= count else { return k == 0 ? [[]] : [] }
        if k == 1 { return map { [$0] } }
        var result: [[Element]] = []
        for (i, element) in enumerated() {
            let rest = Array(self[(i + 1)...])
            for combo in rest.combinations(ofCount: k - 1) {
                result.append([element] + combo)
            }
        }
        return result
    }
}
