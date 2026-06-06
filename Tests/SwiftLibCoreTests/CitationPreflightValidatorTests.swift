import XCTest
@testable import SwiftLibCore

final class CitationPreflightValidatorTests: XCTestCase {
    func testCompleteReferenceDoesNotBlockInsertion() {
        let ref = Reference(
            id: 9101,
            title: "Complete Citation Record",
            authors: [AuthorName(given: "Jane", family: "Smith")],
            year: 2024,
            journal: "Journal of Complete Records",
            volume: "12",
            issue: "3",
            pages: "45-56",
            referenceType: .journalArticle
        )

        let report = CitationPreflightValidator.validate(
            styleID: "apa",
            references: [ref],
            citationClusters: [
                CitationDocumentCluster(id: "c1", itemIDs: ["9101"], position: 0)
            ],
            citationTexts: ["c1": "(Smith, 2024)"],
            bibliographyText: "Smith, J. (2024). Complete Citation Record.",
            includeBibliography: true
        )

        XCTAssertFalse(report.isBlocked)
        XCTAssertTrue(report.criticalIssues.isEmpty)
    }

    func testCriticalFieldIssuesBlockInsertion() {
        let ref = Reference(
            id: 9102,
            title: "   ",
            referenceType: .journalArticle
        )

        let report = CitationPreflightValidator.validate(
            styleID: "china-national-standard-gb-t-7714-2015-numeric",
            references: [ref],
            citationClusters: [
                CitationDocumentCluster(id: "c2", itemIDs: ["9102"], position: 0)
            ],
            citationTexts: ["c2": "[1]"],
            bibliographyText: "[1] Untitled.",
            includeBibliography: true
        )

        XCTAssertTrue(report.isBlocked)
        XCTAssertTrue(report.criticalIssues.contains { $0.fieldKey == "title" })
        XCTAssertTrue(report.criticalIssues.contains { $0.fieldKey == "issued" })
        XCTAssertTrue(report.blockingMessage.contains("当前 CSL 样式无法可靠生成该引文"))
    }

    func testRecommendedFieldIssuesWarnWithoutBlocking() {
        let ref = Reference(
            id: 9103,
            title: "Sparse But Citable Journal Article",
            authors: [AuthorName(given: "Jane", family: "Smith")],
            year: 2024,
            referenceType: .journalArticle
        )

        let report = CitationPreflightValidator.validate(
            styleID: "apa",
            references: [ref],
            citationClusters: [
                CitationDocumentCluster(id: "c3", itemIDs: ["9103"], position: 0)
            ],
            citationTexts: ["c3": "(Smith, 2024)"],
            bibliographyText: "Smith, J. (2024). Sparse But Citable Journal Article.",
            includeBibliography: true
        )

        XCTAssertFalse(report.isBlocked)
        XCTAssertTrue(report.criticalIssues.isEmpty)
        XCTAssertFalse(report.warningIssues.isEmpty)
        XCTAssertTrue(report.warningIssues.contains { $0.fieldKey == "container-title" })
    }

    func testMissingRenderedCitationTextBlocksInsertion() {
        let ref = Reference(
            id: 9104,
            title: "Rendered Text Missing",
            authors: [AuthorName(given: "Jane", family: "Smith")],
            year: 2024,
            journal: "Journal of Missing Text",
            volume: "1",
            pages: "1-2",
            referenceType: .journalArticle
        )

        let report = CitationPreflightValidator.validate(
            styleID: "apa",
            references: [ref],
            citationClusters: [
                CitationDocumentCluster(id: "c4", itemIDs: ["9104"], position: 0)
            ],
            citationTexts: [:],
            bibliographyText: "Smith, J. (2024). Rendered Text Missing.",
            includeBibliography: true
        )

        XCTAssertTrue(report.isBlocked)
        XCTAssertTrue(report.criticalIssues.contains { $0.citationID == "c4" && $0.displayName == "引文文本" })
    }

    func testInvalidRenderedFragmentsBlockInsertion() {
        let ref = Reference(
            id: 9105,
            title: "Invalid Rendered Fragment",
            authors: [AuthorName(given: "Jane", family: "Smith")],
            year: 2024,
            journal: "Journal of Invalid Text",
            volume: "1",
            pages: "1-2",
            referenceType: .journalArticle
        )

        let report = CitationPreflightValidator.validate(
            styleID: "apa",
            references: [ref],
            citationClusters: [
                CitationDocumentCluster(id: "c5", itemIDs: ["9105"], position: 0)
            ],
            citationTexts: ["c5": "(undefined, 2024)"],
            bibliographyText: "Smith, J. (2024). Invalid Rendered Fragment.",
            includeBibliography: true
        )

        XCTAssertTrue(report.isBlocked)
        XCTAssertTrue(report.criticalIssues.contains { $0.message.contains("undefined") })
    }
}
