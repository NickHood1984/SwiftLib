import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class MetadataResolverTests: XCTestCase {
    func testManualCandidateSelectionPromotesRejectedResultToVerifiedManual() {
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CJFD-2024-12345",
            sourceURL: "https://kns.cnki.net/detail/example",
            fetchMode: .detail,
            fieldEvidence: [
                FieldEvidence(field: "title", value: "中文论文题目", origin: .structuredDetail),
                FieldEvidence(field: "authors", value: "张三", origin: .structuredDetail)
            ],
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStableRecordKey: true,
                usedStructuredDetail: true
            )
        )
        let reference = Reference(
            title: "中文论文题目",
            authors: [AuthorName(given: "", family: "张三")],
            year: 2024,
            journal: "测试期刊",
            referenceType: .journalArticle
        )
        let rejected = MetadataResolutionResult.rejected(
            RejectedEnvelope(
                seed: MetadataResolutionSeed(
                    fileName: "seed.pdf",
                    title: "中文论文题目",
                    firstAuthor: "张三",
                    year: 2024,
                    journal: "测试期刊",
                    languageHint: .chinese,
                    workKindHint: .journalArticle
                ),
                fallbackReference: nil,
                currentReference: reference,
                reason: .verifierRuleNotSatisfied,
                message: "未满足期刊类自动验证规则。",
                evidence: evidence
            )
        )

        let promoted = MetadataResolver.promoteManualCandidateSelectionResult(
            rejected,
            reviewedBy: "candidate-selection"
        )

        guard case .verified(let envelope) = promoted else {
            return XCTFail("手动选中候选后应直接晋升为 verifiedManual")
        }
        XCTAssertEqual(envelope.reference.verificationStatus, .verifiedManual)
        XCTAssertEqual(envelope.reference.reviewedBy, "candidate-selection")
        XCTAssertEqual(envelope.reference.metadataSource, .cnki)
        XCTAssertEqual(envelope.reference.recordKey, "CJFD-2024-12345")
        XCTAssertEqual(envelope.reference.verificationSourceURL, "https://kns.cnki.net/detail/example")
        XCTAssertEqual(envelope.reference.evidenceBundleHash, evidence.bundleHash)
    }

    func testManualCandidateSelectionDoesNotOverrideBlockedResult() {
        let blocked = MetadataResolutionResult.blocked(
            BlockedEnvelope(
                seed: nil,
                fallbackReference: Reference(title: "受阻条目"),
                currentReference: nil,
                reason: .verificationRequired,
                message: "需要验证码。"
            )
        )

        let promoted = MetadataResolver.promoteManualCandidateSelectionResult(
            blocked,
            reviewedBy: "candidate-selection"
        )

        guard case .blocked(let envelope) = promoted else {
            return XCTFail("blocked 结果不应被手动选候选直接覆盖")
        }
        XCTAssertEqual(envelope.reason, .verificationRequired)
    }
}
