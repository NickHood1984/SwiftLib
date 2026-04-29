import XCTest
@testable import SwiftLibCore

final class MetadataVerifierTests: XCTestCase {

    private func makeIdentifierEvidence(
        source: MetadataSource = .translationServer,
        recordKey: String? = "doi:10.1000/example"
    ) -> EvidenceBundle {
        EvidenceBundle(
            source: source,
            recordKey: recordKey,
            sourceURL: "https://doi.org/10.1000/example",
            fetchMode: .identifier,
            fieldEvidence: [
                FieldEvidence(field: "title", value: "Verified Paper", origin: .identifierAPI),
                FieldEvidence(field: "authors", value: "Ada Lovelace", origin: .identifierAPI),
                FieldEvidence(field: "year", value: "2024", origin: .identifierAPI),
                FieldEvidence(field: "doi", value: "10.1000/example", origin: .identifierAPI)
            ],
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                hasStableRecordKey: true,
                usedIdentifierFetch: true,
                exactIdentifierMatch: true
            )
        )
    }

    func testJournalVerifierAcceptsJ1DOIExact() {
        let seed = MetadataResolutionSeed(
            fileName: "verified.pdf",
            title: "Verified Paper",
            firstAuthor: "Ada Lovelace",
            year: 2024,
            doi: "10.1000/example",
            journal: "Journal of Verification",
            languageHint: .nonChinese,
            workKindHint: .journalArticle
        )
        let reference = Reference(
            title: "Verified Paper",
            authors: [AuthorName(given: "Ada", family: "Lovelace")],
            year: 2024,
            journal: "Journal of Verification",
            doi: "10.1000/example"
        )

        let decision = MetadataVerifier.verify(
            reference: reference,
            seed: seed,
            evidence: makeIdentifierEvidence()
        )

        guard case .verified(let envelope) = decision else {
            return XCTFail("期望命中 J1_DOI_EXACT 自动验证规则")
        }
        XCTAssertEqual(envelope.reference.verificationStatus, .verifiedAuto)
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    // MARK: - B2: ISBN-less book consensus (Douban / older CN titles)

    private func makeBookConsensusEvidence(
        source: MetadataSource = .douban,
        includePublisherField: Bool = true
    ) -> EvidenceBundle {
        var fields: [FieldEvidence] = [
            FieldEvidence(field: "title", value: "高级水生生物学", origin: .identifierAPI),
            FieldEvidence(field: "authors", value: "刘建康", origin: .identifierAPI),
            FieldEvidence(field: "year", value: "1999", origin: .identifierAPI)
        ]
        if includePublisherField {
            fields.append(FieldEvidence(field: "publisher", value: "科学出版社", origin: .identifierAPI))
        }
        return EvidenceBundle(
            source: source,
            recordKey: nil,
            sourceURL: "https://book.douban.com/subject/1234567/",
            fetchMode: .identifier,
            fieldEvidence: fields,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                usedIdentifierFetch: true
            )
        )
    }

    /// Case reported by a user: 《高级水生生物学》刘建康 1999 科学出版社。
    /// Douban suggest returns title + author + year + publisher but no ISBN
    /// (common for pre-2007 CN books). Old behavior rejected because B1
    /// required ISBN/recordKey; B2 should now fire when all 4 fields agree.
    func testBookVerifierAcceptsB2ChineseBookWithoutISBN() {
        let seed = MetadataResolutionSeed(
            fileName: "高级水生生物学.pdf",
            title: "高级水生生物学",
            firstAuthor: "刘建康",
            year: 1999,
            publisher: "科学出版社",
            languageHint: .chinese,
            workKindHint: .book
        )
        let reference = Reference(
            title: "高级水生生物学",
            authors: [AuthorName.parse("刘建康")],
            year: 1999,
            referenceType: .book,
            metadataSource: .douban,
            publisher: "科学出版社"
        )

        let decision = MetadataVerifier.verify(
            reference: reference,
            seed: seed,
            evidence: makeBookConsensusEvidence()
        )

        guard case .verified(let envelope) = decision else {
            return XCTFail("1999 中文书无 ISBN 但 title/author/year/publisher 全致时应命中 B2_BOOK_TITLE_CONSENSUS")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.b2BookTitleConsensus.rawValue)
        XCTAssertEqual(envelope.reference.metadataSource, .douban)
        XCTAssertEqual(envelope.reference.verificationStatus, .verifiedAuto)
    }

    /// Safety clamp: seed lacks publisher → B2 MUST NOT fire, to avoid accepting
    /// a loose title-only match. B1 can't fire either (no ISBN), so the overall
    /// decision should be rejected.
    func testBookVerifierRejectsB2WhenSeedPublisherMissing() {
        let seed = MetadataResolutionSeed(
            fileName: "高级水生生物学.pdf",
            title: "高级水生生物学",
            firstAuthor: "刘建康",
            year: 1999,
            languageHint: .chinese,
            workKindHint: .book
        )
        let reference = Reference(
            title: "高级水生生物学",
            authors: [AuthorName.parse("刘建康")],
            year: 1999,
            referenceType: .book,
            metadataSource: .douban,
            publisher: "科学出版社"
        )

        let decision = MetadataVerifier.verify(
            reference: reference,
            seed: seed,
            evidence: makeBookConsensusEvidence(includePublisherField: false)
        )

        if case .verified = decision {
            XCTFail("seed 无 publisher 时 B2 不应命中")
        }
    }

    /// Safety clamp: untrusted source (e.g. a generic translationServer scrape)
    /// must not be auto-verified via B2 even when all fields agree.
    func testBookVerifierRejectsB2WhenSourceUntrusted() {
        let seed = MetadataResolutionSeed(
            fileName: "高级水生生物学.pdf",
            title: "高级水生生物学",
            firstAuthor: "刘建康",
            year: 1999,
            publisher: "科学出版社",
            languageHint: .chinese,
            workKindHint: .book
        )
        let reference = Reference(
            title: "高级水生生物学",
            authors: [AuthorName.parse("刘建康")],
            year: 1999,
            referenceType: .book,
            metadataSource: .translationServer,
            publisher: "科学出版社"
        )

        let decision = MetadataVerifier.verify(
            reference: reference,
            seed: seed,
            evidence: makeBookConsensusEvidence(source: .translationServer)
        )

        if case .verified = decision {
            XCTFail("非可信图书源不应命中 B2")
        }
    }

    func testJournalVerifierRejectsBareDOIWithoutCorroboratingSeed() {
        let seed = MetadataResolutionSeed(
            fileName: "suspicious.pdf",
            doi: "10.1000/example",
            languageHint: .nonChinese,
            workKindHint: .journalArticle
        )
        let reference = Reference(
            title: "Verified Paper",
            authors: [AuthorName(given: "Ada", family: "Lovelace")],
            year: 2024,
            journal: "Journal of Verification",
            doi: "10.1000/example"
        )

        let decision = MetadataVerifier.verify(
            reference: reference,
            seed: seed,
            evidence: makeIdentifierEvidence()
        )

        guard case .rejected(let envelope) = decision else {
            return XCTFail("缺少题名/年份/作者复核的 DOI 命中不应自动通过")
        }
        XCTAssertEqual(envelope.reason, .verifierRuleNotSatisfied)
    }
}
