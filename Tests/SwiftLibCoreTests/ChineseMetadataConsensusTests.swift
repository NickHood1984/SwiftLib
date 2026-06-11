import XCTest
@testable import SwiftLibCore

final class ChineseMetadataConsensusTests: XCTestCase {

    // MARK: - Helpers

    private func contribution(
        source: MetadataSource,
        title: String,
        journal: String? = nil,
        abstract: String? = nil,
        doi: String? = nil,
        year: Int? = nil,
        volume: String? = nil,
        issue: String? = nil,
        pages: String? = nil,
        authors: [AuthorName] = [],
        seedTitle: String = ""
    ) -> ChineseMetadataConsensus.SourceContribution {
        var ref = Reference(title: title, authors: authors, year: year)
        ref.journal = journal
        ref.abstract = abstract
        ref.doi = doi
        ref.volume = volume
        ref.issue = issue
        ref.pages = pages
        ref.metadataSource = source

        let seed = seedTitle.isEmpty ? nil : MetadataResolutionSeed(
            fileName: seedTitle,
            title: seedTitle
        )
        let contribs = ChineseMetadataConsensus.makeContributions(
            seed: seed,
            sources: [(source, ref)]
        )
        return contribs[0]
    }

    // MARK: - Empty input

    func testBuildConsensusReturnsNilForEmptyContributions() {
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [])
        XCTAssertNil(result)
    }

    // MARK: - Title selection

    func testBuildConsensusPrefersChineseTitleWithHigherTitleScore() {
        let seed = MetadataResolutionSeed(fileName: "洱海水质研究", title: "洱海水质研究")

        let cnki = contribution(source: .cnki, title: "洱海水质时空变化研究", seedTitle: "洱海水质研究")
        let openAlex = contribution(source: .openAlex, title: "Water Quality Study of Erhai Lake", seedTitle: "洱海水质研究")

        let result = ChineseMetadataConsensus.buildConsensus(seed: seed, contributions: [cnki, openAlex])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "洱海水质时空变化研究")
    }

    func testBuildConsensusUsesEnglishTitleWhenNoChinese() {
        let cnki = contribution(source: .cnki, title: "CNKI English Title")
        let openAlex = contribution(source: .openAlex, title: "OpenAlex Title")

        // No Han characters in any title → falls back to highest-priority source title
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, openAlex])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "CNKI English Title") // CNKI priority = 1
    }

    // MARK: - Journal selection

    func testBuildConsensusPrefersChineseJournalFromHighPrioritySource() {
        let cnki = contribution(source: .cnki, title: "洱海论文", journal: "湖泊科学")
        let openAlex = contribution(source: .openAlex, title: "Erhai Paper", journal: "Journal of Lake Sciences")

        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, openAlex])

        XCTAssertEqual(result?.journal, "湖泊科学")
    }

    func testBuildConsensusFallsBackToEnglishJournalWhenNoChinese() {
        let crossRef = contribution(source: .crossRef, title: "Paper", journal: "Nature")
        let openAlex = contribution(source: .openAlex, title: "Paper", journal: "Science")

        // Neither journal is Chinese → first source journal wins (CNKI not present)
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [crossRef, openAlex])

        XCTAssertEqual(result?.journal, "Nature") // crossRef priority = 4, openAlex = 5
    }

    // MARK: - Abstract selection

    func testBuildConsensusPreferslongestChineseAbstract() {
        var refShort = Reference(title: "洱海论文")
        refShort.abstract = "短摘要内容。"
        refShort.metadataSource = .cnki

        var refLong = Reference(title: "洱海研究")
        refLong.abstract = "这是一段更长的中文摘要，详细描述了研究背景、方法、结果以及结论的各个方面。"
        refLong.metadataSource = .wanfang

        let contribs = ChineseMetadataConsensus.makeContributions(
            seed: nil,
            sources: [(.cnki, refShort), (.wanfang, refLong)]
        )
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: contribs)

        XCTAssertEqual(result?.abstract, "这是一段更长的中文摘要，详细描述了研究背景、方法、结果以及结论的各个方面。")
    }

    func testBuildConsensusUsesEnglishAbstractWhenNoChinese() {
        let cnki = contribution(source: .cnki, title: "Paper", abstract: "English abstract text.")
        let openAlex = contribution(source: .openAlex, title: "Paper", abstract: "Another abstract.")

        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, openAlex])

        XCTAssertEqual(result?.abstract, "English abstract text.")
    }

    func testBuildConsensusAbstractIsNilWhenAllAbstractsMissing() {
        let cnki = contribution(source: .cnki, title: "Paper")
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki])
        XCTAssertNil(result?.abstract)
    }

    // MARK: - Author selection

    func testBuildConsensusPrefersSourceWithMostChineseAuthors() {
        let crossRefAuthors = [
            AuthorName(given: "Haoyun", family: "Wu"),
            AuthorName(given: "John", family: "Smith")
        ]
        let cnkiAuthors = [
            AuthorName(given: "浩云", family: "吴"),
            AuthorName(given: "建国", family: "张"),
            AuthorName(given: "晓梅", family: "李")
        ]

        var crossRefRef = Reference(title: "Water Study")
        crossRefRef.authors = crossRefAuthors
        crossRefRef.metadataSource = .crossRef

        var cnkiRef = Reference(title: "水体研究")
        cnkiRef.authors = cnkiAuthors
        cnkiRef.metadataSource = .cnki

        let contribs = ChineseMetadataConsensus.makeContributions(
            seed: nil,
            sources: [(.crossRef, crossRefRef), (.cnki, cnkiRef)]
        )
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: contribs)

        XCTAssertEqual(result?.authors.count, 3)
        XCTAssertEqual(result?.authors.first?.family, "吴")
    }

    // MARK: - Structured fields

    func testBuildConsensusFillsDOIFromHighestPrioritySourceWithValue() {
        // CNKI has no DOI, CrossRef does
        let cnki = contribution(source: .cnki, title: "中国论文", doi: nil, year: 2023)
        let crossRef = contribution(source: .crossRef, title: "China Paper", doi: "10.1234/test", year: 2023)

        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, crossRef])

        XCTAssertEqual(result?.doi, "10.1234/test")
    }

    func testBuildConsensusFillsYearFromHighestPrioritySource() {
        let cnki = contribution(source: .cnki, title: "论文", year: 2023)
        let openAlex = contribution(source: .openAlex, title: "Paper", year: 2022)

        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, openAlex])

        XCTAssertEqual(result?.year, 2023)
    }

    func testBuildConsensusFillsVolumeIssuePagesFromHighestPrioritySource() {
        let cnki = contribution(source: .cnki, title: "论文", volume: "35", issue: "3", pages: "120-128")
        let openAlex = contribution(source: .openAlex, title: "Paper", volume: "10", issue: "1", pages: "1-5")

        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, openAlex])

        XCTAssertEqual(result?.volume, "35")
        XCTAssertEqual(result?.issue, "3")
        XCTAssertEqual(result?.pages, "120-128")
    }

    // MARK: - Language and source

    func testBuildConsensusSetsLanguageZhCN() {
        let cnki = contribution(source: .cnki, title: "中国论文")
        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki])
        XCTAssertEqual(result?.language, "zh-CN")
    }

    func testBuildConsensusSetsCNKIAsMetadataSourceWhenCNKIPresent() {
        let cnki = contribution(source: .cnki, title: "论文")
        let openAlex = contribution(source: .openAlex, title: "Paper")

        let result = ChineseMetadataConsensus.buildConsensus(seed: nil, contributions: [cnki, openAlex])

        XCTAssertEqual(result?.metadataSource, .cnki)
    }

    // MARK: - Author selection regressions

    /// 全部来源都没有中文作者名时，不得用低优先级源（OpenAlex）的作者列表
    /// 覆盖最高优先级来源的作者顺序（旧实现 max(by:) 取最后一个极大元素，
    /// 全 0 并列时恰好把作者顺序交给了优先级最低的源）。
    func testAuthorsNotOverriddenByLowestPrioritySourceWhenNoHanNames() {
        let seed = MetadataResolutionSeed(fileName: "paper", title: "Some English Paper")

        let crossRef = contribution(
            source: .crossRef,
            title: "Some English Paper",
            authors: [
                AuthorName(given: "Alice", family: "First"),
                AuthorName(given: "Bob", family: "Second"),
            ],
            seedTitle: "Some English Paper"
        )
        let openAlex = contribution(
            source: .openAlex,
            title: "Some English Paper",
            authors: [
                AuthorName(given: "Bob", family: "Second"),
                AuthorName(given: "Alice", family: "First"),
            ],
            seedTitle: "Some English Paper"
        )

        let result = ChineseMetadataConsensus.buildConsensus(seed: seed, contributions: [crossRef, openAlex])

        XCTAssertEqual(result?.authors.first?.family, "First", "无中文作者时应保留最高优先级源（CrossRef）的作者顺序")
    }

    /// 中文作者数并列时按来源优先级取舍（CNKI 优先于维普）。
    func testAuthorsTieBrokenBySourcePriority() {
        let seed = MetadataResolutionSeed(fileName: "论文", title: "某中文论文")

        let cnki = contribution(
            source: .cnki,
            title: "某中文论文",
            authors: [AuthorName(given: "", family: "张三"), AuthorName(given: "", family: "李四")],
            seedTitle: "某中文论文"
        )
        let vip = contribution(
            source: .vip,
            title: "某中文论文",
            authors: [AuthorName(given: "", family: "李四"), AuthorName(given: "", family: "张三")],
            seedTitle: "某中文论文"
        )

        let result = ChineseMetadataConsensus.buildConsensus(seed: seed, contributions: [vip, cnki])

        XCTAssertEqual(result?.authors.first?.family, "张三", "中文作者数并列时应取优先级更高的 CNKI 的顺序")
    }

    // MARK: - makeContributions priority

    func testMakeContributionsAssignsPriorityOrderCNKIFirst() {
        let sources: [(MetadataSource, Reference)] = [
            (.openAlex, Reference(title: "Paper A")),
            (.cnki, Reference(title: "论文 B")),
            (.wanfang, Reference(title: "论文 C")),
        ]
        let contribs = ChineseMetadataConsensus.makeContributions(seed: nil, sources: sources)

        let sorted = contribs.sorted { $0.priority < $1.priority }
        XCTAssertEqual(sorted.first?.source, .cnki)
        XCTAssertEqual(sorted[1].source, .wanfang)
        XCTAssertEqual(sorted.last?.source, .openAlex)
    }
}
