import XCTest
@testable import SwiftLibCore

final class CitationFormatterTests: XCTestCase {

    // MARK: - Supported Styles

    func testSupportedStylesContainsExpected() {
        let expected = ["apa", "mla", "chicago", "ieee", "harvard", "vancouver", "nature"]
        for style in expected {
            XCTAssertTrue(CitationFormatter.supportedStyles.contains(style),
                          "supportedStyles should contain \(style)")
        }
    }

    func testStylesJSONIsValidJSON() {
        let json = CitationFormatter.stylesJSON
        XCTAssertFalse(json.isEmpty)
        let data = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                         "stylesJSON should be valid JSON")
    }

    // MARK: - Citation Kind

    func testCitationKindForAPA() {
        let kind = CitationFormatter.citationKind(for: "apa")
        XCTAssertEqual(kind, .authorDate)
    }

    func testCitationKindForIEEE() {
        let kind = CitationFormatter.citationKind(for: "ieee")
        XCTAssertEqual(kind, .numeric)
    }

    func testCitationKindForVancouver() {
        let kind = CitationFormatter.citationKind(for: "vancouver")
        XCTAssertEqual(kind, .numeric)
    }

    func testCitationKindForNature() {
        let kind = CitationFormatter.citationKind(for: "nature")
        XCTAssertEqual(kind, .numeric)
    }

    func testCitationKindForBuiltInGBTStyleUsesCSLMetadata() {
        let kind = CitationFormatter.citationKind(for: "http://www.zotero.org/styles/china-national-standard-gb-t-7714-2015-numeric")
        XCTAssertEqual(kind, .numeric)
    }

    // MARK: - Format Inline Citation

    func testFormatInlineCitationAPA() {
        let ref = Reference(
            id: 1,
            title: "Test",
            authors: [AuthorName(given: "John", family: "Smith")],
            year: 2023
        )
        let result = CitationFormatter.formatInlineCitation([ref], style: "apa")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Smith"), "APA citation should contain author last name")
        XCTAssertTrue(result.contains("2023"), "APA citation should contain year")
    }

    func testFormatInlineCitationMultipleAuthorsAPA() {
        let ref = Reference(
            id: 1,
            title: "Multi",
            authors: [
                AuthorName(given: "Jane", family: "Doe"),
                AuthorName(given: "John", family: "Smith"),
                AuthorName(given: "Pat", family: "Lee"),
            ],
            year: 2024
        )
        let result = CitationFormatter.formatInlineCitation([ref], style: "apa")
        XCTAssertTrue(result.contains("et al."),
                      "APA citation with 3+ authors should use et al.")
    }

    func testFormatInlineCitationMultipleReferences() {
        let ref1 = Reference(
            id: 1,
            title: "First",
            authors: [AuthorName(given: "Jane", family: "Doe")],
            year: 2020
        )
        let ref2 = Reference(
            id: 2,
            title: "Second",
            authors: [AuthorName(given: "John", family: "Smith")],
            year: 2021
        )
        let result = CitationFormatter.formatInlineCitation([ref1, ref2], style: "apa")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Doe"), "Should contain first author")
        XCTAssertTrue(result.contains("Smith"), "Should contain second author")
    }

    // MARK: - Format Bibliography

    func testFormatBibliographyAPA() {
        let ref = Reference(
            id: 1,
            title: "A Study on Testing",
            authors: [AuthorName(given: "John", family: "Smith")],
            year: 2023,
            journal: "Test Journal",
            volume: "10",
            pages: "100-115"
        )
        let result = CitationFormatter.formatBibliography(ref, style: "apa")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Smith"), "Bibliography should contain author")
        XCTAssertTrue(result.contains("A Study on Testing"), "Bibliography should contain title")
    }

    func testFormatBibliographyAllStyles() {
        let ref = Reference(
            id: 1,
            title: "Style Test",
            authors: [AuthorName(given: "Jane", family: "Doe")],
            year: 2023,
            journal: "Test Journal"
        )
        for style in CitationFormatter.supportedStyles {
            let result = CitationFormatter.formatBibliography(ref, style: style)
            XCTAssertFalse(result.isEmpty,
                           "formatBibliography should return non-empty for style: \(style)")
        }
    }

    // MARK: - Numeric Citation

    func testFormatNumericInlineCitationIEEE() {
        let result = CitationFormatter.formatNumericInlineCitation(numbers: [1, 2, 3], style: "ieee")
        XCTAssertFalse(result.isEmpty)
    }

    func testFormatNumericBibliographyEntry() {
        let result = CitationFormatter.formatNumericBibliographyEntry(
            "Smith, J. A Study. Test Journal, 2023.",
            number: 1,
            style: "ieee"
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("1"), "Should contain the entry number")
    }

    // MARK: - Different Styles Produce Different Output

    func testDifferentStylesProduceDifferentBibliography() {
        let ref = Reference(
            id: 1,
            title: "Style Comparison",
            authors: [
                AuthorName(given: "John", family: "Smith"),
                AuthorName(given: "Jane", family: "Doe"),
            ],
            year: 2023,
            journal: "Test Journal",
            volume: "42",
            pages: "100-115"
        )
        let apa = CitationFormatter.formatBibliography(ref, style: "apa")
        let mla = CitationFormatter.formatBibliography(ref, style: "mla")
        let ieee = CitationFormatter.formatBibliography(ref, style: "ieee")

        // These styles have different formatting rules
        XCTAssertNotEqual(apa, ieee, "APA and IEEE should produce different output")
        XCTAssertNotEqual(apa, mla, "APA and MLA should produce different output")
    }
}
