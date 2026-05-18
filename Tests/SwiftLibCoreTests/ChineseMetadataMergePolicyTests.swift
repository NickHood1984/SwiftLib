import XCTest
@testable import SwiftLibCore

final class ChineseMetadataMergePolicyTests: XCTestCase {

    // MARK: - shouldPreferChineseText

    func testPrefersChineseWhenSeedHasChineseLanguageHint() {
        let seed = MetadataResolutionSeed(
            fileName: "paper",
            title: "Some Paper",
            languageHint: .chinese
        )
        XCTAssertTrue(ChineseMetadataMergePolicy.shouldPreferChineseText(seed: seed))
    }

    func testPrefersChineseWhenSeedTitleContainsHanCharacters() {
        let seed = MetadataResolutionSeed(
            fileName: "太湖水质分析",
            title: "太湖水质分析",
            languageHint: .unknown
        )
        XCTAssertTrue(ChineseMetadataMergePolicy.shouldPreferChineseText(seed: seed))
    }

    func testPrefersChineseWhenInputURLIsCNKI() {
        let url = URL(string: "https://kns.cnki.net/detail/12345")!
        XCTAssertTrue(ChineseMetadataMergePolicy.shouldPreferChineseText(inputURL: url))
    }

    func testPrefersChineseWhenReferenceSourceIsCNKI() {
        var ref = Reference(title: "Some Paper")
        ref.metadataSource = .cnki
        XCTAssertTrue(ChineseMetadataMergePolicy.shouldPreferChineseText(reference: ref))
    }

    func testPrefersChineseWhenExistingReferenceSourceIsWanfang() {
        var existing = Reference(title: "已有文献")
        existing.metadataSource = .wanfang
        XCTAssertTrue(ChineseMetadataMergePolicy.shouldPreferChineseText(existingReference: existing))
    }

    func testPrefersChineseWhenReferenceTitleContainsHanCharacters() {
        var ref = Reference(title: "洱海营养盐变化研究")
        ref.metadataSource = .crossRef
        XCTAssertTrue(ChineseMetadataMergePolicy.shouldPreferChineseText(reference: ref))
    }

    func testDoesNotPreferChineseForPureEnglishContent() {
        let seed = MetadataResolutionSeed(
            fileName: "deep-learning-paper",
            title: "Deep Learning for Natural Language Processing",
            languageHint: .nonChinese
        )
        var ref = Reference(title: "Deep Learning for Natural Language Processing")
        ref.metadataSource = .crossRef

        XCTAssertFalse(ChineseMetadataMergePolicy.shouldPreferChineseText(
            seed: seed, reference: ref
        ))
    }

    // MARK: - merge: Chinese fields priority

    func testMergePreservesChineseTitleFromCNKIOverEnglishBackend() {
        var backend = Reference(title: "Study on Water Quality of Taihu Lake")
        backend.journal = "Journal of Lake Sciences"

        var chinese = Reference(title: "太湖水质时空变化研究")
        chinese.journal = "湖泊科学"
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.title, "太湖水质时空变化研究")
        XCTAssertEqual(result.journal, "湖泊科学")
        XCTAssertEqual(result.language, "zh-CN")
    }

    func testMergeKeepsEnglishTitleWhenChineseTitleIsEmpty() {
        let backend = Reference(title: "Spatiotemporal Dynamics of Lake Pollution")
        var chinese = Reference(title: "")
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.title, "Spatiotemporal Dynamics of Lake Pollution")
    }

    func testMergePreservesChineseAbstractOverEnglish() {
        var backend = Reference(title: "Water Quality Study")
        backend.abstract = "This is the English abstract."

        var chinese = Reference(title: "水质研究")
        chinese.abstract = "这是中文摘要内容，描述研究结果和意义。"
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.abstract, "这是中文摘要内容，描述研究结果和意义。")
    }

    func testMergeUsesBackendAbstractWhenChineseHasNone() {
        var backend = Reference(title: "Water Quality Study")
        backend.abstract = "English abstract content."

        var chinese = Reference(title: "水质研究")
        chinese.abstract = nil
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.abstract, "English abstract content.")
    }

    func testMergeSetsLanguageZhCNWhenChineseTitleHasHanCharacters() {
        var backend = Reference(title: "Water Study")
        backend.language = "en"

        var chinese = Reference(title: "水体研究")
        chinese.language = nil
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.language, "zh-CN")
    }

    func testMergeUsesChineseExplicitLanguageWhenProvided() {
        var backend = Reference(title: "Water Study")
        var chinese = Reference(title: "Water Study")
        chinese.language = "zh-TW"
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.language, "zh-TW")
    }

    // MARK: - Author deduplication

    func testMergeAuthorsUsesChineseAsBaseAndAppendsNewEnglishAuthors() {
        var backend = Reference(title: "Paper")
        backend.authors = [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe")
        ]

        var chinese = Reference(title: "论文")
        chinese.authors = [AuthorName(given: "小明", family: "张")]
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.authors.count, 3)
        XCTAssertEqual(result.authors.first?.family, "张")
    }

    func testMergeAuthorsDoesNotDuplicateByFamilyName() {
        var backend = Reference(title: "Paper")
        backend.authors = [AuthorName(given: "Haoyun", family: "Wu")]

        var chinese = Reference(title: "论文")
        chinese.authors = [AuthorName(given: "浩云", family: "Wu")]
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        // "Wu" appears in both lists but same family name, should not duplicate
        XCTAssertEqual(result.authors.filter { $0.family.lowercased() == "wu" }.count, 1)
    }

    func testMergeAuthorsUsesChineseListWhenBackendIsEmpty() {
        var backend = Reference(title: "Paper")
        backend.authors = []

        var chinese = Reference(title: "论文")
        chinese.authors = [AuthorName(given: "小明", family: "张")]
        chinese.metadataSource = .cnki

        let result = ChineseMetadataMergePolicy.merge(backend: backend, chinese: chinese)

        XCTAssertEqual(result.authors, [AuthorName(given: "小明", family: "张")])
    }

    // MARK: - mergeResolvedChineseReference

    func testMergeResolvedPrefersChinesePrimaryFields() {
        var chinese = Reference(title: "知网返回的论文标题")
        chinese.journal = "湖泊科学"
        chinese.year = 2023
        chinese.metadataSource = .cnki

        var fallback = Reference(title: "CrossRef Title")
        fallback.journal = "Journal of Lake Sciences"
        fallback.doi = "10.1234/example"
        fallback.year = 2022

        let result = ChineseMetadataMergePolicy.mergeResolvedChineseReference(chinese, fallback: fallback)

        XCTAssertEqual(result.title, "知网返回的论文标题")
        XCTAssertEqual(result.journal, "湖泊科学")
        // DOI fills from fallback since chinese lacks it
        XCTAssertEqual(result.doi, "10.1234/example")
    }
}
