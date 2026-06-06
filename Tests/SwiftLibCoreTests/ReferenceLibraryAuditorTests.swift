import XCTest
@testable import SwiftLibCore

final class ReferenceLibraryAuditorTests: XCTestCase {
    func testAuditReportsCitationMetadataIssues() {
        let ref = Reference(
            id: 1,
            title: "Problem Record",
            authors: [AuthorName(given: "C S", family: "R")],
            year: 2023,
            journal: "Test Journal",
            volume: "12",
            issue: "3",
            pages: "1-9",
            doi: "https://doi.org/10.1890/12-2010.1",
            referenceType: .other,
            accessedDate: "2026-05-25"
        )

        let report = ReferenceLibraryAuditor.audit([ref])
        let kinds = Set(report.issues.map(\.kind))

        XCTAssertEqual(report.referenceCount, 1)
        XCTAssertEqual(report.issueCount, 4)
        XCTAssertTrue(kinds.contains(.doiHasURLPrefix))
        XCTAssertTrue(kinds.contains(.stableJournalHasAccessedDate))
        XCTAssertTrue(kinds.contains(.suspiciousAuthorName))
        XCTAssertTrue(kinds.contains(.journalEvidenceWithOtherType))
    }

    func testAuditDoesNotFlagCleanStableJournalArticle() {
        let ref = Reference(
            id: 2,
            title: "Clean Record",
            authors: [AuthorName(given: "S J", family: "TAIPALE")],
            year: 2013,
            journal: "Aquatic Microbial Ecology",
            volume: "71",
            issue: "2",
            pages: "165-178",
            doi: "10.3354/ame01671",
            referenceType: .journalArticle
        )

        let report = ReferenceLibraryAuditor.audit([ref])

        XCTAssertTrue(report.issues.isEmpty)
    }

    func testAuditAndRepairKeepAccessedDateForOnlineFirstJournalWithoutStableDetails() {
        let ref = Reference(
            id: 4,
            title: "Online First",
            year: 2026,
            journal: "Freshwater Biology",
            doi: "10.1111/fwb.13988",
            referenceType: .journalArticle,
            accessedDate: "2026-05-25"
        )

        let audit = ReferenceLibraryAuditor.audit([ref])
        XCTAssertFalse(audit.issues.contains { $0.kind == .stableJournalHasAccessedDate })

        let repair = ReferenceLibraryRepairer.repairPlan(for: [ref])
        XCTAssertFalse(
            repair.candidates.flatMap(\.changes).contains { $0.kind == .removedStableJournalAccessedDate }
        )
    }

    func testAuditReportsProbableDuplicateTranslationFromGenericEvidence() {
        let english = Reference(
            id: 4,
            title: "Lakes in China",
            authors: [
                AuthorName(given: "S M", family: "WANG"),
                AuthorName(given: "H S", family: "DOU"),
            ],
            year: 1998,
            referenceType: .book,
            publisher: "Science Press",
            publisherPlace: "Beijing"
        )
        let chinese = Reference(
            id: 5,
            title: "中国湖泊志",
            authors: [
                AuthorName(given: "", family: "王苏民"),
                AuthorName(given: "", family: "窦鸿身"),
            ],
            year: 1998,
            referenceType: .book,
            publisher: "科学出版社",
            publisherPlace: "北京"
        )

        let report = ReferenceLibraryAuditor.audit([english, chinese])
        let issue = report.issues.first { $0.kind == ReferenceLibraryAuditIssueKind.probableDuplicateTranslation }

        XCTAssertEqual(issue?.referenceID, 4)
        XCTAssertTrue(issue?.message.contains("中国湖泊志") == true)
        XCTAssertTrue(issue?.message.contains("transliterated author") == true)
    }

    func testAuditDoesNotReportDuplicateTranslationForSameYearOnly() {
        let english = Reference(
            id: 40,
            title: "Lake Ecology Methods",
            authors: [
                AuthorName(given: "Jane", family: "Smith"),
            ],
            year: 1998,
            referenceType: .book,
            publisher: "Science Press",
            publisherPlace: "Beijing"
        )
        let chinese = Reference(
            id: 50,
            title: "中国湖泊志",
            authors: [
                AuthorName(given: "", family: "王苏民"),
                AuthorName(given: "", family: "窦鸿身"),
            ],
            year: 1998,
            referenceType: .book,
            publisher: "科学出版社",
            publisherPlace: "北京"
        )

        let report = ReferenceLibraryAuditor.audit([english, chinese])

        XCTAssertFalse(report.issues.contains { $0.kind == .probableDuplicateTranslation })
    }

    func testAuditReportsSuspiciousAuthorSwap() {
        // given=Zhang is a known pinyin surname, family=Sai is not → flag.
        let ref = Reference(
            id: 5,
            title: "Erhai Lake Paper",
            authors: [
                AuthorName(given: "Wei", family: "Yang"),     // both surnames — not flagged
                AuthorName(given: "Zhang", family: "Sai"),    // swap candidate
            ],
            year: 2014,
            journal: "Marine Biology",
            volume: "50",
            doi: "10.1007/test",
            referenceType: .journalArticle
        )
        let report = ReferenceLibraryAuditor.audit([ref])
        let swapIssues = report.issues.filter { $0.kind == .suspiciousAuthorSwap }
        XCTAssertEqual(swapIssues.count, 1)
        XCTAssertTrue(swapIssues[0].message.contains("Zhang"))
    }

