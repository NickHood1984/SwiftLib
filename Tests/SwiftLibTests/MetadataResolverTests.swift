import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class MetadataResolverTests: XCTestCase {
    func testCNKICandidateEnvelopeMergesChineseBrowserCandidates() {
        let seed = MetadataResolutionSeed(
            fileName: "seed.pdf",
            title: "中文论文题目",
            languageHint: .chinese,
            workKindHint: .journalArticle
        )
        let cnkiCandidate = MetadataCandidate(
            source: .cnki,
            title: "中文论文题目",
            detailURL: "https://kns.cnki.net/detail/example",
            score: 0.74
        )
        let wanfangCandidate = MetadataCandidate(
            source: .wanfang,
            title: "中文论文题目",
            detailURL: "https://s.wanfangdata.com.cn/paper/example",
            score: 0.82
        )
        let cnkiEnvelope = CandidateEnvelope(
            seed: seed,
            fallbackReference: nil,
            candidates: [cnkiCandidate],
            message: "CNKI candidate"
        )
        let wanfangEnvelope = CandidateEnvelope(
            seed: seed,
            fallbackReference: nil,
            candidates: [wanfangCandidate],
            message: "Wanfang candidate"
        )

        let merged = MetadataResolver.mergedChineseBrowserCandidateEnvelope(
            cnkiEnvelope,
            fallbackEnvelope: wanfangEnvelope
        )

        XCTAssertEqual(merged.candidates.map(\.source), [.wanfang, .cnki])
        XCTAssertTrue(merged.message.contains("万方"))
        XCTAssertTrue(merged.message.contains("中国知网"))
    }

    func testCNKICandidateEnvelopeDeduplicatesSameSourceAndURL() {
        let first = MetadataCandidate(
            source: .cnki,
            title: "中文论文题目",
            detailURL: "https://kns.cnki.net/detail/example",
            score: 0.74
        )
        let duplicate = MetadataCandidate(
            source: .cnki,
            title: "中文论文题目",
            detailURL: "https://kns.cnki.net/detail/example",
            score: 0.90
        )
        let primary = CandidateEnvelope(seed: nil, fallbackReference: nil, candidates: [first], message: "CNKI")
        let fallback = CandidateEnvelope(seed: nil, fallbackReference: nil, candidates: [duplicate], message: "Fallback")

        let merged = MetadataResolver.mergedChineseBrowserCandidateEnvelope(primary, fallbackEnvelope: fallback)

        XCTAssertEqual(merged.candidates.count, 1)
        XCTAssertEqual(merged.candidates.first?.score, 0.74)
    }

    func testRefreshSkipsCrossRefForChineseJournal() {
        let reference = Reference(
            title: "近50a洱海水环境演变特征及其主要驱动因素",
            authors: [AuthorName(given: "", family: "高思佳")],
            year: 2023,
            journal: "湖泊科学",
            doi: "10.18307/2023.0422",
            url: "https://kns.cnki.net/kcms2/article/abstract?v=example",
            referenceType: .journalArticle,
            metadataSource: .cnki
        )
        let seed = MetadataResolutionSeed.fromReference(reference)

        XCTAssertFalse(
            MetadataResolver.shouldUseCrossRefForRefresh(reference: reference, seed: seed),
            "Chinese journal refresh should not let Crossref overwrite CNKI-style metadata."
        )
    }

    func testRefreshUsesCrossRefForNonChineseJournal() {
        let reference = Reference(
            title: "Freshwater biodiversity: importance, threats, status and conservation challenges",
            authors: [AuthorName(given: "D", family: "Dudgeon")],
            year: 2006,
            journal: "Biological Reviews",
            doi: "10.1017/S1464793105006950",
            referenceType: .journalArticle,
            metadataSource: .crossRef
        )
        let seed = MetadataResolutionSeed.fromReference(reference)

        XCTAssertTrue(MetadataResolver.shouldUseCrossRefForRefresh(reference: reference, seed: seed))
    }

    func testRefreshUsesCrossRefForChineseBookRouting() {
        let reference = Reference(
            title: "中国湖泊志",
            authors: [AuthorName(given: "", family: "王苏民")],
            year: 1998,
            referenceType: .book,
            isbn: "9787030069870"
        )
        let seed = MetadataResolutionSeed.fromReference(reference)

        XCTAssertTrue(MetadataResolver.shouldUseCrossRefForRefresh(reference: reference, seed: seed))
    }

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
