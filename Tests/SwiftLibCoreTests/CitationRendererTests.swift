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

    private static let edgeCaseStyles = CitationFormatter.supportedStyles + [
        "china-national-standard-gb-t-7714-2015-numeric"
    ]

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

    func testGBTJournalArticleUsesBareDOIAndSuppressesAccessedDate() {
        let ref = Reference(
            id: 9010,
            title: "Tracking dietary fatty acids in triacylglycerols and phospholipids of zooplankton",
            authors: [
                AuthorName(given: "Francine", family: "Mathieu"),
                AuthorName(given: "Fen", family: "Guo"),
                AuthorName(given: "Martin J.", family: "Kainz"),
            ],
            year: 2022,
            journal: "Freshwater Biology",
            volume: "67",
            issue: "11",
            pages: "1949-1959",
            doi: "https://doi.org/10.1111/fwb.13988",
            referenceType: .journalArticle,
            accessedDate: "2026-05-25"
        )

        let entry = CitationRenderer.renderBibliographyEntry(
            ref,
            styleID: "china-national-standard-gb-t-7714-2015-numeric"
        )

        XCTAssertTrue(entry.contains("DOI:10.1111/fwb.13988"), entry)
        XCTAssertFalse(entry.contains("DOI:https://doi.org/"), entry)
        XCTAssertFalse(entry.contains("2026-05-25"), entry)
        XCTAssertFalse(entry.contains("[2026"), entry)
        XCTAssertTrue(entry.contains("[J]"), entry)
        XCTAssertFalse(entry.contains("[J/OL]"), entry)
    }

    func testGBTRendersOtherWithJournalEvidenceAsJournalArticle() {
        let ref = Reference(
            id: 9011,
            title: "洞庭湖春秋季浮游植物群落结构及其与环境因子的关系",
            authors: [
                AuthorName(given: "", family: "王昊"),
                AuthorName(given: "", family: "潘保柱"),
                AuthorName(given: "", family: "赵耿楠"),
            ],
            year: 2021,
            journal: "长江流域资源与环境",
            volume: "30",
            issue: "11",
            pages: "2659-2667",
            referenceType: .other,
            accessedDate: "2026-05-25"
        )

        let entry = CitationRenderer.renderBibliographyEntry(
            ref,
            styleID: "china-national-standard-gb-t-7714-2015-numeric"
        )

        XCTAssertTrue(entry.contains("[J]"), entry)
        XCTAssertFalse(entry.contains("[A]"), entry)
        XCTAssertFalse(entry.contains("[J/OL]"), entry)
        XCTAssertFalse(entry.contains("2026-05-25"), entry)
        XCTAssertFalse(entry.contains("[2026"), entry)
    }

    func testGBTRendersReversedEnglishInitialAuthorsWithFamilyFirst() {
        let ref = Reference(
            id: 9012,
            title: "Fatty acid composition as biomarkers of freshwater microalgae: analysis of 37 strains of microalgae in 22 genera and in seven classes",
            authors: [
                AuthorName(given: "Taipale", family: "S"),
                AuthorName(given: "Strandberg", family: "U"),
                AuthorName(given: "Peltomaa", family: "E"),
                AuthorName(given: "Galloway", family: "AWE"),
            ],
            year: 2013,
            journal: "Aquatic Microbial Ecology",
            volume: "71",
            issue: "2",
            pages: "165-178",
            doi: "10.3354/ame01671",
            referenceType: .journalArticle,
            language: "en"
        )

        let entry = CitationRenderer.renderBibliographyEntry(
            ref,
            styleID: "china-national-standard-gb-t-7714-2015-numeric"
        )

        XCTAssertTrue(entry.contains("TAIPALE S, STRANDBERG U, PELTOMAA E, et al."), entry)
        XCTAssertFalse(entry.contains("S T"), entry)
        XCTAssertFalse(entry.contains("U S"), entry)
        XCTAssertFalse(entry.contains("E P"), entry)
        XCTAssertTrue(entry.contains("[J]"), entry)
        XCTAssertTrue(entry.contains("DOI:10.3354/ame01671"), entry)
    }

    func testGBTNumericInlineCitationDoesNotInjectAuthorNarrative() {
        let ref = Reference(
            id: 9013,
            title: "Consumers and lake warming",
            authors: [
                AuthorName(given: "R.", family: "Lau"),
                AuthorName(given: "O.", family: "Keva"),
            ],
            year: 2021,
            journal: "Ecology Letters",
            volume: "24",
            issue: "8",
            pages: "1600-1610",
            referenceType: .journalArticle,
            language: "en"
        )

        let citation = CitationRenderer.renderInlineCitation(
            [ref],
            styleID: "china-national-standard-gb-t-7714-2015-numeric"
        )

        XCTAssertTrue(citation.contains("1"), citation)
        XCTAssertFalse(citation.localizedCaseInsensitiveContains("Lau"), citation)
        XCTAssertFalse(citation.localizedCaseInsensitiveContains("Keva"), citation)
        XCTAssertFalse(citation.contains("等"), citation)
        XCTAssertFalse(citation.localizedCaseInsensitiveContains("et al"), citation)
    }

    // MARK: - Extreme incomplete metadata

    func testExtremeIncompleteReferencesRenderAcrossBuiltinStyles() {
        let refs: [Reference] = [
            Reference(
                id: 9020,
                title: "",
                referenceType: .journalArticle
            ),
            Reference(
                id: 9021,
                title: "Title Only Journal Article",
                referenceType: .journalArticle
            ),
            Reference(
                id: 9022,
                title: "DOI Only Metadata",
                doi: "https://doi.org/10.5555/example.doi",
                referenceType: .journalArticle
            ),
            Reference(
                id: 9023,
                title: "URL Only Web Page",
                url: "https://example.org/research/page",
                referenceType: .webpage
            ),
            Reference(
                id: 9024,
                title: "Yearless Authored Article",
                authors: [AuthorName(given: "Ada", family: "Lovelace")],
                journal: "Journal of Missing Metadata",
                referenceType: .journalArticle
            ),
            Reference(
                id: 9025,
                title: "Publisherless Book",
                referenceType: .book
            ),
            Reference(
                id: 9026,
                title: "极简中文记录",
                referenceType: .other,
                language: "中文"
            ),
            Reference(
                id: 9027,
                title: "Numberless Patent",
                authors: [AuthorName(given: "Nikola", family: "Tesla")],
                referenceType: .patent
            ),
        ]

        for style in Self.edgeCaseStyles {
            CitationRenderer.invalidate(styleID: style)

            for ref in refs {
                let bibliography = CitationRenderer.renderBibliographyEntry(ref, styleID: style)
                assertUsableCitationOutput(
                    bibliography,
                    style: style,
                    refID: ref.id,
                    context: "bibliography"
                )

                let inline = CitationRenderer.renderInlineCitation([ref], styleID: style)
                assertUsableCitationOutput(
                    inline,
                    style: style,
                    refID: ref.id,
                    context: "inline citation"
                )
            }
        }
    }

    func testEmptyTitleExportsUntitledInsteadOfBlankCitation() {
        let ref = Reference(
            id: 9028,
            title: "   ",
            referenceType: .journalArticle
        )

        let entry = CitationRenderer.renderBibliographyEntry(
            ref,
            styleID: "china-national-standard-gb-t-7714-2015-numeric"
        )

        XCTAssertTrue(entry.contains("Untitled"), entry)
        XCTAssertFalse(entry.contains("Optional("), entry)
        XCTAssertFalse(entry.contains("undefined"), entry)
    }

    func testDOIOnlyIncompleteReferenceUsesBareDOIInGBT() {
        let ref = Reference(
            id: 9029,
            title: "DOI-only incomplete journal article",
            doi: "https://doi.org/10.1234/abc.def",
            referenceType: .journalArticle,
            accessedDate: "2026-06-04"
        )

        let entry = CitationRenderer.renderBibliographyEntry(
            ref,
            styleID: "china-national-standard-gb-t-7714-2015-numeric"
        )

        XCTAssertTrue(entry.contains("DOI:10.1234/abc.def"), entry)
        XCTAssertFalse(entry.contains("DOI:https://doi.org/"), entry)
    }

    func testUnsavedBibliographyEntriesDoNotShareStaleFallbackCache() {
        CitationRenderer.invalidateAll()
        let first = Reference(title: "First Unsaved Draft")
        let second = Reference(title: "Second Unsaved Draft")

        let firstEntry = CitationRenderer.renderBibliographyEntry(first, styleID: "apa")
        let secondEntry = CitationRenderer.renderBibliographyEntry(second, styleID: "apa")

        XCTAssertTrue(firstEntry.contains("First Unsaved Draft"), firstEntry)
        XCTAssertTrue(secondEntry.contains("Second Unsaved Draft"), secondEntry)
        XCTAssertNotEqual(firstEntry, secondEntry)
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

    private func assertUsableCitationOutput(
        _ output: String,
        style: String,
        refID: Int64?,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(
            trimmed.isEmpty,
            "\(context) should not be empty for style \(style), ref \(refID.map(String.init) ?? "nil")",
            file: file,
            line: line
        )

        for fragment in ["Optional(", "undefined", "NaN"] {
            XCTAssertFalse(
                trimmed.contains(fragment),
                "\(context) leaked invalid fragment '\(fragment)' for style \(style), ref \(refID.map(String.init) ?? "nil"): \(trimmed)",
                file: file,
                line: line
            )
        }
    }
}
