import Foundation

extension MetadataResolution {
    // MARK: - OpenAlex Enrichment Merge (v12)

    /// Apply OpenAlex enrichment data onto a Reference without overwriting existing fields.
    public static func applyEnrichment(_ enrichment: MetadataFetcher.OpenAlexEnrichment?, to reference: Reference) -> Reference {
        guard let enrichment else { return reference }
        var merged = reference

        // Keywords & topics — JSON-encode arrays
        if !enrichment.keywords.isEmpty, merged.keywords == nil {
            merged.keywords = (try? JSONEncoder().encode(enrichment.keywords)).flatMap { String(data: $0, encoding: .utf8) }
        }
        if !enrichment.topics.isEmpty, merged.topics == nil {
            merged.topics = (try? JSONEncoder().encode(enrichment.topics)).flatMap { String(data: $0, encoding: .utf8) }
        }

        // Open access
        if merged.isOpenAccess == nil { merged.isOpenAccess = enrichment.isOpenAccess }
        if merged.oaUrl == nil { merged.oaUrl = enrichment.oaUrl }

        // Citation count
        if merged.citedByCount == nil { merged.citedByCount = enrichment.citedByCount }

        // Funding
        if !enrichment.fundingInfo.isEmpty, merged.fundingInfo == nil {
            merged.fundingInfo = (try? JSONEncoder().encode(enrichment.fundingInfo)).flatMap { String(data: $0, encoding: .utf8) }
        }

        // Abstract fallback
        if (merged.abstract ?? "").isEmpty, let abs = enrichment.abstract, !abs.isEmpty {
            merged.abstract = abs
        }

        // Reference type enrichment (only upgrade from .other)
        if merged.referenceType == .other, let enrichedType = enrichment.referenceType {
            merged.referenceType = enrichedType
        }

        return merged
    }

    /// Apply easyScholar journal-rank enrichment to a reference.
    /// Stores the entire JSON response so the UI can render whatever
    /// ranks the user has configured in their easyScholar account.
    public static func applyEasyScholarEnrichment(_ response: EasyScholarRankResponse?, to reference: Reference) -> Reference {
        guard let response, response.isSuccess, let data = response.data else { return reference }
        var merged = reference
        if let encoded = try? JSONEncoder().encode(data),
           let jsonString = String(data: encoded, encoding: .utf8),
           !jsonString.isEmpty {
            merged.journalRankJSON = jsonString
        }
        return merged
    }

}
