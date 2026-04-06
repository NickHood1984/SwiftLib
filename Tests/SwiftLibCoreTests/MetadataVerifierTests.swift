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
