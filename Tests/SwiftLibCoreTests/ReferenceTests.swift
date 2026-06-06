import XCTest
@testable import SwiftLibCore

final class ReferenceTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithTitle() {
        let ref = Reference(title: "Test Title")
        XCTAssertEqual(ref.title, "Test Title")
        XCTAssertNil(ref.id)
        XCTAssertNil(ref.year)
        XCTAssertNil(ref.journal)
        XCTAssertNil(ref.doi)
        XCTAssertNil(ref.pdfPath)
        XCTAssertTrue(ref.authors.isEmpty)
    }

    func testInitWithAllFields() {
        let ref = Reference(
            title: "Full Reference",
            authors: [AuthorName(given: "John", family: "Smith")],
            year: 2023,
            journal: "Test Journal",
            volume: "42",
            issue: "3",
            pages: "100-115",
            doi: "10.1234/test",
            url: "https://example.com",
            abstract: "This is an abstract.",
            notes: "Some notes."
        )
        XCTAssertEqual(ref.title, "Full Reference")
        XCTAssertEqual(ref.year, 2023)
        XCTAssertEqual(ref.journal, "Test Journal")
        XCTAssertEqual(ref.volume, "42")
        XCTAssertEqual(ref.issue, "3")
        XCTAssertEqual(ref.pages, "100-115")
        XCTAssertEqual(ref.doi, "10.1234/test")
        XCTAssertEqual(ref.url, "https://example.com")
        XCTAssertEqual(ref.abstract, "This is an abstract.")
        XCTAssertEqual(ref.notes, "Some notes.")
        XCTAssertEqual(ref.authors.count, 1)
    }

    // MARK: - Reference Type

    func testDefaultReferenceTypeIsJournalArticle() {
        let ref = Reference(title: "Default Type")
        XCTAssertEqual(ref.referenceType, .journalArticle)
    }

    func testAllReferenceTypesHaveIcons() {
        for type in ReferenceType.allCases {
            XCTAssertFalse(type.icon.isEmpty,
                           "\(type.rawValue) should have a non-empty icon")
        }
    }

    func testReferenceTypeRawValues() {
        XCTAssertEqual(ReferenceType.journalArticle.rawValue, "Journal Article")
        XCTAssertEqual(ReferenceType.magazineArticle.rawValue, "Magazine Article")
        XCTAssertEqual(ReferenceType.newspaperArticle.rawValue, "Newspaper Article")
        XCTAssertEqual(ReferenceType.preprint.rawValue, "Preprint")
        XCTAssertEqual(ReferenceType.book.rawValue, "Book")
        XCTAssertEqual(ReferenceType.bookSection.rawValue, "Book Section")
        XCTAssertEqual(ReferenceType.conferencePaper.rawValue, "Conference Paper")
        XCTAssertEqual(ReferenceType.thesis.rawValue, "Thesis")
        XCTAssertEqual(ReferenceType.dataset.rawValue, "Dataset")
        XCTAssertEqual(ReferenceType.software.rawValue, "Software")
        XCTAssertEqual(ReferenceType.standard.rawValue, "Standard")
        XCTAssertEqual(ReferenceType.manuscript.rawValue, "Manuscript")
        XCTAssertEqual(ReferenceType.interview.rawValue, "Interview")
        XCTAssertEqual(ReferenceType.presentation.rawValue, "Presentation")
        XCTAssertEqual(ReferenceType.blogPost.rawValue, "Blog Post")
        XCTAssertEqual(ReferenceType.forumPost.rawValue, "Forum Post")
        XCTAssertEqual(ReferenceType.legalCase.rawValue, "Legal Case")
        XCTAssertEqual(ReferenceType.legislation.rawValue, "Legislation")
        XCTAssertEqual(ReferenceType.webpage.rawValue, "Web Page")
        XCTAssertEqual(ReferenceType.report.rawValue, "Report")
        XCTAssertEqual(ReferenceType.patent.rawValue, "Patent")
        XCTAssertEqual(ReferenceType.other.rawValue, "Other")
    }

    func testReferenceTypeCSLTypeMappingForExpandedTypes() {
        XCTAssertEqual(ReferenceType.magazineArticle.cslType, "article-magazine")
        XCTAssertEqual(ReferenceType.newspaperArticle.cslType, "article-newspaper")
        XCTAssertEqual(ReferenceType.preprint.cslType, "article")
        XCTAssertEqual(ReferenceType.dataset.cslType, "dataset")
        XCTAssertEqual(ReferenceType.software.cslType, "software")
        XCTAssertEqual(ReferenceType.standard.cslType, "standard")
        XCTAssertEqual(ReferenceType.manuscript.cslType, "manuscript")
        XCTAssertEqual(ReferenceType.interview.cslType, "interview")
        XCTAssertEqual(ReferenceType.presentation.cslType, "speech")
        XCTAssertEqual(ReferenceType.blogPost.cslType, "post-weblog")
        XCTAssertEqual(ReferenceType.forumPost.cslType, "post")
        XCTAssertEqual(ReferenceType.legalCase.cslType, "legal_case")
        XCTAssertEqual(ReferenceType.legislation.cslType, "legislation")
    }

    func testCSLJSONObjectStripsDOIURLPrefix() {
        let ref = Reference(
            id: 1,
            title: "DOI Prefix",
            doi: "https://doi.org/10.1890/12-2010.1"
        )

        XCTAssertEqual(ref.cslJSONObject()["DOI"] as? String, "10.1890/12-2010.1")
        XCTAssertEqual(ref.toCSLItem().DOI, "10.1890/12-2010.1")
    }

    func testCSLJSONObjectSuppressesAccessedDateForStableJournalArticle() {
        let ref = Reference(
            id: 1,
            title: "Stable Journal Article",
            volume: "67",
            issue: "11",
            pages: "1949-1959",
            doi: "https://doi.org/10.1111/fwb.13988",
            referenceType: .journalArticle,
            accessedDate: "2026-05-25"
        )

        XCTAssertNil(ref.cslJSONObject()["accessed"])
        XCTAssertNil(ref.toCSLItem().accessed)
    }

    func testCSLJSONObjectKeepsAccessedDateForJournalArticleWithoutStableDetails() {
        let ref = Reference(
            id: 1,
            title: "Online First Journal Article",
            journal: "Freshwater Biology",
            doi: "10.1111/fwb.13988",
            referenceType: .journalArticle,
            accessedDate: "2026-05-25"
        )

        XCTAssertNotNil(ref.cslJSONObject()["accessed"])
        XCTAssertNotNil(ref.toCSLItem().accessed)
    }

    func testCSLJSONObjectKeepsAccessedDateForWebpage() {
        let ref = Reference(
            id: 1,
            title: "Web Page",
            url: "https://example.com",
            referenceType: .webpage,
            accessedDate: "2026-05-25"
        )

        XCTAssertNotNil(ref.cslJSONObject()["accessed"])
        XCTAssertNotNil(ref.toCSLItem().accessed)
    }

    func testCSLJSONObjectInfersJournalArticleTypeForOtherWithJournalEvidence() {
        let ref = Reference(
            id: 1,
            title: "洞庭湖春秋季浮游植物群落结构及其与环境因子的关系",
            journal: "长江流域资源与环境",
            volume: "30",
            issue: "11",
            pages: "2659-2667",
            referenceType: .other
        )

        XCTAssertEqual(ref.cslJSONObject()["type"] as? String, "article-journal")
        XCTAssertEqual(ref.toCSLItem().type, "article-journal")
    }

    func testCSLJSONObjectSuppressesAccessedDateForOtherWithStableJournalEvidence() {
        let ref = Reference(
            id: 1,
            title: "洞庭湖春秋季浮游植物群落结构及其与环境因子的关系",
            journal: "长江流域资源与环境",
            volume: "30",
            issue: "11",
            pages: "2659-2667",
            referenceType: .other,
            accessedDate: "2026-05-25"
        )

        XCTAssertEqual(ref.cslJSONObject()["type"] as? String, "article-journal")
        XCTAssertNil(ref.cslJSONObject()["accessed"])
        XCTAssertNil(ref.toCSLItem().accessed)
    }

    func testCSLJSONObjectUsesTypedExporterForCorporateAuthorsAndThesisArchive() {
        let ref = Reference(
            id: 10,
            title: "Water Quality Bulletin",
            authors: [AuthorName(given: "", family: "Ministry of Ecology and Environment")],
            year: 2024,
            referenceType: .thesis,
            genre: "Doctoral dissertation",
            institution: "Nanjing University"
        )

        let object = ref.cslJSONObject()
        let item = ref.toCSLItem()
        let authors = object["author"] as? [[String: String]]

        XCTAssertEqual(authors?.first?["literal"], "Ministry of Ecology and Environment")
        XCTAssertEqual(object["publisher"] as? String, "Nanjing University")
        XCTAssertEqual(object["archive"] as? String, "Nanjing University")
        XCTAssertEqual(item.author?.first?.literal, "Ministry of Ecology and Environment")
        XCTAssertEqual(item.archive, "Nanjing University")
    }

    // MARK: - AuthorName

    func testAuthorNameDisplayName() {
        let author = AuthorName(given: "John", family: "Smith")
        XCTAssertEqual(author.displayName, "John Smith")
    }

    func testAuthorNameDisplayNameWithEmptyGiven() {
        let author = AuthorName(given: "", family: "Smith")
        XCTAssertEqual(author.displayName, "Smith")
    }

    func testAuthorNameShortName() {
        let author = AuthorName(given: "John", family: "Smith")
        XCTAssertEqual(author.shortName, "Smith, J.")
    }

    func testAuthorNameShortNameMultipleGiven() {
        let author = AuthorName(given: "John Robert", family: "Smith")
        XCTAssertEqual(author.shortName, "Smith, J. R.")
    }

    // MARK: - AuthorName.parse

    func testParseGivenFamily() {
        let author = AuthorName.parse("John Smith")
        XCTAssertEqual(author.given, "John")
        XCTAssertEqual(author.family, "Smith")
    }

    func testParseFamilyCommaGiven() {
        let author = AuthorName.parse("Smith, John")
        XCTAssertEqual(author.given, "John")
        XCTAssertEqual(author.family, "Smith")
    }

    func testParseSingleName() {
        let author = AuthorName.parse("Aristotle")
        XCTAssertEqual(author.family, "Aristotle")
        XCTAssertTrue(author.given.isEmpty)
    }

    // MARK: - AuthorName.parseList

    func testParseListWithAnd() {
        let authors = AuthorName.parseList("Smith, John and Doe, Jane")
        XCTAssertEqual(authors, [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe"),
        ])
    }

    func testParseListWithSemicolon() {
        let authors = AuthorName.parseList("Smith, John; Doe, Jane")
        XCTAssertEqual(authors.count, 2)
        XCTAssertEqual(authors[0].family, "Smith")
        XCTAssertEqual(authors[1].family, "Doe")
    }

    func testParseListWithCommaSeparatedPairs() {
        let authors = AuthorName.parseList("Smith, John, Doe, Jane")
        XCTAssertEqual(authors.count, 2)
        XCTAssertEqual(authors[0], AuthorName(given: "John", family: "Smith"))
        XCTAssertEqual(authors[1], AuthorName(given: "Jane", family: "Doe"))
    }

    func testParseListWithFamilyInitialsDisplayString() {
        let authors = AuthorName.parseList("Carpenter S R, Stanley E H, Vander Zanden M J")
        XCTAssertEqual(authors, [
            AuthorName(given: "S R", family: "Carpenter"),
            AuthorName(given: "E H", family: "Stanley"),
            AuthorName(given: "M J", family: "Vander Zanden"),
        ])
    }

    func testParseListKeepsCompoundFamilyNamesWithInitials() {
        let authors = AuthorName.parseList("Dalsgaard J, St. John M, Kattner G, de Senerpont Domis L N, Müller-Navarra D C")
        XCTAssertEqual(authors, [
            AuthorName(given: "J", family: "Dalsgaard"),
            AuthorName(given: "M", family: "St. John"),
            AuthorName(given: "G", family: "Kattner"),
            AuthorName(given: "L N", family: "de Senerpont Domis"),
            AuthorName(given: "D C", family: "Müller-Navarra"),
        ])
    }

    func testParseListHandlesGBTEnglishFamilyInitialsBibliographyAuthors() {
        let taipale = AuthorName.parseList("TAIPALE S J, STRANDBERG U, PELTOMAA E")
        XCTAssertEqual(taipale.prefix(3), [
            AuthorName(given: "S J", family: "TAIPALE"),
            AuthorName(given: "U", family: "STRANDBERG"),
            AuthorName(given: "E", family: "PELTOMAA"),
        ])

        let strandberg = AuthorName.parseList("STRANDBERG U, TAIPALE S J, HILTUNEN M")
        XCTAssertEqual(strandberg.prefix(3), [
            AuthorName(given: "U", family: "STRANDBERG"),
            AuthorName(given: "S J", family: "TAIPALE"),
            AuthorName(given: "M", family: "HILTUNEN"),
        ])

        let vuorio = AuthorName.parseList("TAIPALE S J, VUORIO K, STRANDBERG U")
        XCTAssertEqual(vuorio.prefix(3), [
            AuthorName(given: "S J", family: "TAIPALE"),
            AuthorName(given: "K", family: "VUORIO"),
            AuthorName(given: "U", family: "STRANDBERG"),
        ])
    }

    func testAuthorNameValidationFlagsInitialOnlyReversal() {
        let issues = AuthorName.validationIssues(in: [
            AuthorName(given: "C S", family: "R"),
            AuthorName(given: "S R", family: "Carpenter"),
        ])

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].index, 0)
    }

    func testAuthorNameNormalizesMalformedChineseAuthorsForCitation() {
        let reversed = AuthorName.normalizedForCitation([
            AuthorName(given: "", family: "娟柴"),
            AuthorName(given: "", family: "勇角"),
            AuthorName(given: "", family: "鹏吴"),
            AuthorName(given: "", family: "越田"),
        ])
        XCTAssertEqual(reversed.map(\.family), ["柴娟", "角勇", "吴鹏", "田越"])

        let fused = AuthorName.normalizedForCitation([
            AuthorName(given: "潘保柱, 赵耿楠, 韩 谞, 蒋小明, 李典宝", family: "王 昊"),
        ])
        XCTAssertEqual(fused.map(\.family), ["王昊", "潘保柱", "赵耿楠", "韩谞", "蒋小明", "李典宝"])
    }

    func testAuthorNameNormalizesReversedEnglishInitialAuthorsForCitation() {
        let taipale = AuthorName.normalizedForCitation([
            AuthorName(given: "Taipale", family: "S"),
            AuthorName(given: "Strandberg", family: "U"),
            AuthorName(given: "Peltomaa", family: "E"),
        ])
        XCTAssertEqual(taipale, [
            AuthorName(given: "S", family: "Taipale"),
            AuthorName(given: "U", family: "Strandberg"),
            AuthorName(given: "E", family: "Peltomaa"),
        ])

        let strandberg = AuthorName.normalizedForCitation([
            AuthorName(given: "S. J. Taipale", family: "U."),
            AuthorName(given: "Hiltunen", family: "M."),
        ])
        XCTAssertEqual(strandberg, [
            AuthorName(given: "U", family: "S. J. Taipale"),
            AuthorName(given: "M", family: "Hiltunen"),
        ])

        let vuorio = AuthorName.normalizedForCitation([
            AuthorName(given: "Vuorio", family: "K."),
            AuthorName(given: "Strandberg", family: "U."),
        ])
        XCTAssertEqual(vuorio, [
            AuthorName(given: "K", family: "Vuorio"),
            AuthorName(given: "U", family: "Strandberg"),
        ])
    }

    func testAuthorNameDoesNotNormalizeUppercaseWesternFullNamesAsInitials() {
        let authors = [
            AuthorName(given: "SABINE", family: "HILT"),
            AuthorName(given: "MARINA", family: "MANCA"),
            AuthorName(given: "PEETER", family: "NÕGES"),
        ]

        XCTAssertEqual(AuthorName.normalizedForCitation(authors), authors)
    }

    func testAuthorNameDeduplicatesRepeatedAuthorSequences() {
        let uniqueAuthors = [
            AuthorName(given: "", family: "陈小锋"),
            AuthorName(given: "", family: "揣小明"),
            AuthorName(given: "", family: "杨柳燕"),
        ]

        XCTAssertEqual(
            AuthorName.deduplicatingRepeatedSequence(uniqueAuthors + uniqueAuthors),
            uniqueAuthors
        )
        XCTAssertEqual(
            AuthorName.deduplicatingRepeatedSequence(uniqueAuthors),
            uniqueAuthors
        )
    }

    func testParseListEmpty() {
        let authors = AuthorName.parseList("")
        XCTAssertTrue(authors.isEmpty)
    }

    // MARK: - Authors displayString

    func testAuthorsDisplayString() {
        let authors = [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe"),
        ]
        XCTAssertEqual(authors.displayString, "John Smith, Jane Doe")
    }

    func testEmptyAuthorsDisplayString() {
        let authors: [AuthorName] = []
        XCTAssertEqual(authors.displayString, "")
    }

    // MARK: - Dates

    func testDateAddedIsSetOnInit() {
        let before = Date()
        let ref = Reference(title: "Date Test")
        XCTAssertGreaterThanOrEqual(ref.dateAdded, before)
    }

    func testDateModifiedIsSetOnInit() {
        let before = Date()
        let ref = Reference(title: "Date Test")
        XCTAssertGreaterThanOrEqual(ref.dateModified, before)
    }

    // MARK: - Extended Metadata

    func testExtendedMetadataDefaults() {
        let ref = Reference(title: "Extended Test")
        XCTAssertNil(ref.publisher)
        XCTAssertNil(ref.publisherPlace)
        XCTAssertNil(ref.edition)
        XCTAssertNil(ref.editors)
        XCTAssertNil(ref.isbn)
        XCTAssertNil(ref.issn)
        XCTAssertNil(ref.accessedDate)
        XCTAssertNil(ref.translators)
        XCTAssertNil(ref.language)
        XCTAssertNil(ref.pmid)
        XCTAssertNil(ref.pmcid)
    }

    func testExtendedMetadataCanBeSet() {
        var ref = Reference(title: "Extended Set Test")
        ref.publisher = "Springer"
        ref.isbn = "978-3-16-148410-0"
        ref.language = "en"
        XCTAssertEqual(ref.publisher, "Springer")
        XCTAssertEqual(ref.isbn, "978-3-16-148410-0")
        XCTAssertEqual(ref.language, "en")
    }

    // MARK: - Collection Assignment

    func testCollectionIdDefaultsToNil() {
        let ref = Reference(title: "No Collection")
        XCTAssertNil(ref.collectionId)
    }

    func testCollectionIdCanBeSet() {
        var ref = Reference(title: "With Collection")
        ref.collectionId = 42
        XCTAssertEqual(ref.collectionId, 42)
    }

    // MARK: - parseRomanizedCJKAware

    func testParseRomanizedCJKAwareHandlesPinyinSurnameFirst() {
        // OpenAlex display_name "Zhang Sai" — surname Zhang first.
        XCTAssertEqual(
            AuthorName.parseRomanizedCJKAware("Zhang Sai"),
            AuthorName(given: "Sai", family: "Zhang")
        )
        // "Gong Li" — Gong is a known surname; result: family=Gong, given=Li.
        XCTAssertEqual(
            AuthorName.parseRomanizedCJKAware("Gong Li"),
            AuthorName(given: "Li", family: "Gong")
        )
        // "Zhang Li" — Zhang is a known surname; Li is also a surname (ambiguous),
        // but parseRomanizedCJKAware only checks the first token, so family=Zhang.
        XCTAssertEqual(
            AuthorName.parseRomanizedCJKAware("Zhang Li"),
            AuthorName(given: "Li", family: "Zhang")
        )
    }

    func testParseRomanizedCJKAwareFallsBackForWesternNames() {
        // Tom Pinceel — "Tom" is not a known pinyin surname → use western default.
        XCTAssertEqual(
            AuthorName.parseRomanizedCJKAware("Tom Pinceel"),
            AuthorName(given: "Tom", family: "Pinceel")
        )
        // Luc Brendonck — same.
        XCTAssertEqual(
            AuthorName.parseRomanizedCJKAware("Luc Brendonck"),
            AuthorName(given: "Luc", family: "Brendonck")
        )
        // Comma-delimited — should fall back to parse().
        XCTAssertEqual(
            AuthorName.parseRomanizedCJKAware("Smith, John"),
            AuthorName(given: "John", family: "Smith")
        )
    }

    // MARK: - pinyinSwapIssues

    func testPinyinSwapIssuesDetectsKnownSwap() {
        // given=Zhang is a known surname, family=Sai is not → flag as swap candidate.
        let issues = AuthorName.pinyinSwapIssues(in: [
            AuthorName(given: "Zhang", family: "Sai"),
        ])
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].index, 0)
        XCTAssertTrue(issues[0].message.contains("Zhang"))
    }

    func testPinyinSwapIssuesConservativeAboutAmbiguousCase() {
        // given=Gong is a surname, family=Li is ALSO a surname → ambiguous → NOT flagged.
        let issues = AuthorName.pinyinSwapIssues(in: [
            AuthorName(given: "Gong", family: "Li"),
        ])
        XCTAssertTrue(issues.isEmpty)
    }

    func testPinyinSwapRepaired() {
        let author = AuthorName(given: "Zhang", family: "Sai")
        let repaired = author.pinyinSwapRepaired()
        XCTAssertEqual(repaired.family, "Zhang")
        XCTAssertEqual(repaired.given, "Sai")
    }

    // MARK: - Hashable / Equatable

    func testReferencesWithSameIdAreEqual() {
        let ref1 = Reference(id: 1, title: "A")
        let ref2 = Reference(id: 1, title: "B")
        XCTAssertEqual(ref1, ref2)
    }

    func testReferencesWithDifferentIdsAreNotEqual() {
        let ref1 = Reference(id: 1, title: "A")
        let ref2 = Reference(id: 2, title: "A")
        XCTAssertNotEqual(ref1, ref2)
    }
}
