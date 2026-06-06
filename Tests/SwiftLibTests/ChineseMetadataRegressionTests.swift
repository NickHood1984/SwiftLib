import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class ChineseMetadataRegressionTests: XCTestCase {
    func testChineseLibraryCasesRouteAwayFromCrossRefWhenJournalLike() throws {
        let cases = try loadCases()
        let regressionCases = cases.filter(\.classification.needsChineseRefreshRegression)

        XCTAssertGreaterThanOrEqual(regressionCases.count, 20)

        for fixture in regressionCases {
            let reference = fixture.makeReference()
            let seed = MetadataResolutionSeed.fromReference(reference)

            XCTAssertTrue(
                seed.shouldSearchCNKI,
                "Expected CNKI routing seed for \(fixture.id): \(fixture.title)"
            )
            XCTAssertFalse(
                MetadataResolver.shouldUseCrossRefForRefresh(reference: reference, seed: seed),
                "Chinese journal-like refresh must not use CrossRef as primary for \(fixture.id): \(fixture.title)"
            )
        }
    }

    func testChineseLibraryCasesKeepRequiredCitationFieldsAfterCanonicalization() throws {
        let cases = try loadCases()

        for fixture in cases {
            let reference = fixture.makeReference()
            let canonical = ReferenceIntakeCanonicalizer.canonicalized(reference)
            let csl = CSLExportService.cslJSONObject(for: canonical)

            XCTAssertEqual(canonical.title, fixture.title, "Title changed unexpectedly for \(fixture.id)")
            XCTAssertFalse(canonical.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if fixture.classification.journalLike, fixture.referenceType == ReferenceType.journalArticle.rawValue {
                XCTAssertEqual(csl["type"] as? String, ReferenceType.journalArticle.cslType)
                XCTAssertEqual(csl["container-title"] as? String, canonical.journal)
                XCTAssertNotNil(csl["issued"], "Missing issued date for journal case \(fixture.id)")
            }

            if !canonical.authors.isEmpty {
                let cslAuthors = try XCTUnwrap(csl["author"] as? [[String: Any]], "Missing CSL authors for \(fixture.id)")
                XCTAssertEqual(cslAuthors.count, canonical.authors.count, "CSL author count drift for \(fixture.id)")
            }
        }
    }

    func testRepeatedAuthorSequencesFromRealLibraryAreAuditedAndRepaired() throws {
        let cases = try loadCases()
        let repeatedCases = cases
            .map { $0.makeReference() }
            .filter { AuthorName.deduplicatingRepeatedSequence($0.authors) != $0.authors }

        XCTAssertGreaterThanOrEqual(repeatedCases.count, 3)

        let audit = ReferenceLibraryAuditor.audit(repeatedCases)
        XCTAssertEqual(
            audit.issues.filter { $0.kind == .repeatedAuthorSequence }.count,
            repeatedCases.count
        )

        let repair = ReferenceLibraryRepairer.repairPlan(for: repeatedCases)
        XCTAssertEqual(repair.candidateCount, repeatedCases.count)
        XCTAssertTrue(
            repair.candidates.allSatisfy {
                $0.changes.contains { $0.kind == .removedRepeatedAuthorSequence }
            }
        )

        for reference in repeatedCases {
            let repaired = ReferenceLibraryRepairer.repairedReference(reference)
            XCTAssertEqual(repaired.authors, AuthorName.deduplicatingRepeatedSequence(reference.authors))
            XCTAssertLessThan(repaired.authors.count, reference.authors.count)
        }
    }

    func testChineseBookCasesAreNotForcedIntoJournalCrossRefBlock() throws {
        let cases = try loadCases()
        let bookCases = cases
            .map { $0.makeReference() }
            .filter { $0.referenceType == .book || $0.isbn?.swiftlib_nilIfBlank != nil }

        XCTAssertFalse(bookCases.isEmpty)

        for reference in bookCases {
            let seed = MetadataResolutionSeed.fromReference(reference)
            XCTAssertTrue(
                MetadataResolver.shouldUseCrossRefForRefresh(reference: reference, seed: seed),
                "Book-like Chinese record should follow book/identifier routing, not Chinese journal CrossRef blocking: \(reference.title)"
            )
        }
    }

    private func loadCases() throws -> [ChineseLibraryCase] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/metadata-regression/chinese-library-cases.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ChineseLibraryCase].self, from: data)
    }
}

private struct ChineseLibraryCase: Decodable {
    struct Classification: Decodable {
        var containsHanText: Bool
        var chineseSource: Bool
        var journalLike: Bool
        var bookLike: Bool
        var needsChineseRefreshRegression: Bool
        var mustNotUseCrossRefAsPrimary: Bool
        var authorCount: Int

        private enum CodingKeys: String, CodingKey {
            case containsHanText
            case chineseSource
            case journalLike
            case bookLike
            case needsChineseRefreshRegression
            case mustNotUseCrossRefAsPrimary
            case authorCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            containsHanText = try container.decodeFlexibleBool(forKey: .containsHanText)
            chineseSource = try container.decodeFlexibleBool(forKey: .chineseSource)
            journalLike = try container.decodeFlexibleBool(forKey: .journalLike)
            bookLike = try container.decodeFlexibleBool(forKey: .bookLike)
            needsChineseRefreshRegression = try container.decodeFlexibleBool(forKey: .needsChineseRefreshRegression)
            mustNotUseCrossRefAsPrimary = try container.decodeFlexibleBool(forKey: .mustNotUseCrossRefAsPrimary)
            authorCount = try container.decode(Int.self, forKey: .authorCount)
        }
    }

    var id: Int64
    var title: String
    var authors: [AuthorName]
    var year: Int?
    var journal: String?
    var volume: String?
    var issue: String?
    var pages: String?
    var doi: String?
    var isbn: String?
    var issn: String?
    var url: String?
    var referenceType: String
    var metadataSource: String?
    var language: String?
    var publisher: String?
    var publisherPlace: String?
    var institution: String?
    var genre: String?
    var classification: Classification

    func makeReference() -> Reference {
        var reference = Reference(
            id: id,
            title: title,
            authors: authors,
            year: year,
            journal: journal,
            volume: volume,
            issue: issue,
            pages: pages,
            doi: doi,
            url: url,
            referenceType: ReferenceType(rawValue: referenceType) ?? .other,
            publisher: publisher,
            publisherPlace: publisherPlace,
            isbn: isbn,
            issn: issn,
            genre: genre,
            institution: institution,
            language: language
        )
        reference.metadataSource = metadataSource.flatMap(MetadataSource.init(rawValue:))
        return reference
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleBool(forKey key: Key) throws -> Bool {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        return try decode(String.self, forKey: key) == "1"
    }
}
