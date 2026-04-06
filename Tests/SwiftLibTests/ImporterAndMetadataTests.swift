import Foundation
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class ImporterAndMetadataTests: XCTestCase {
    func testBibTeXParseMapsEntryTypesAndPreservesNestedBraceContent() throws {
        let bibtex = """
        @article{smith2024,
          title = {Understanding {Swift} Testing},
          author = {Smith, John and Doe, Jane},
          year = {2024},
          journal = {Journal of Tests},
          volume = {12},
          number = {3},
          pages = {10--20},
          doi = {10.1000/test},
          url = {https://example.com/article},
          abstract = {A careful study.}
        }

        @inproceedings{lee2023,
          title = "Conference Paper",
          author = "Lee, Pat",
          year = "2023",
          booktitle = "Proceedings of SwiftConf"
        }
        """

        let references = BibTeXImporter.parse(bibtex)

        XCTAssertEqual(references.count, 2)

        let article = try XCTUnwrap(references.first)
        XCTAssertEqual(article.title, "Understanding {Swift} Testing")
        XCTAssertEqual(article.authors, [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe"),
        ])
        XCTAssertEqual(article.year, 2024)
        XCTAssertEqual(article.journal, "Journal of Tests")
        XCTAssertEqual(article.volume, "12")
        XCTAssertEqual(article.issue, "3")
        XCTAssertEqual(article.pages, "10--20")
        XCTAssertEqual(article.doi, "10.1000/test")
        XCTAssertEqual(article.url, "https://example.com/article")
        XCTAssertEqual(article.abstract, "A careful study.")
        XCTAssertEqual(article.referenceType, .journalArticle)

        let conference = references[1]
        XCTAssertEqual(conference.title, "Conference Paper")
        XCTAssertEqual(conference.authors, [AuthorName(given: "Pat", family: "Lee")])
        XCTAssertEqual(conference.journal, "Proceedings of SwiftConf")
        XCTAssertEqual(conference.referenceType, .conferencePaper)
    }

    func testRISParseBuildsReferencesIncludingTrailingEntryWithoutER() {
        let ris = """
        TY  - JOUR
        TI  - RIS Article
        AU  - Smith, John
        AU  - Doe, Jane
        PY  - 2022/05/01
        JO  - Parsing Today
        VL  - 8
        IS  - 2
        SP  - 15
        EP  - 30
        DO  - 10.1000/ris
        ER  -
        TY  - CHAP
        T1  - Final Chapter
        A1  - Lee, Pat
        Y1  - 2021
        T2  - Great Book
        """

        let references = RISImporter.parse(ris)

        XCTAssertEqual(references.count, 2)

        let article = references[0]
        XCTAssertEqual(article.title, "RIS Article")
        XCTAssertEqual(article.authors, [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe"),
        ])
        XCTAssertEqual(article.year, 2022)
        XCTAssertEqual(article.journal, "Parsing Today")
        XCTAssertEqual(article.volume, "8")
        XCTAssertEqual(article.issue, "2")
        XCTAssertEqual(article.pages, "15-30")
        XCTAssertEqual(article.doi, "10.1000/ris")
        XCTAssertEqual(article.referenceType, .journalArticle)

        let chapter = references[1]
        XCTAssertEqual(chapter.title, "Final Chapter")
        XCTAssertEqual(chapter.authors, [AuthorName(given: "Pat", family: "Lee")])
        XCTAssertEqual(chapter.year, 2021)
        XCTAssertEqual(chapter.journal, "Great Book")
        XCTAssertEqual(chapter.referenceType, .bookSection)
    }

    func testMetadataFetcherExtractIdentifierPrioritizesSupportedFormats() {
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "https://doi.org/10.1000/xyz.123."),
            matches: .doi("10.1000/xyz.123")
        )
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "9780306406157"),
            matches: .isbn("9780306406157")
        )
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "arXiv:2301.07041v2"),
            matches: .arxiv("2301.07041")
        )
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "12345678"),
            matches: .pmid("12345678")
        )
        XCTAssertNil(MetadataFetcher.extractIdentifier(from: "not an identifier"))
    }

    func testMetadataFetcherPrefersDOIOverOtherNumericPatterns() {
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "doi:10.1000/123456789X"),
            matches: .doi("10.1000/123456789X")
        )
    }

    func testCNKIDetailResolutionRejectsGatewayTitles() {
        XCTAssertNil(CNKIMetadataProvider.resolveTitle(extractedTitle: "自动登录"))
        XCTAssertNil(CNKIMetadataProvider.resolveTitle(extractedTitle: "卢慧斌 陈光杰 蔡燕凤 王教元 陈小林"))
        XCTAssertEqual(
            CNKIMetadataProvider.resolveTitle(extractedTitle: "多目标驱动的太湖调度水位研究"),
            "多目标驱动的太湖调度水位研究"
        )
    }

    func testCNKIDetailResolutionFallsBackToCandidateTitleWhenDetailTitleIsGatewayText() {
        XCTAssertEqual(
            CNKIMetadataProvider.resolvedDetailTitle(
                extractedTitle: "自动登录",
                fallbackCandidateTitle: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析"
            ),
            "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析"
        )
    }

    func testCNKIDetailResolutionFallsBackToCandidateTitleWhenDetailTitleLooksLikeAuthors() {
        XCTAssertEqual(
            CNKIMetadataProvider.resolvedDetailTitle(
                extractedTitle: "卢慧斌 陈光杰 蔡燕凤 王教元 陈小林 段立曾 张虎才",
                fallbackCandidateTitle: "近百年来洱海水生生态环境演化及其驱动机制"
            ),
            "近百年来洱海水生生态环境演化及其驱动机制"
        )
    }

    func testCNKIDetailResolutionUsesOnlyExtractedAuthors() {
        XCTAssertTrue(CNKIMetadataProvider.resolveAuthors(extractedAuthors: []).isEmpty)
        XCTAssertEqual(
            CNKIMetadataProvider.resolveAuthors(extractedAuthors: ["吴浩云", "刘敏", "金科"]),
            [
                AuthorName(given: "", family: "吴浩云"),
                AuthorName(given: "", family: "刘敏"),
                AuthorName(given: "", family: "金科"),
            ]
        )
    }

    func testCNKIDetailResolutionDropsShellNoiseAuthors() {
        XCTAssertEqual(
            CNKIMetadataProvider.resolveAuthors(
                extractedAuthors: ["李锐", "杨智", "印刷版", "有限公司", "编辑部", "华兆晖"]
            ),
            [
                AuthorName(given: "", family: "李锐"),
                AuthorName(given: "", family: "杨智"),
                AuthorName(given: "", family: "华兆晖"),
            ]
        )
    }

    func testCNKIDetailResolutionFallsBackToCandidateAuthorsWhenDetailAuthorsMissing() {
        let fallbackAuthors = [
            AuthorName(given: "", family: "华兆晖"),
            AuthorName(given: "", family: "李钰"),
        ]

        XCTAssertEqual(
            CNKIMetadataProvider.resolvedDetailAuthors(
                extractedAuthors: [],
                fallbackAuthors: fallbackAuthors
            ),
            fallbackAuthors
        )
    }

    func testCNKIDetailVerificationAuthorsDoNotUseCandidateFallback() {
        XCTAssertTrue(
            CNKIMetadataProvider.verificationDetailAuthors(extractedAuthors: []).isEmpty
        )
    }

    func testCNKIDetailResolutionAcceptsStructuredDetailWithoutAuthors() {
        XCTAssertTrue(
            CNKIMetadataProvider.shouldAcceptResolvedDetail(
                resolvedTitle: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
                resolvedAuthors: [],
                journal: "湖泊科学",
                doi: nil,
                yearText: "2024 36(06)",
                pages: "100-112",
                institution: nil,
                thesisType: nil
            )
        )
    }

    func testCNKIDetailResolutionRejectsBodyTextOnlyFallback() {
        XCTAssertFalse(
            CNKIMetadataProvider.shouldAcceptResolvedDetail(
                resolvedTitle: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
                resolvedAuthors: [],
                journal: "湖泊科学",
                doi: nil,
                yearText: "2024 36(06)",
                pages: nil,
                institution: nil,
                thesisType: nil
            )
        )
    }

    func testCNKIPageResolutionPrefersResolvedDetailOverBlockedMarker() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: true,
            searchRowCount: 0,
            hasDetailTitle: true,
            hasDetailAuthors: true,
            hasDetailSummary: true
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .resolvedDetail
        )
    }

    func testCNKIPageResolutionPrefersResolvedSearchOverBlockedMarker() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: true,
            searchRowCount: 3,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .resolvedSearch
        )
    }

    func testCNKIPageResolutionReportsBlockedWhenNoUsableContentExists() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: true,
            searchRowCount: 0,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .blocked
        )
    }

    func testCNKIPageResolutionReportsLoadingWhenSignalsAreAbsent() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: false,
            searchRowCount: 0,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .loadingOrUnknown
        )
    }

    private func assertIdentifier(_ actual: MetadataFetcher.Identifier?, matches expected: MetadataFetcher.Identifier) {
        switch (actual, expected) {
        case (.doi(let lhs), .doi(let rhs)):
            XCTAssertEqual(lhs, rhs)
        case (.pmid(let lhs), .pmid(let rhs)):
            XCTAssertEqual(lhs, rhs)
        case (.arxiv(let lhs), .arxiv(let rhs)):
            XCTAssertEqual(lhs, rhs)
        case (.isbn(let lhs), .isbn(let rhs)):
            XCTAssertEqual(lhs, rhs)
        default:
            XCTFail("Identifier mismatch: actual=\(String(describing: actual)) expected=\(expected)")
        }
    }
}
