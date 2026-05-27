import XCTest
@testable import SwiftLibCore

// ---------------------------------------------------------------------------
// CitationGoldenSnapshotTests
//
// Regression suite that renders every corpus fixture against 6 builtin styles
// using CitationRenderer (citeproc-js) and writes the output to a snapshot
// file on first run. Subsequent runs compare against the stored snapshot.
//
// USAGE
// -----
// First run: set SWIFTLIB_UPDATE_SNAPSHOTS=1 to generate the snapshot file.
//
//   SWIFTLIB_UPDATE_SNAPSHOTS=1 swift test --filter CitationGoldenSnapshotTests
//
// Normal run (CI): run without the env var. Tests fail if output differs from
// the stored snapshot.
//
// The snapshot file lives at:
//   Tests/SwiftLibCoreTests/Fixtures/citation-corpus/snapshots.json
// ---------------------------------------------------------------------------

private struct CorpusFixture: Decodable {
    struct Author: Decodable { var given: String?; var family: String }
    var id: String
    var label: String
    var title: String
    var type: String
    var authors: [Author]?
    var year: Int?
    var journal: String?
    var volume: String?
    var issue: String?
    var pages: String?
    var doi: String?
    var url: String?
    var siteName: String?
    var accessedDate: String?
    var publisher: String?
    var publisherPlace: String?
    var edition: String?
    var isbn: String?
    var institution: String?
    var genre: String?
    var language: String?
    var number: String?
}

private typealias Snapshots = [String: [String: String]]  // fixtureID → styleID → renderedBib

final class CitationGoldenSnapshotTests: XCTestCase {

    private let styles = ["apa", "ieee", "vancouver", "nature", "chicago", "harvard"]
    private static let snapshotPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/citation-corpus/snapshots.json")

    // MARK: - Golden snapshot test

    func testGoldenSnapshots() throws {
        let fixtures = try loadCorpus()
        let update = ProcessInfo.processInfo.environment["SWIFTLIB_UPDATE_SNAPSHOTS"] == "1"

        var snapshots: Snapshots = [:]
        if !update, FileManager.default.fileExists(atPath: Self.snapshotPath.path) {
            let data = try Data(contentsOf: Self.snapshotPath)
            snapshots = (try? JSONDecoder().decode(Snapshots.self, from: data)) ?? [:]
        }

        var updated: Snapshots = [:]
        var failures: [String] = []

        let refs = fixtures.map { fixture in
            (fixture, makeReference(from: fixture, dbID: Int64(fixture.id.hashValue & 0x7FFF_FFFF) + 1))
        }
        for fixture in fixtures {
            updated[fixture.id] = [:]
        }

        // Iterate style-first so the citeproc engine pool can reuse the current
        // JSContext. Iterating fixture-first repeatedly rebuilds heavyweight
        // engines when the style count exceeds the pool size.
        for style in styles {
            CitationRenderer.invalidate(styleID: style)
            for (fixture, ref) in refs {
                let rendered = CitationRenderer.renderBibliographyEntry(ref, styleID: style)
                updated[fixture.id]?[style] = rendered

                if !update, let expected = snapshots[fixture.id]?[style], rendered != expected {
                    failures.append("[\(fixture.id)/\(style)]\nExpected: \(expected)\nGot:      \(rendered)")
                }
            }
        }

        if update {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated)
            try data.write(to: Self.snapshotPath)
            print("[CitationGoldenSnapshotTests] Snapshots updated at \(Self.snapshotPath.path)")
            return
        }

        // First-run: no snapshot file yet — generate it silently
        if snapshots.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated)
            try data.write(to: Self.snapshotPath)
            print("[CitationGoldenSnapshotTests] Snapshot file created; re-run to validate.")
            return
        }

        XCTAssertTrue(failures.isEmpty,
                      "Golden snapshot mismatches:\n\n" + failures.joined(separator: "\n\n"))
    }

    // MARK: - Helpers

    private func loadCorpus() throws -> [CorpusFixture] {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/citation-corpus/corpus.json")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode([CorpusFixture].self, from: data)
    }

    private func makeReference(from f: CorpusFixture, dbID: Int64) -> Reference {
        let refType: ReferenceType = {
            switch f.type {
            case "journalArticle": return .journalArticle
            case "book":           return .book
            case "bookSection":    return .bookSection
            case "thesis":         return .thesis
            case "conferencePaper":return .conferencePaper
            case "preprint":       return .preprint
            case "webpage":        return .webpage
            case "report":         return .report
            case "patent":         return .patent
            default:               return .other
            }
        }()

        let authors: [AuthorName] = (f.authors ?? []).map {
            AuthorName(given: $0.given ?? "", family: $0.family)
        }

        return Reference(
            id: dbID,
            title: f.title,
            authors: authors,
            year: f.year,
            journal: f.journal,
            volume: f.volume,
            issue: f.issue,
            pages: f.pages,
            doi: f.doi,
            url: f.url,
            referenceType: refType,
            verificationStatus: .legacy,
            publisher: f.publisher,
            publisherPlace: f.publisherPlace,
            edition: f.edition,
            isbn: f.isbn,
            accessedDate: f.accessedDate,
            genre: f.genre,
            institution: f.institution,
            number: f.number,
            language: f.language
        )
    }
}