    func testRepairPlanFixesPinyinSwap() {
        let ref = Reference(
            id: 6,
            title: "Swap Repair Test",
            authors: [
                AuthorName(given: "Zhang", family: "Sai"),   // swap needed
                AuthorName(given: "Wei",   family: "Yang"),  // ambiguous — no swap
            ]
        )
        let report = ReferenceLibraryRepairer.repairPlan(for: [ref])
        guard let candidate = report.candidates.first else {
            XCTFail("Expected a repair candidate")
            return
        }
        let swapChange = candidate.changes.first { $0.kind == .repairedAuthorSwap }
        XCTAssertNotNil(swapChange)
        // After repair: Zhang should be family.
        let repaired = ReferenceLibraryRepairer.repairedReference(ref)
        XCTAssertEqual(repaired.authors[0].family, "Zhang")
        XCTAssertEqual(repaired.authors[0].given,  "Sai")
        // Ambiguous pair must remain untouched.
        XCTAssertEqual(repaired.authors[1].family, "Yang")
        XCTAssertEqual(repaired.authors[1].given,  "Wei")
    }

    func testRepairPlanDisplaysAuthorNameChangesInCitationOrder() {
        let ref = Reference(
            id: 3,
            title: "Reversed Initials",
            authors: [
                AuthorName(given: "Kattner", family: "G."),
                AuthorName(given: "Graeve", family: "M."),
            ]
        )

        let report = ReferenceLibraryRepairer.repairPlan(for: [ref])
        let change = report.candidates.first?.changes.first { $0.kind == .normalizedAuthorNames }

        XCTAssertEqual(change?.before, "G. Kattner, M. Graeve")
        XCTAssertEqual(change?.after, "Kattner G, Graeve M")
    }

    func testCanonicalizerNormalizesStorageFieldsThroughSingleEntryPoint() {
        let ref = Reference(
            id: 7,
            title: "  Canonical   Record  ",
            authors: [AuthorName(given: "Zhang", family: "Sai")],
            year: 2024,
            journal: " Journal  Name ",
            volume: " 12 ",
            pages: " 1-9 ",
            doi: "https://doi.org/10.1890/12-2010.1",
            referenceType: .other,
            accessedDate: "2026-05-25",
            language: "zh_cn"
        )

        let result = ReferenceIntakeCanonicalizer.canonicalize(ref)
        let kinds = Set(result.changes.map(\.kind))

        XCTAssertEqual(result.reference.title, "Canonical Record")
        XCTAssertEqual(result.reference.journal, "Journal Name")
        XCTAssertEqual(result.reference.doi, "10.1890/12-2010.1")
        XCTAssertEqual(result.reference.referenceType, .journalArticle)
        XCTAssertNil(result.reference.accessedDate)
        XCTAssertEqual(result.reference.authors.first, AuthorName(given: "Sai", family: "Zhang"))
        XCTAssertEqual(result.reference.language, "zh-CN")
        XCTAssertTrue(kinds.contains(.trimmedTextFields))
        XCTAssertTrue(kinds.contains(.normalizedDOI))
        XCTAssertTrue(kinds.contains(.removedStableJournalAccessedDate))
        XCTAssertTrue(kinds.contains(.repairedAuthorSwap))
        XCTAssertTrue(kinds.contains(.inferredJournalArticleType))
        XCTAssertTrue(kinds.contains(.normalizedLanguage))
    }

    func testCanonicalizerNormalizesEncodedEditorAndTranslatorNames() throws {
        let ref = Reference(
            id: 8,
            title: "Edited Volume",
            editors: Reference.encodeNames([
                AuthorName(given: "Kattner", family: "G."),
            ]),
            translators: Reference.encodeNames([
                AuthorName(given: "Graeve", family: "M."),
            ])
        )

        let result = ReferenceIntakeCanonicalizer.canonicalize(ref)
        let kinds = Set(result.changes.map(\.kind))

        XCTAssertEqual(result.reference.parsedEditors, [AuthorName(given: "G", family: "Kattner")])
        XCTAssertEqual(result.reference.parsedTranslators, [AuthorName(given: "M", family: "Graeve")])
        XCTAssertTrue(kinds.contains(.normalizedEditorNames))
        XCTAssertTrue(kinds.contains(.normalizedTranslatorNames))

        let repair = ReferenceLibraryRepairer.repairPlan(for: [ref])
        let repairKinds = Set(repair.candidates.flatMap(\.changes).map(\.kind))
        XCTAssertTrue(repairKinds.contains(.normalizedEditorNames))
        XCTAssertTrue(repairKinds.contains(.normalizedTranslatorNames))
    }
}
