import Foundation
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class ReferenceModelTests: XCTestCase {
    func testAuthorNameParseListSupportsCommonInputForms() {
        XCTAssertEqual(
            AuthorName.parseList("Smith, John and Doe, Jane"),
            [
                AuthorName(given: "John", family: "Smith"),
                AuthorName(given: "Jane", family: "Doe"),
            ]
        )

        XCTAssertEqual(
            AuthorName.parseList("Smith, John, Doe, Jane"),
            [
                AuthorName(given: "John", family: "Smith"),
                AuthorName(given: "Jane", family: "Doe"),
            ]
        )

        XCTAssertEqual(
            AuthorName.parseList("John Smith; Jane Doe"),
            [
                AuthorName(given: "John", family: "Smith"),
                AuthorName(given: "Jane", family: "Doe"),
            ]
        )
    }

    func testAuthorNameDisplayVariantsUseExpectedFormatting() {
        let author = AuthorName(given: "Jane Ann", family: "Doe")

        XCTAssertEqual(author.displayName, "Jane Ann Doe")
        XCTAssertEqual(author.shortName, "Doe, J. A.")
        XCTAssertEqual([author].displayString, "Jane Ann Doe")
    }

    func testDecodeWebContentTreatsLegacyHTMLAsHTML() {
        let decoded = Reference.decodeWebContent("<article><p>Hello</p></article>")

        XCTAssertEqual(decoded?.format, .html)
        XCTAssertEqual(decoded?.body, "<article><p>Hello</p></article>")
    }

    func testResolvedWebReaderURLAndCanOpenWebReaderPreferUsableSources() {
        var reference = Reference(
            title: "Clipped page",
            url: "mailto:test@example.com",
            referenceType: .webpage
        )
        reference.siteName = "https://example.com/article"

        XCTAssertEqual(reference.resolvedWebReaderURLString(), "https://example.com/article")
        XCTAssertTrue(reference.canOpenWebReader)

        reference.referenceType = .journalArticle
        XCTAssertFalse(reference.canOpenWebReader)

        let clipped = Reference(
            title: "Saved content",
            webContent: "# Heading",
            referenceType: .webpage
        )
        XCTAssertTrue(clipped.canOpenWebReader)
    }

    func testYouTubeDetectionAndVideoIDParsingHandleCommonURLShapes() {
        XCTAssertTrue(Reference.isLikelyYouTubeWatchURL(urlString: "https://www.youtube.com/watch?v=abc123"))
        XCTAssertTrue(Reference.isLikelyYouTubeWatchURL(urlString: "https://youtu.be/xyz789?t=12"))
        XCTAssertTrue(Reference.isLikelyYouTubeWatchURL(urlString: "https://www.youtube.com/shorts/short42"))
        XCTAssertFalse(Reference.isLikelyYouTubeWatchURL(urlString: "https://example.com/watch?v=abc123"))

        XCTAssertEqual(Reference.parseYouTubeVideoId(from: "https://www.youtube.com/watch?v=abc123"), "abc123")
        XCTAssertEqual(Reference.parseYouTubeVideoId(from: "https://youtu.be/xyz789?t=12"), "xyz789")
        XCTAssertEqual(Reference.parseYouTubeVideoId(from: "https://www.youtube.com/shorts/short42"), "short42")
        XCTAssertEqual(Reference.parseYouTubeVideoId(from: "https://www.youtube.com/embed/embed77"), "embed77")
    }

    func testCSLJSONObjectExportsExpectedFields() throws {
        let reference = Reference(
            id: 42,
            title: "Testing Swift",
            authors: [
                AuthorName(given: "Jane", family: "Doe"),
                AuthorName(given: "John", family: "Smith"),
            ],
            year: 2024,
            journal: "Journal of Tests",
            volume: "12",
            issue: "3",
            pages: "10-20",
            doi: "10.1000/test",
            url: "https://example.com/article",
            referenceType: .journalArticle
        )

        let object = reference.cslJSONObject()
        let authors = try XCTUnwrap(object["author"] as? [[String: String]])
        let issued = try XCTUnwrap(object["issued"] as? [String: Any])
        let dateParts = try XCTUnwrap(issued["date-parts"] as? [[Int]])

        XCTAssertEqual(object["id"] as? String, "42")
        XCTAssertEqual(object["type"] as? String, "article-journal")
        XCTAssertEqual(object["title"] as? String, "Testing Swift")
        XCTAssertEqual(object["container-title"] as? String, "Journal of Tests")
        XCTAssertEqual(object["volume"] as? String, "12")
        XCTAssertEqual(object["issue"] as? String, "3")
        XCTAssertEqual(object["page"] as? String, "10-20")
        XCTAssertEqual(object["DOI"] as? String, "10.1000/test")
        XCTAssertNil(object["URL"])
        XCTAssertEqual(authors, [
            ["family": "Doe", "given": "Jane"],
            ["family": "Smith", "given": "John"],
        ])
        XCTAssertEqual(dateParts, [[2024]])
    }

    func testCSLJSONObjectDoesNotExportURLForJournalArticle() {
        let reference = Reference(
            id: 43,
            title: "CNKI Article",
            year: 2024,
            url: "https://kns.cnki.net/kcms2/article/abstract?v=test",
            referenceType: .journalArticle
        )

        let object = reference.cslJSONObject()

        XCTAssertNil(object["URL"])
    }

    func testCSLJSONObjectExportsURLForWebpage() {
        let reference = Reference(
            id: 44,
            title: "SwiftLib Homepage",
            url: "https://example.com/article",
            referenceType: .webpage
        )

        let object = reference.cslJSONObject()

        XCTAssertEqual(object["URL"] as? String, "https://example.com/article")
    }

    func testCSLJSONObjectReturnsEmptyDictionaryWhenReferenceHasNoID() {
        let reference = Reference(title: "Untitled")

        XCTAssertTrue(reference.cslJSONObject().isEmpty)
    }
}
