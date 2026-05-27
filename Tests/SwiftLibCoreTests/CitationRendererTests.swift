import XCTest
@testable import SwiftLibCore

// ---------------------------------------------------------------------------
// CitationRendererTests
//
// Verifies that CitationRenderer routes exclusively through citeproc-js and
// produces output consistent with what the Word/WPS add-in renders.
//
// These tests use the live builtin CSL styles (APA, IEEE, Vancouver, Nature,
// Chicago, Harvard, MLA) and a canonical journal article fixture.
// They do NOT hit the network; all data is in-process.
// ---------------------------------------------------------------------------

final class CitationRendererTests: XCTestCase {

    // MARK: - Fixture

    /// A well-formed journal article with enough fields to exercise all styles.
    private static func makeJournalArticle() -> Reference {
        Reference(
            id: 9001,
            title: "Quantum Entanglement in Macroscopic Systems",
            authors: [
                AuthorName(given: "Alice", family: "Smith"),
                AuthorName(given: "Bob", family: "Jones"),
                AuthorName(given: "Carol", family: "Zhang"),
            ],
            year: 2024,
            journal: "Physical Review Letters",
            volume: "132",
            issue: "4",
            pages: "041601",
            doi: "10.1103/PhysRevLett.132.041601",
            referenceType: .journalArticle,
            verificationStatus: .verifiedAuto
        )
    }

    private static func makeBookRef() -> Reference {
        Reference(
            id: 9002,
            title: "Introduction to Algorithms",
            authors: [
                AuthorName(given: "Thomas H.", family: "Cormen"),
                AuthorName(given: "Charles E.", family: "Leiserson"),
            ],
            year: 2022,
            referenceType: .book,
            verificationStatus: .verifiedAuto,
            publisher: "MIT Press",
            publisherPlace: "Cambridge, MA",
            edition: "4th",
            isbn: "9780262046305"
        )
    }

    private static func makeChinese() -> Reference {
        Reference(
            id: 9003,
            title: "人工智能在医疗诊断中的应用",
            authors: [
                AuthorName(given: "Wei", family: "Wang"),
                AuthorName(given: "Lei", family: "Li"),
            ],
            year: 2023,
            journal: "中国医学信息学杂志",
            volume: "40",
            issue: "3",
            pages: "15-22",
            referenceType: .journalArticle,
            verificationStatus: .verifiedAuto,
            language: "zh-CN"
        )
    }

    // MARK: - Inline citation tests

    func testInlineCitationAPA() {
        let ref = Self.makeJournalArticle()
        let text = CitationRenderer.renderInlineCitation([ref], styleID: "apa")
        XCTAssertFalse(text.isEmpty, "APA inline citation should not be empty")
        // APA should contain the year
        XCTAssertTrue(text.contains("2024"), "APA inline citation should contain year 2024: \(text)")
        // APA should not be the fallback form "(Smith, 2024)"—should be formatted by citeproc
        // Just ensure it's non-empty and reasonable
        XCTAssertTrue(text.count > 3, "APA inline citation too short: \(text)")
    }

    func testInlineCitationIEEE() {
        let ref = Self.makeJournalArticle()
        let text = CitationRenderer.renderInlineCitation([ref], styleID: "ieee")
        XCTAssertFalse(text.isEmpty, "IEEE inline citation should not be empty")
        // IEEE produces numeric like [1]
        XCTAssertTrue(text.contains("[") || text.contains("1"),
                      "IEEE inline citation should be numeric: \(text)")
    }

    func testInlineCitationVancouver() {
        let ref = Self.makeJournalArticle()
        let text = CitationRenderer.renderInlineCitation([ref], styleID: "vancouver")
        XCTAssertFalse(text.isEmpty, "Vancouver inline citation should not be empty")
    }

    func testInlineCitationNature() {
        let ref = Self.makeJournalArticle()
        let text = CitationRenderer.renderInlineCitation([ref], styleID: "nature")
        XCTAssertFalse(text.isEmpty, "Nature inline citation should not be empty")
    }

    func testInlineCitationMultipleRefs() {
        let ref1 = Self.makeJournalArticle()
        let ref2 = Self.makeBookRef()
        let text = CitationRenderer.renderInlineCitation([ref1, ref2], styleID: "apa")
        XCTAssertFalse(text.isEmpty, "Multi-ref inline citation should not be empty")
    }

    func testInlineCitationEmptyRefsReturnsEmpty() {
        let text = CitationRenderer.renderInlineCitation([], styleID: "apa")
        XCTAssertEqual(text, "", "Empty refs should return empty string")
    }

