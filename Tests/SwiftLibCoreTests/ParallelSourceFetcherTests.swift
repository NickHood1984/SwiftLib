import XCTest
@testable import SwiftLibCore

final class ParallelSourceFetcherTests: XCTestCase {

    private func sourceResult(
        source: MetadataSource,
        title: String,
        doi: String?
    ) -> ParallelSourceFetcher.SourceResult {
        var ref = Reference(title: title)
        ref.doi = doi
        return ParallelSourceFetcher.SourceResult(source: source, reference: ref)
    }

    // MARK: - Disproven-DOI scrubbing

    /// When CrossRef shows that a title-search-discovered DOI points to a
    /// different paper, that DOI must be removed from every source result so
    /// FieldLevelMerger cannot persist the wrong identifier.
    func testScrubRemovesDisprovenDOIFromAllSources() {
        let badDOI = "10.1234/wrong-paper"
        let results = [
            sourceResult(source: .openAlex, title: "目标论文标题", doi: badDOI),
            sourceResult(source: .semanticScholar, title: "目标论文标题", doi: "10.1234/WRONG-PAPER"), // 大小写差异也要清除
            sourceResult(source: .pubMed, title: "另一篇", doi: "10.5678/other"),
        ]

        let scrubbed = ParallelSourceFetcher.scrubbingDisprovenDOI(badDOI, from: results)

        XCTAssertNil(scrubbed[0].reference.doi)
        XCTAssertNil(scrubbed[1].reference.doi, "DOI 比较必须大小写不敏感")
        XCTAssertEqual(scrubbed[2].reference.doi, "10.5678/other", "无关 DOI 不得被误删")
    }

    func testScrubLeavesNilDOIUntouched() {
        let results = [sourceResult(source: .openAlex, title: "标题", doi: nil)]
        let scrubbed = ParallelSourceFetcher.scrubbingDisprovenDOI("10.1234/x", from: results)
        XCTAssertNil(scrubbed[0].reference.doi)
        XCTAssertEqual(scrubbed.count, 1)
    }
}
