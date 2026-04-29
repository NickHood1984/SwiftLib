import GRDB
import XCTest
@testable import SwiftLibCore

// MARK: - v12 Enrichment Model Tests

final class EnrichmentModelTests: XCTestCase {

    // MARK: - EvidenceBundle enrichment fields

    func testEvidenceBundleEnrichmentFieldsDefaultToNil() {
        let bundle = EvidenceBundle(source: .crossRef, fetchMode: .identifier)
        XCTAssertNil(bundle.enrichmentSources)
        XCTAssertNil(bundle.confidenceScore)
        XCTAssertNil(bundle.keywords)
        XCTAssertNil(bundle.topics)
        XCTAssertNil(bundle.isOpenAccess)
        XCTAssertNil(bundle.oaUrl)
        XCTAssertNil(bundle.fundingInfo)
        XCTAssertNil(bundle.citedByCount)
    }

    func testEvidenceBundleEnrichmentFieldsRoundTripCodable() throws {
        var bundle = EvidenceBundle(source: .openAlex, fetchMode: .identifier)
        bundle.enrichmentSources = [.openAlex, .crossRef]
        bundle.confidenceScore = 0.92
        bundle.keywords = ["machine learning", "NLP"]
        bundle.topics = ["Computer Science"]
        bundle.isOpenAccess = true
        bundle.oaUrl = "https://example.com/paper.pdf"
        bundle.fundingInfo = ["NSF (1234567)"]
        bundle.citedByCount = 42

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(EvidenceBundle.self, from: data)

        XCTAssertEqual(decoded.enrichmentSources, [.openAlex, .crossRef])
        XCTAssertEqual(decoded.confidenceScore, 0.92)
        XCTAssertEqual(decoded.keywords, ["machine learning", "NLP"])
        XCTAssertEqual(decoded.topics, ["Computer Science"])
        XCTAssertEqual(decoded.isOpenAccess, true)
        XCTAssertEqual(decoded.oaUrl, "https://example.com/paper.pdf")
        XCTAssertEqual(decoded.fundingInfo, ["NSF (1234567)"])
        XCTAssertEqual(decoded.citedByCount, 42)
    }

    func testEvidenceBundleBackwardCompatibleDecoding() throws {
        // Simulate a JSON payload from a v11 client (no enrichment fields)
        let oldJSON = """
        {
            "source": "crossRef",
            "fetchedAt": "2024-01-01T00:00:00Z",
            "fetchMode": "identifier",
            "rawArtifacts": [],
            "fieldEvidence": [],
            "verificationHints": {
                "hasStructuredTitle": true,
                "hasStructuredAuthors": false,
                "hasStructuredJournal": false,
                "hasStructuredInstitution": false,
                "hasStructuredPages": false,
                "hasStructuredThesisType": false,
                "hasStableRecordKey": false,
                "usedStructuredExport": false,
                "usedStructuredDetail": false,
                "usedIdentifierFetch": false,
                "exactIdentifierMatch": false,
                "competingCandidateCount": 0
            }
        }
        """
        let data = oldJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(EvidenceBundle.self, from: data)
        XCTAssertNil(bundle.enrichmentSources)
        XCTAssertNil(bundle.keywords)
        XCTAssertEqual(bundle.source, .crossRef)
    }

    // MARK: - VerificationHints enrichment fields

    func testVerificationHintsEnrichmentFieldsDefaultFalse() {
        let hints = VerificationHints()
        XCTAssertFalse(hints.hasFundingInfo)
        XCTAssertFalse(hints.hasKeywords)
        XCTAssertFalse(hints.hasOaStatus)
        XCTAssertFalse(hints.hasTopics)
    }

    func testVerificationHintsEnrichmentFieldsCanBeSet() {
        let hints = VerificationHints(
            hasFundingInfo: true,
            hasKeywords: true,
            hasOaStatus: true,
            hasTopics: true
        )
        XCTAssertTrue(hints.hasFundingInfo)
        XCTAssertTrue(hints.hasKeywords)
        XCTAssertTrue(hints.hasOaStatus)
        XCTAssertTrue(hints.hasTopics)
    }

    // MARK: - AcceptedRuleID new cases

    func testAcceptedRuleIDNewCasesRawValues() {
        XCTAssertEqual(AcceptedRuleID.p1PreprintArxiv.rawValue, "P1_PREPRINT_ARXIV")
        XCTAssertEqual(AcceptedRuleID.c1ConferenceRecordKey.rawValue, "C1_CONFERENCE_RECORD_KEY")
        XCTAssertEqual(AcceptedRuleID.r1ReportRecordKey.rawValue, "R1_REPORT_RECORD_KEY")
        XCTAssertEqual(AcceptedRuleID.d1DatasetDOI.rawValue, "D1_DATASET_DOI")
    }

