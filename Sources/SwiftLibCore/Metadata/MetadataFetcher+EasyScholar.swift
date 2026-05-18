import Foundation

extension MetadataFetcher {
    // MARK: - easyScholar Journal Rank

    /// Fetch journal rank data from easyScholar open API.
    public static func enrichWithEasyScholar(journal: String, secretKey: String) async -> EasyScholarRankResponse? {
        await EasyScholarRankProvider.fetchRank(publicationName: journal, secretKey: secretKey)
    }

}
