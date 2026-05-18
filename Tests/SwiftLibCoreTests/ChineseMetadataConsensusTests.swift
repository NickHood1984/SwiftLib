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