    // MARK: - Reference P3 enrichment fields

    func testReferenceP3FieldsDefaultToNil() {
        let ref = Reference(title: "Test")
        XCTAssertNil(ref.keywords)
        XCTAssertNil(ref.topics)
        XCTAssertNil(ref.isOpenAccess)
        XCTAssertNil(ref.oaUrl)
        XCTAssertNil(ref.citedByCount)
        XCTAssertNil(ref.fundingInfo)
        XCTAssertNil(ref.confidenceScore)
    }

    func testReferenceP3FieldsEquality() {
        let now = Date()
        var ref1 = Reference(title: "Test")
        ref1.dateAdded = now
        ref1.dateModified = now
        var ref2 = Reference(title: "Test")
        ref2.dateAdded = now
        ref2.dateModified = now
        XCTAssertEqual(ref1, ref2)

        ref1.isOpenAccess = true
        XCTAssertNotEqual(ref1, ref2)

        ref2.isOpenAccess = true
        XCTAssertEqual(ref1, ref2)

        ref1.citedByCount = 100
        XCTAssertNotEqual(ref1, ref2)
    }
}

// MARK: - Verifier New Rules Tests

final class VerifierNewRulesTests: XCTestCase {

    private func makeSeed(
        title: String = "Test Paper",
        firstAuthor: String? = "Zhang San",
        year: Int? = 2024,
        doi: String? = nil,
        isbn: String? = nil
    ) -> MetadataResolutionSeed {
        MetadataResolutionSeed(
            fileName: "test.pdf",
            title: title,
            firstAuthor: firstAuthor,
            year: year,
            doi: doi,
            isbn: isbn,
            languageHint: .nonChinese,
            workKindHint: .journalArticle
        )
    }

    // MARK: - P1 Preprint (arXiv)

    func testP1PreprintArxivVerifies() {
        let seed = makeSeed(
            title: "Deep Learning for NLP",
            firstAuthor: "Ashish Vaswani",
            year: 2017
        )
        let ref = Reference(
            title: "Deep Learning for NLP",
            authors: [AuthorName(given: "Ashish", family: "Vaswani")],
            year: 2017,
            doi: "10.48550/arXiv.1706.03762",
            referenceType: .preprint
        )
        let evidence = EvidenceBundle(
            source: .arXiv,
            recordKey: "arxiv:1706.03762",
            fetchMode: .identifier,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                exactIdentifierMatch: true
            )
        )

        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)
        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected P1_PREPRINT_ARXIV verification")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.p1PreprintArxiv.rawValue)
    }

    // MARK: - C1 Conference Paper

    func testC1ConferenceRecordKeyVerifies() {
        let seed = makeSeed(
            title: "Attention Is All You Need",
            firstAuthor: "Ashish Vaswani",
            year: 2017
        )
        let ref = Reference(
            title: "Attention Is All You Need",
            authors: [AuthorName(given: "Ashish", family: "Vaswani")],
            year: 2017,
            referenceType: .conferencePaper,
            eventTitle: "NeurIPS 2017"
        )
        let evidence = EvidenceBundle(
            source: .translationServer,
            recordKey: "conf/nips/VaswaniSPUJGKP17",
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStableRecordKey: true
            )
        )

        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)
        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected C1_CONFERENCE_RECORD_KEY verification")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.c1ConferenceRecordKey.rawValue)
    }

    // MARK: - R1 Report

    func testR1ReportRecordKeyVerifies() {
        let seed = makeSeed(
            title: "AI Index Report 2024",
            firstAuthor: "Nestor Maslej",
            year: 2024
        )
        let ref = Reference(
            title: "AI Index Report 2024",
            authors: [AuthorName(given: "Nestor", family: "Maslej")],
            year: 2024,
            referenceType: .report,
            institution: "Stanford University"
        )
        let evidence = EvidenceBundle(
            source: .translationServer,
            recordKey: "report/stanford/aiindex2024",
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStableRecordKey: true
            )
        )

        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)
        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected R1_REPORT_RECORD_KEY verification")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.r1ReportRecordKey.rawValue)
    }

    // MARK: - D1 Dataset

    func testD1DatasetDOIVerifies() {
        let seed = makeSeed(
            title: "ImageNet Large Scale Visual Recognition Dataset",
            firstAuthor: "Deng",
            year: 2009,
            doi: "10.1109/CVPR.2009.5206848"
        )
        let ref = Reference(
            title: "ImageNet Large Scale Visual Recognition Dataset",
            authors: [AuthorName(given: "Jia", family: "Deng")],
            year: 2009,
            doi: "10.1109/CVPR.2009.5206848",
            referenceType: .dataset
        )
        let evidence = EvidenceBundle(
            source: .crossRef,
            recordKey: "doi:10.1109/CVPR.2009.5206848",
            fetchMode: .identifier,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                exactIdentifierMatch: true
            )
        )

        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)
        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected D1_DATASET_DOI verification")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.d1DatasetDOI.rawValue)
    }

    // MARK: - Confidence Score

    func testConfidenceScoreFullMatchNear1() {
        let seed = makeSeed(
            title: "Exact Title Match",
            firstAuthor: "Author One",
            year: 2024,
            doi: "10.1000/test"
        )
        let ref = Reference(
            title: "Exact Title Match",
            authors: [AuthorName(given: "Author", family: "One")],
            year: 2024,
            doi: "10.1000/test"
        )
        let evidence = EvidenceBundle(
            source: .crossRef,
            fetchMode: .identifier,
            verificationHints: VerificationHints(
                hasFundingInfo: true,
                hasKeywords: true,
                hasOaStatus: true,
                hasTopics: true
            )
        )

        let score = MetadataVerifier.calculateConfidenceScore(
            reference: ref, seed: seed, evidence: evidence
        )
        XCTAssertGreaterThan(score, 0.85, "Full match with enrichment should score > 0.85")
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func testConfidenceScoreNoSeedLow() {
        let ref = Reference(
            title: "Some Paper",
            authors: [AuthorName(given: "Test", family: "Author")]
        )
        let evidence = EvidenceBundle(source: .crossRef, fetchMode: .identifier)

        let score = MetadataVerifier.calculateConfidenceScore(
            reference: ref, seed: nil, evidence: evidence
        )
        XCTAssertLessThan(score, 0.50, "No seed should give low confidence")
    }
}

