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

    func testParseCSLJSONResponseMapsDOIFallbackMetadata() throws {
        let json = """
        {
          "type": "article-journal",
          "title": "Fallback Paper",
          "author": [
            {"family": "Carpenter", "given": "S R"},
            {"family": "Vander Zanden", "given": "M J"}
          ],
          "issued": {"date-parts": [[2025, 4, 1]]},
          "container-title": "Aquatic Ecology",
          "volume": "59",
          "issue": "2",
          "page": "101-112",
          "DOI": "10.1080/example"
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCSLJSONResponse(json, doi: "10.1080/example")

        XCTAssertEqual(reference.title, "Fallback Paper")
        XCTAssertEqual(reference.authors, [
            AuthorName(given: "S R", family: "Carpenter"),
            AuthorName(given: "M J", family: "Vander Zanden"),
        ])
        XCTAssertEqual(reference.year, 2025)
        XCTAssertEqual(reference.journal, "Aquatic Ecology")
        XCTAssertEqual(reference.pages, "101-112")
        XCTAssertEqual(reference.referenceType, .journalArticle)
    }

    // MARK: - CJK Author Name Swap Heuristic

    /// CrossRef correctly returns given=Wei, family=Yang for the paper
    /// "Seasonal dynamics of crustacean zooplankton … in Erhai Lake" (DOI 10.1007/s00343-014-3204-5).
    /// Both Wei and Yang are known romanized Chinese surnames → ambiguous → NOT swapped.
    func testParseCrossrefResponseDoesNotSwapCorrectChineseAuthor() throws {
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.1007/s00343-014-3204-5",
            "type": "journal-article",
            "title": ["Seasonal dynamics of crustacean zooplankton community structure in Erhai Lake"],
            "author": [
              {"given": "Wei",    "family": "Yang",   "sequence": "first"},
              {"given": "Daogui", "family": "Deng",   "sequence": "additional"},
              {"given": "Sai",    "family": "Zhang",  "sequence": "additional"},
              {"given": "Cuilin", "family": "Hu",     "sequence": "additional"}
            ],
            "published-print": {"date-parts": [[2014]]}
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json, doi: "10.1007/s00343-014-3204-5")

        // First author: CrossRef is correct — Yang is the surname, Wei is the given name.
        // Must NOT be swapped to family=Wei, given=Yang.
        XCTAssertEqual(reference.authors[0].family, "Yang")
        XCTAssertEqual(reference.authors[0].given,  "Wei")
        // Third author: Zhang is a surname (5 chars) — must NOT be swapped with Sai.
        XCTAssertEqual(reference.authors[2].family, "Zhang")
        XCTAssertEqual(reference.authors[2].given,  "Sai")
        // Fourth author: Hu is short, Cuilin(6) is clearly a given name — Cuilin should stay as given.
        // (CrossRef returns given=Cuilin, family=Hu — already in correct order, no swap needed.)
        XCTAssertEqual(reference.authors[3].family, "Hu")
        XCTAssertEqual(reference.authors[3].given,  "Cuilin")
    }

    /// CrossRef mistakenly swaps surname/given for some Chinese authors:
    /// `given=Lu, family=Huibin` should become family=Lu, given=Huibin (Huibin=6 chars).
    func testParseCrossrefResponseCorrectsCJKSurnameInGivenSlot() throws {
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.18307/2016.0115",
            "type": "journal-article",
            "title": ["Cladoceran community responses to eutrophication"],
            "author": [
              {"given": "Lu",  "family": "Huibin",  "sequence": "first"},
              {"given": "Wu",  "family": "Haoyun",  "sequence": "additional"}
            ],
            "published-print": {"date-parts": [[2016]]}
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json, doi: "10.18307/2016.0115")

        // CrossRef has surname and given swapped — must be corrected.
        XCTAssertEqual(reference.authors[0].family, "Lu")
        XCTAssertEqual(reference.authors[0].given,  "Huibin")
        XCTAssertEqual(reference.authors[1].family, "Wu")
        XCTAssertEqual(reference.authors[1].given,  "Haoyun")
    }

    /// Regression: [37] RAMAEKERS L, TOM P, LUC B — the old >=6 length threshold
    /// incorrectly swapped given=Tom(3)/family=Pinceel(7) and given=Luc(3)/family=Brendonck(9).
    /// The new pinyin-dictionary approach must NOT swap Western names.
    func testParseCrossrefResponseDoesNotSwapWesternNamesLookingLikeCJK() throws {
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.1111/j.1365-2427.2009.02341.x",
            "type": "journal-article",
            "title": ["Large-scale community reshuffling in Anostraca"],
            "author": [
              {"given": "Luc",      "family": "Ramaekers",  "sequence": "first"},
              {"given": "Tom",      "family": "Pinceel",    "sequence": "additional"},
              {"given": "Luc",      "family": "Brendonck",  "sequence": "additional"}
            ],
            "published-print": {"date-parts": [[2010]]}
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json,
            doi: "10.1111/j.1365-2427.2009.02341.x")

        XCTAssertEqual(reference.authors.count, 3)
        // Ramaekers — "Luc" is not a known pinyin surname → no swap
        XCTAssertEqual(reference.authors[0].family, "Ramaekers")
        XCTAssertEqual(reference.authors[0].given,  "Luc")
        // Pinceel — "Tom" is not a known pinyin surname → no swap
        XCTAssertEqual(reference.authors[1].family, "Pinceel")
        XCTAssertEqual(reference.authors[1].given,  "Tom")
        // Brendonck — "Luc" is not a known pinyin surname → no swap
        XCTAssertEqual(reference.authors[2].family, "Brendonck")
        XCTAssertEqual(reference.authors[2].given,  "Luc")
    }

    /// sequence=first anchors the first author correctly even when the API array does not
    /// have the sequence=first author at index 0.
    func testBuildCrossRefAuthorsAnchorsFirstAuthorBySequence() throws {
        // Simulate a CrossRef response where sequence=first is not the first array element.
        let json = """
        {
          "status": "ok",
          "message": {
            "DOI": "10.1360/csb2013-58-10-855",
            "type": "journal-article",
            "title": ["湖泊富营养化及其生态系统响应"],
            "author": [
              {"given": "Boqiang",  "family": "Qin",    "sequence": "additional"},
              {"given": "Yunlin",   "family": "Zhang",  "sequence": "first"}
            ],
            "published-print": {"date-parts": [[2013]]}
          }
        }
        """.data(using: .utf8)!

        let reference = try MetadataFetcher.parseCrossrefResponse(json,
            doi: "10.1360/csb2013-58-10-855")

        // Zhang Yunlin (sequence=first) should be at index 0.
        XCTAssertEqual(reference.authors[0].family, "Zhang")
        XCTAssertEqual(reference.authors[0].given,  "Yunlin")
        XCTAssertEqual(reference.authors[1].family, "Qin")
        XCTAssertEqual(reference.authors[1].given,  "Boqiang")
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

    // MARK: - Douban Detail Page Parser

    /// Fixture mimicking the live structure of
    /// https://book.douban.com/subject/1554675/ (《高级水生生物学》).
    /// Ensures the parser picks up ISBN (from meta tag), publisher, year, pages,
    /// and the author list from the `#info` block even when fields are nested
    /// in `<a>` tags.
    func testParseDoubanDetailExtractsCoreFields() {
        let html = """
        <html><head>
        <meta property="book:isbn" content="9787030069870" />
        </head><body>
        <div id="info">
          <span><span class="pl"> 作者</span>:
            <a class="" href="/author/">刘建康</a>
          </span><br/>
          <span class="pl">出版社:</span>
            <a href="/press/" class="a_publisher">科学出版社</a><br/>
          <span class="pl">出版年:</span> 1999-3<br/>
          <span class="pl">页数:</span> 401<br/>
          <span class="pl">定价:</span> 45.00元<br/>
          <span class="pl">ISBN:</span> 9787030069870<br/>
        </div>
        <div id="link-report">
          <div class="intro">
            <p>这是一本关于高级水生生物学的研究生教材。</p>
          </div>
        </div>
        </body></html>
        """
        let detail = MetadataFetcher.parseDoubanDetailHTML(html)
        XCTAssertEqual(detail.isbn, "9787030069870")
        XCTAssertEqual(detail.publisher, "科学出版社")
        XCTAssertEqual(detail.year, 1999)
        XCTAssertEqual(detail.pages, "401")
        XCTAssertEqual(detail.authors.map { $0.displayName.trimmingCharacters(in: .whitespaces) }.first, "刘建康")
        XCTAssertEqual(detail.abstract, "这是一本关于高级水生生物学的研究生教材。")
    }

    func testParseDoubanDetailReturnsEmptyWhenInfoBlockMissing() {
        let html = "<html><body><h1>404 Not Found</h1></body></html>"
        let detail = MetadataFetcher.parseDoubanDetailHTML(html)
        XCTAssertNil(detail.isbn)
        XCTAssertNil(detail.publisher)
        XCTAssertNil(detail.year)
        XCTAssertNil(detail.pages)
        XCTAssertTrue(detail.authors.isEmpty)
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