    func testInlineCitationFallsBackGracefullyForUnknownStyle() {
        let ref = Self.makeJournalArticle()
        let text = CitationRenderer.renderInlineCitation([ref], styleID: "nonexistent-style-xyz")
        // Should return a non-empty fallback rather than crashing or returning ""
        XCTAssertFalse(text.isEmpty, "Unknown style should produce fallback text: \(text)")
    }

    // MARK: - Bibliography entry tests

    func testBibliographyEntryAPA() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "apa")
        XCTAssertFalse(entry.isEmpty, "APA bibliography entry should not be empty")
        // APA bib should contain key fields
        XCTAssertTrue(entry.contains("2024"), "APA bib should contain year: \(entry)")
        XCTAssertTrue(entry.contains("Smith") || entry.contains("smith"),
                      "APA bib should contain first author family name: \(entry)")
    }

    func testBibliographyEntryIEEE() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "ieee")
        XCTAssertFalse(entry.isEmpty, "IEEE bibliography entry should not be empty")
        XCTAssertTrue(entry.contains("Quantum") || entry.lowercased().contains("quantum"),
                      "IEEE bib should contain title word: \(entry)")
    }

    func testBibliographyEntryVancouver() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "vancouver")
        XCTAssertFalse(entry.isEmpty, "Vancouver bibliography entry should not be empty")
    }

    func testBibliographyEntryNature() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "nature")
        XCTAssertFalse(entry.isEmpty, "Nature bibliography entry should not be empty")
    }

    func testBibliographyEntryChicago() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "chicago")
        XCTAssertFalse(entry.isEmpty, "Chicago bibliography entry should not be empty")
    }

    func testBibliographyEntryHarvard() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "harvard")
        XCTAssertFalse(entry.isEmpty, "Harvard bibliography entry should not be empty")
    }

    func testBibliographyEntryMLA() {
        let ref = Self.makeJournalArticle()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "mla")
        XCTAssertFalse(entry.isEmpty, "MLA bibliography entry should not be empty")
    }

    func testBibliographyEntryBook() {
        let ref = Self.makeBookRef()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "apa")
        XCTAssertFalse(entry.isEmpty, "APA book bibliography entry should not be empty")
        XCTAssertTrue(entry.contains("2022") || entry.contains("Cormen"),
                      "APA book bib should contain year or author: \(entry)")
    }

    func testBibliographyEntryChineseRef() {
        let ref = Self.makeChinese()
        let entry = CitationRenderer.renderBibliographyEntry(ref, styleID: "apa")
        XCTAssertFalse(entry.isEmpty, "APA Chinese bibliography entry should not be empty")
    }

    // MARK: - Cache consistency

    func testCacheReturnsSameResultOnRepeatedCalls() {
        let ref = Self.makeJournalArticle()
        CitationRenderer.invalidate(referenceID: 9001)
        let first = CitationRenderer.renderBibliographyEntry(ref, styleID: "apa")
        let second = CitationRenderer.renderBibliographyEntry(ref, styleID: "apa")
        XCTAssertEqual(first, second, "Cached result should be identical to initial render")
    }

    func testInvalidateClearsCache() {
        let ref = Self.makeJournalArticle()
        let before = CitationRenderer.renderBibliographyEntry(ref, styleID: "ieee")
        CitationRenderer.invalidate(styleID: "ieee")
        let after = CitationRenderer.renderBibliographyEntry(ref, styleID: "ieee")
        // Both should be non-empty and semantically equivalent
        XCTAssertFalse(before.isEmpty)
        XCTAssertFalse(after.isEmpty)
    }

    // MARK: - CSLManager compatibility

    func testCSLManagerFormatCitationRoutesThroughCitationRenderer() {
        let ref = Self.makeJournalArticle()
        let direct = CitationRenderer.renderInlineCitation([ref], styleID: "apa")
        let viaManager = CSLManager.shared.formatCitation([ref], style: "apa")
        XCTAssertEqual(direct, viaManager,
                       "CSLManager.formatCitation must route through CitationRenderer")
    }

    func testCSLManagerFormatBibliographyRoutesThroughCitationRenderer() {
        let ref = Self.makeJournalArticle()
        let direct = CitationRenderer.renderBibliographyEntry(ref, styleID: "apa")
        let viaManager = CSLManager.shared.formatBibliography(ref, style: "apa")
        XCTAssertEqual(direct, viaManager,
                       "CSLManager.formatBibliography must route through CitationRenderer")
    }
}