// MARK: - OpenAlex Enrichment Parsing Tests

final class OpenAlexEnrichmentTests: XCTestCase {

    func testParseOpenAlexEnrichmentFromFixture() {
        let work: [String: Any] = [
            "id": "https://openalex.org/W2741809807",
            "type": "journal-article",
            "concepts": [
                ["display_name": "Machine Learning", "score": 0.95],
                ["display_name": "Neural Network", "score": 0.80],
                ["display_name": "NLP", "score": 0.70],
            ] as [[String: Any]],
            "topics": [
                ["display_name": "Deep Learning Applications"],
                ["display_name": "Transformer Models"],
            ] as [[String: Any]],
            "open_access": [
                "is_oa": true,
                "oa_url": "https://arxiv.org/pdf/1706.03762.pdf",
            ] as [String: Any],
            "cited_by_count": 120000,
            "grants": [
                ["funder_display_name": "Google Brain", "award_id": ""] as [String: Any],
                ["funder_display_name": "NSF", "award_id": "1234567"] as [String: Any],
            ] as [[String: Any]],
            "abstract_inverted_index": [
                "The": [0],
                "dominant": [1],
                "approach.": [2],
            ] as [String: [Int]],
        ]

        let enrichment = MetadataFetcher.parseOpenAlexEnrichment(work)

        XCTAssertEqual(enrichment.keywords, ["Machine Learning", "Neural Network", "NLP"])
        XCTAssertEqual(enrichment.topics, ["Deep Learning Applications", "Transformer Models"])
        XCTAssertTrue(enrichment.isOpenAccess)
        XCTAssertEqual(enrichment.oaUrl, "https://arxiv.org/pdf/1706.03762.pdf")
        XCTAssertEqual(enrichment.citedByCount, 120000)
        XCTAssertEqual(enrichment.fundingInfo.count, 2)
        XCTAssertTrue(enrichment.fundingInfo.contains("Google Brain"))
        XCTAssertTrue(enrichment.fundingInfo.contains("NSF (1234567)"))
        XCTAssertEqual(enrichment.referenceType, .journalArticle)
        XCTAssertEqual(enrichment.abstract, "The dominant approach.")
    }

    func testParseOpenAlexEnrichmentHandlesMissingFields() {
        let work: [String: Any] = [
            "id": "https://openalex.org/W123",
            "type": "unknown-type",
        ]

        let enrichment = MetadataFetcher.parseOpenAlexEnrichment(work)

        XCTAssertTrue(enrichment.keywords.isEmpty)
        XCTAssertTrue(enrichment.topics.isEmpty)
        XCTAssertFalse(enrichment.isOpenAccess)
        XCTAssertNil(enrichment.oaUrl)
        XCTAssertEqual(enrichment.citedByCount, 0)
        XCTAssertTrue(enrichment.fundingInfo.isEmpty)
        XCTAssertNil(enrichment.referenceType)
        XCTAssertNil(enrichment.abstract)
    }

