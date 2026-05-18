import Foundation

extension MetadataFetcher {
    // MARK: - Unified Fetch

    /// Auto-detect identifier and fetch metadata.
    public static func fetch(from text: String) async throws -> Reference {
        guard let identifier = extractIdentifier(from: text) else {
            throw FetchError.unrecognizedIdentifier
        }

        switch identifier {
        case .doi(let doi):   return try await fetchFromDOI(doi)
        case .pmid(let pmid): return try await fetchFromPMID(pmid)
        case .arxiv(let id):  return try await fetchFromArXiv(id)
        case .isbn(let isbn): return try await fetchFromISBN(isbn)
        }
    }

}
