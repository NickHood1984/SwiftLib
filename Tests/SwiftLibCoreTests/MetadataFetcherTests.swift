import XCTest
@testable import SwiftLibCore

final class MetadataFetcherTests: XCTestCase {
    func testParsePubMedResponseSetsPMIDAndPMCID() throws {
        let json = """
        {
          "result": {
            "uids": ["12345"],
            "12345": {
              "title": "Sample PubMed Article.",
              "pubdate": "2024 Jan 02",
              "source": "Journal of Tests",
              "volume": "12",
              "issue": "3",
              "pages": "100-120",
              "authors": [
                { "name": "Smith J" },
                { "name": "Doe J" }
              ],
              "articleids": [
                { "idtype": "doi", "value": "10.1000/test-doi" },
                { "idtype": "pmc", "value": "PMC999999" }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parsePubMedResponse(json, pmid: "12345")

        XCTAssertEqual(reference.title, "Sample PubMed Article")
        XCTAssertEqual(reference.pmid, "12345")
        XCTAssertEqual(reference.pmcid, "PMC999999")
        XCTAssertEqual(reference.doi, "10.1000/test-doi")
        XCTAssertEqual(reference.year, 2024)
    }

    func testParseArXivResponseUsesIdentifierForCanonicalURL() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2301.07041v2</id>
            <published>2023-01-17T00:00:00Z</published>
            <title>  Example   arXiv   Title  </title>
            <summary>  Example abstract. </summary>
            <author><name>Doe, Jane</name></author>
          </entry>
        </feed>
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseArXivResponse(xml, arxivId: "2301.07041")

        XCTAssertEqual(reference.title, "Example arXiv Title")
        XCTAssertEqual(reference.url, "https://arxiv.org/abs/2301.07041")
        XCTAssertEqual(reference.year, 2023)
        XCTAssertEqual(reference.authors, [AuthorName.parse("Doe, Jane")])
    }

    // MARK: - CrossRef CJK Author Name Tests

    func testParseCrossrefResponseSwapsCJKAuthorNames() throws {
        // CrossRef returns given/family swapped for Chinese authors:
        // {"given":"Wu","family":"Haoyun"} should become given:"Haoyun", family:"Wu"
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.18307/2023.0320",
            "type": "journal-article",
            "title": ["Research on multi-objective driven dispatching water level of Lake Taihu"],
            "author": [
              {"given": "Wu", "family": "Haoyun", "sequence": "first"},
              {"given": "Liu", "family": "Min", "sequence": "additional"},
              {"given": "Jin", "family": "Ke", "sequence": "additional"}
            ],
            "container-title": ["Journal of Lake Sciences"],
            "published-print": {"date-parts": [[2023]]},
            "volume": "35",
            "issue": "3",
            "page": "1009-1021"
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json, doi: "10.18307/2023.0320")

        // After correction: "Wu" (2 chars, likely family) should be in family field
        XCTAssertEqual(reference.authors.count, 3)
        XCTAssertEqual(reference.authors[0].family, "Wu")
        XCTAssertEqual(reference.authors[0].given, "Haoyun")
        // "Liu"/"Min" are equal-length (3 chars each) — ambiguous, not swapped.
        // ChineseMetadataMergePolicy will correct these from CNKI data later.
        XCTAssertEqual(reference.authors[1].given, "Liu")
        XCTAssertEqual(reference.authors[1].family, "Min")
        XCTAssertEqual(reference.title, "Research on multi-objective driven dispatching water level of Lake Taihu")
        XCTAssertEqual(reference.doi, "10.18307/2023.0320")
    }

    func testParseCrossrefResponseKeepsWesternAuthorNamesUnchanged() throws {
        // Western names with longer given names should NOT be swapped
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.1002/test",
            "type": "journal-article",
            "title": ["A Test Paper"],
            "author": [
              {"given": "John William", "family": "Smith", "sequence": "first"},
              {"given": "Alice", "family": "Johnson", "sequence": "additional"}
            ],
            "published-print": {"date-parts": [[2024]]}
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json, doi: "10.1002/test")

        XCTAssertEqual(reference.authors[0].given, "John William")
        XCTAssertEqual(reference.authors[0].family, "Smith")
        XCTAssertEqual(reference.authors[1].given, "Alice")
        XCTAssertEqual(reference.authors[1].family, "Johnson")
    }

    func testParseCrossrefResponseHandlesOrganizationAuthor() throws {
        // CrossRef sometimes has organization names in "name" field
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.1002/org",
            "type": "journal-article",
            "title": ["Org Paper"],
            "author": [
              {"name": "World Health Organization"},
              {"given": "Test", "family": "Author"}
            ],
            "published-print": {"date-parts": [[2024]]}
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json, doi: "10.1002/org")

        XCTAssertEqual(reference.authors.count, 2)
        // "Test"(4 chars) / "Author"(6 chars): given > 3 chars, NOT treated as CJK swap
        XCTAssertEqual(reference.authors[1].given, "Test")
        XCTAssertEqual(reference.authors[1].family, "Author")
    }

    // MARK: - Retry/Error Classification

    func testHTTP429IsRetryable() {
        let error = MetadataFetcher.FetchError.httpError(429)
        XCTAssertTrue(error.isRetryable, "429 rate-limit errors should be retryable")
    }

    func testHTTP500IsRetryable() {
        let error = MetadataFetcher.FetchError.httpError(500)
        XCTAssertTrue(error.isRetryable, "500 server errors should be retryable")
    }

    func testHTTP404IsNotRetryable() {
        let error = MetadataFetcher.FetchError.httpError(404)
        XCTAssertFalse(error.isRetryable, "404 not-found errors should not be retryable")
    }
}