    func testApplyEnrichmentDoesNotOverwriteExisting() {
        var ref = Reference(title: "Test Paper")
        ref.abstract = "Existing abstract"
        ref.referenceType = .journalArticle

        let enrichment = MetadataFetcher.OpenAlexEnrichment(
            keywords: ["AI"],
            topics: ["CS"],
            isOpenAccess: true,
            oaUrl: "https://example.com/oa",
            citedByCount: 50,
            fundingInfo: ["Grant A"],
            referenceType: .preprint,
            abstract: "New abstract from OpenAlex"
        )

        let merged = MetadataResolution.applyEnrichment(enrichment, to: ref)

        // Should NOT overwrite existing abstract
        XCTAssertEqual(merged.abstract, "Existing abstract")
        // Should NOT downgrade referenceType
        XCTAssertEqual(merged.referenceType, .journalArticle)
        // Should set new fields
        XCTAssertTrue(merged.isOpenAccess!)
        XCTAssertEqual(merged.oaUrl, "https://example.com/oa")
        XCTAssertEqual(merged.citedByCount, 50)
        // Keywords should be JSON-encoded
        XCTAssertNotNil(merged.keywords)
    }

    func testApplyEnrichmentFillsEmptyAbstract() {
        let ref = Reference(title: "Test Paper")
        let enrichment = MetadataFetcher.OpenAlexEnrichment(
            keywords: [],
            topics: [],
            isOpenAccess: false,
            citedByCount: 0,
            fundingInfo: [],
            abstract: "Enriched abstract"
        )

        let merged = MetadataResolution.applyEnrichment(enrichment, to: ref)
        XCTAssertEqual(merged.abstract, "Enriched abstract")
    }

    func testApplyNilEnrichmentReturnsOriginal() {
        let ref = Reference(title: "Test")
        let merged = MetadataResolution.applyEnrichment(nil, to: ref)
        XCTAssertEqual(merged, ref)
    }
}

// MARK: - ImportIntakeService Tests

final class ImportIntakeServiceTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(path: ":memory:"))
    }

    func testBuildImportEvidenceHasStructuredTitle() {
        // Verify that a parsed reference with a title gets structured title hint
        let ref = Reference(
            title: "Test Article",
            authors: [AuthorName(given: "Test", family: "Author")],
            year: 2024,
            journal: "Test Journal",
            doi: "10.1000/test"
        )

        let seed = MetadataResolutionSeed(
            fileName: "test.bib",
            title: ref.title,
            firstAuthor: "Author",
            year: 2024,
            doi: "10.1000/test"
        )

        // The evidence from import should have structured hints
        let evidence = EvidenceBundle(
            source: .bibtex,
            recordKey: ref.doi,
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                usedIdentifierFetch: true,
                exactIdentifierMatch: true
            )
        )

        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)
        // DOI exact match + title match + year/author → should verify via J1
        guard case .verified(let envelope) = decision else {
            return XCTFail("BibTeX import with DOI should verify via J1")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    func testBatchImportPersistsVerifiedEntriesDirectlyToLibrary() async throws {
        let db = try makeDatabase()
        let ref = Reference(
            title: "Test Article",
            authors: [AuthorName(given: "Test", family: "Author")],
            year: 2024,
            journal: "Test Journal",
            doi: "10.1000/test"
        )

        let result = try await ImportIntakeService.batchImport(
            references: [ref],
            enrichWithOpenAlex: false,
            database: db
        )

        XCTAssertEqual(result.verified, 1)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.candidates, 0)
        XCTAssertEqual(result.rejected, 0)
        XCTAssertEqual(try db.referenceCount(), 1)
        XCTAssertTrue(try db.fetchPendingMetadataIntakes().isEmpty)
    }

    func testBatchImportQueuesRejectedEntriesIntoMetadataIntake() async throws {
        let db = try makeDatabase()
        let ref = Reference(
            title: "Standalone Book",
            authors: [AuthorName(given: "Test", family: "Author")],
            year: 2024,
            referenceType: .book,
            publisher: "Test Press"
        )

        let result = try await ImportIntakeService.batchImport(
            references: [ref],
            enrichWithOpenAlex: false,
            database: db
        )

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.verified, 0)
        XCTAssertEqual(result.rejected, 1)
        XCTAssertEqual(try db.referenceCount(), 0)

        let pending = try db.fetchPendingMetadataIntakes()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].sourceKind, .importFile)
        XCTAssertEqual(pending[0].verificationStatus, .rejectedAmbiguous)
        XCTAssertEqual(pending[0].title, "Standalone Book")
    }
}
