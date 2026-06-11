import XCTest
@testable import SwiftLibCore

final class ChineseStructuredCandidateTests: XCTestCase {

    private func seed(
        title: String? = "湖泊富营养化对浮游植物群落结构的影响",
        firstAuthor: String? = "林秋奇",
        year: Int? = 2020,
        journal: String? = "生态学报"
    ) -> MetadataResolutionSeed {
        MetadataResolutionSeed(
            fileName: title ?? "test.pdf",
            title: title,
            firstAuthor: firstAuthor,
            year: year,
            journal: journal,
            languageHint: .chinese,
            workKindHint: .journalArticle
        )
    }

    // MARK: - scoreStructuredChineseCandidate

    func testExactMatchScoresHigh() {
        let score = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(),
            title: "湖泊富营养化对浮游植物群落结构的影响",
            authors: [AuthorName(given: "", family: "林秋奇")],
            journal: "生态学报",
            year: 2020
        )
        XCTAssertGreaterThanOrEqual(score, 0.90, "题名/作者/年份/期刊全中应接近满分")
    }

    func testUnrelatedResultIsNotInflatedToFloor() {
        let score = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(),
            title: "城市轨道交通客流预测模型研究",
            authors: [AuthorName(given: "", family: "王五")],
            journal: "交通运输工程学报",
            year: 2015
        )
        XCTAssertLessThan(score, 0.30, "弱相关结果不得再被抬到 0.45 下限")
    }

    func testAuthorAndYearLiftBorderlineTitle() {
        let base = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(),
            title: "富营养化对浮游植物的影响",
            authors: [],
            journal: nil,
            year: nil
        )
        let lifted = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(),
            title: "富营养化对浮游植物的影响",
            authors: [AuthorName(given: "", family: "林秋奇")],
            journal: "生态学报",
            year: 2020
        )
        XCTAssertGreaterThan(lifted, base + 0.30, "作者+年份+期刊命中应显著提升评分")
    }

    func testAdjacentYearGetsPartialCredit() {
        let exact = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(), title: "湖泊富营养化对浮游植物群落结构的影响",
            authors: [], journal: nil, year: 2020
        )
        let adjacent = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(), title: "湖泊富营养化对浮游植物群落结构的影响",
            authors: [], journal: nil, year: 2021
        )
        let far = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed(), title: "湖泊富营养化对浮游植物群落结构的影响",
            authors: [], journal: nil, year: 2010
        )
        XCTAssertGreaterThan(exact, adjacent)
        XCTAssertGreaterThan(adjacent, far)
    }

    // MARK: - structuredChineseAuthor

    func testHanNameBecomesFamilyOnly() {
        let author = MetadataResolution.structuredChineseAuthor(from: "张三")
        XCTAssertEqual(author.family, "张三")
        XCTAssertEqual(author.given, "")
    }

    func testSpacedHanNameIsNotSplit() {
        let author = MetadataResolution.structuredChineseAuthor(from: "张 三")
        XCTAssertEqual(author.family, "张三", "带空格的中文名不得按西文规则拆成 given/family")
        XCTAssertEqual(author.given, "")
    }

    func testWesternNameStillParsesNormally() {
        let author = MetadataResolution.structuredChineseAuthor(from: "John Smith")
        XCTAssertEqual(author.family, "Smith")
        XCTAssertEqual(author.given, "John")
    }

    func testMinorityCompoundNameKept() {
        let author = MetadataResolution.structuredChineseAuthor(from: "买买提·艾力")
        XCTAssertEqual(author.family, "买买提·艾力")
        XCTAssertEqual(author.given, "")
    }
}
