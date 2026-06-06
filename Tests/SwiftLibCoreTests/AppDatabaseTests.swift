import XCTest
import GRDB
@testable import SwiftLibCore

final class AppDatabaseTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(path: ":memory:"))
    }

    private func makeEvidence(
        source: MetadataSource = .translationServer,
        recordKey: String? = "record-1",
        sourceURL: String? = "https://example.com/reference",
        fetchMode: FetchMode = .identifier
    ) -> EvidenceBundle {
        EvidenceBundle(
            source: source,
            recordKey: recordKey,
            sourceURL: sourceURL,
            fetchMode: fetchMode,
            fieldEvidence: [
                FieldEvidence(field: "title", value: "Evidence Title", origin: .identifierAPI),
                FieldEvidence(field: "year", value: "2024", origin: .identifierAPI)
            ],
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStableRecordKey: recordKey != nil,
                usedIdentifierFetch: fetchMode == .identifier,
                exactIdentifierMatch: fetchMode == .identifier
            )
        )
    }

    // MARK: - Reference CRUD

    func testSaveAndFetchReference() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "DB Test Reference")
        ref.year = 2023
        ref.journal = "Test Journal"

        try db.saveReference(&ref)
        XCTAssertNotNil(ref.id, "After save, reference should have an ID")

        let fetched = try db.fetchReferences(ids: [ref.id!])
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].title, "DB Test Reference")
        XCTAssertEqual(fetched[0].year, 2023)
    }

    func testUpdateReference() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Original Title")
        try db.saveReference(&ref)
        let id = ref.id!

        ref.title = "Updated Title"
        ref.year = 2024
        try db.saveReference(&ref)

        let fetched = try db.fetchReferences(ids: [id])
        XCTAssertEqual(fetched[0].title, "Updated Title")
        XCTAssertEqual(fetched[0].year, 2024)
    }

    func testUpdateReferenceTouchesDateModified() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Original Title")
        try db.saveReference(&ref)
        let id = try XCTUnwrap(ref.id)

        ref.title = "Updated Title"
        ref.dateModified = Date(timeIntervalSince1970: 1)
        try db.saveReference(&ref)

        let stored = try XCTUnwrap(try db.fetchReferences(ids: [id]).first)
        XCTAssertEqual(stored.title, "Updated Title")
        XCTAssertGreaterThan(stored.dateModified, Date(timeIntervalSince1970: 1))
    }

    func testDeleteReference() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "To Delete")
        try db.saveReference(&ref)
        let id = ref.id!

        try db.deleteReferences(ids: [id])
        let fetched = try db.fetchReferences(ids: [id])
        XCTAssertTrue(fetched.isEmpty, "Deleted reference should not be fetchable")
    }

    func testDeleteMultipleReferences() throws {
        let db = try makeDatabase()
        var ref1 = Reference(title: "Delete Multi 1")
        var ref2 = Reference(title: "Delete Multi 2")
        try db.saveReference(&ref1)
        try db.saveReference(&ref2)

        try db.deleteReferences(ids: [ref1.id!, ref2.id!])
        let fetched = try db.fetchReferences(ids: [ref1.id!, ref2.id!])
        XCTAssertTrue(fetched.isEmpty)
    }

    func testDeleteReferencesReturningPDFPathsDeletesDatabaseRowsAtomically() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Delete With PDF")
        ref.pdfPath = "PDFs/example.pdf"
        try db.saveReference(&ref)

        let pdfPaths = try db.deleteReferencesReturningPDFPaths(ids: [try XCTUnwrap(ref.id)])

        XCTAssertEqual(pdfPaths, ["PDFs/example.pdf"])
        XCTAssertTrue(try db.fetchReferences(ids: [try XCTUnwrap(ref.id)]).isEmpty)
    }

    func testSaveReferenceWithPDFPathIsTreatedAsManualDirectSave() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Manual PDF Entry")
        ref.pdfPath = "PDFs/manual.pdf"

        try db.saveReference(&ref)

        let stored = try XCTUnwrap(try db.fetchReferences(ids: [try XCTUnwrap(ref.id)]).first)
        XCTAssertEqual(stored.verificationStatus, .verifiedManual)
        XCTAssertEqual(stored.reviewedBy, "direct-save")
        XCTAssertEqual(stored.pdfPath, "PDFs/manual.pdf")
    }

    func testSaveReferenceCanonicalizesLegacyCitationProblemsBeforeRepair() throws {
        let db = try makeDatabase()
        var ref = Reference(
            title: "洞庭湖春秋季浮游植物群落结构及其与环境因子的关系",
            authors: [
                AuthorName(given: "潘保柱, 赵耿楠, 韩 谞, 蒋小明, 李典宝", family: "王 昊")
            ],
            year: 2021,
            journal: "长江流域资源与环境",
            volume: "30",
            issue: "11",
            pages: "2659-2667",
            doi: "https://doi.org/10.1111/example",
            referenceType: .other,
            accessedDate: "2026-05-25"
        )
        try db.saveReference(&ref)

        let stored = try XCTUnwrap(try db.fetchReferences(ids: [try XCTUnwrap(ref.id)]).first)
        XCTAssertEqual(stored.doi, "10.1111/example")
        XCTAssertNil(stored.accessedDate)
        XCTAssertEqual(stored.referenceType, .journalArticle)
        XCTAssertEqual(stored.authors.map(\.family), ["王昊", "潘保柱", "赵耿楠", "韩谞", "蒋小明", "李典宝"])

        let dryRun = ReferenceLibraryRepairer.repairPlan(for: [stored])
        XCTAssertEqual(dryRun.candidateCount, 0)

        let report = try db.repairCitationMetadata([stored])
        XCTAssertEqual(report.appliedCount, 0)
        XCTAssertEqual(report.candidateCount, 0)
    }

    func testSaveReferenceMergesDuplicateDOIAndKeepsBestMetadata() throws {
        let db = try makeDatabase()

        var original = Reference(title: "Original Title")
        original.doi = "10.1000/example"
        original.notes = "short"
        try db.saveReference(&original)

        var duplicate = Reference(title: "Better Title")
        duplicate.doi = "10.1000/example"
        duplicate.abstract = "A much longer abstract than before"
        duplicate.pdfPath = "PDFs/duplicate.pdf"
        try db.saveReference(&duplicate)

        let all = try db.fetchAllReferences()
        XCTAssertEqual(all.count, 1)
        let merged = try XCTUnwrap(all.first)
        XCTAssertEqual(merged.title, "Better Title")
        XCTAssertEqual(merged.abstract, "A much longer abstract than before")
        XCTAssertEqual(merged.pdfPath, "PDFs/duplicate.pdf")
        XCTAssertEqual(duplicate.id, merged.id)
    }

    func testSaveReferenceStoresBareDOIAndDeduplicatesDOIURLVariants() throws {
        let db = try makeDatabase()

        var original = Reference(title: "Original DOI URL")
        original.doi = "https://doi.org/10.1890/12-2010.1"
        try db.saveReference(&original)

        var duplicate = Reference(title: "Duplicate DOI Prefix")
        duplicate.doi = "DOI:10.1890/12-2010.1"
        try db.saveReference(&duplicate)

        let all = try db.fetchAllReferences()
        XCTAssertEqual(all.count, 1)
        let stored = try XCTUnwrap(all.first)
        XCTAssertEqual(stored.doi, "10.1890/12-2010.1")
        XCTAssertEqual(duplicate.id, stored.id)
    }

    func testSaveReferenceDeduplicatesAgainstLegacyDoiNormalizedURLRows() throws {
        let db = try makeDatabase()

        var legacy = Reference(title: "Legacy DOI URL")
        legacy.doi = "https://doi.org/10.1890/12-2010.1"
        try db.saveReference(&legacy)
        let legacyId = try XCTUnwrap(legacy.id)
        try db.dbWriter.write { rawDB in
            try rawDB.execute(
                sql: """
                    UPDATE reference
                    SET doi = ?, doiNormalized = ?
                    WHERE id = ?
                    """,
                arguments: [
                    "https://doi.org/10.1890/12-2010.1",
                    "https://doi.org/10.1890/12-2010.1",
                    legacyId,
                ]
            )
        }

        var duplicate = Reference(title: "Bare DOI Duplicate")
        duplicate.doi = "10.1890/12-2010.1"
        try db.saveReference(&duplicate)

        let all = try db.fetchAllReferences()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(duplicate.id, legacyId)
        XCTAssertEqual(try XCTUnwrap(all.first).doi, "10.1890/12-2010.1")
    }

    func testBatchImportStoresBareDOI() throws {
        let db = try makeDatabase()

        _ = try db.batchImportReferences([
            Reference(title: "Imported DOI URL", doi: "https://doi.org/10.1111/gcb.13295")
        ])

        let stored = try XCTUnwrap(try db.fetchAllReferences().first)
        XCTAssertEqual(stored.doi, "10.1111/gcb.13295")
    }

    func testSaveReferenceAllowsUpdatingExistingLegacyEntry() throws {
        let db = try makeDatabase()

        var ref = Reference(title: "Legacy Entry")
        try db.saveReference(&ref)
        ref.verificationStatus = .legacy
        try db.saveReference(&ref)

        ref.title = "Updated Legacy Entry"
        ref.notes = "Edited after migration"
        try db.saveReference(&ref)

        let stored = try XCTUnwrap(try db.fetchReferences(ids: [try XCTUnwrap(ref.id)]).first)
        XCTAssertEqual(stored.title, "Updated Legacy Entry")
        XCTAssertEqual(stored.notes, "Edited after migration")
        XCTAssertEqual(stored.verificationStatus, .legacy)
    }

    func testBatchImportDeduplicatesByPMID() throws {
        let db = try makeDatabase()
        let refs = [
            Reference(title: "First Import", pmid: "123456"),
            Reference(title: "Second Import", abstract: "Merged abstract", pmid: "123456")
        ]

        let result = try db.batchImportReferences(refs)
        let all = try db.fetchAllReferences()

        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].pmid, "123456")
        XCTAssertEqual(all[0].abstract, "Merged abstract")
    }

    func testBatchImportKeepsLegacyStatus() throws {
        // File imports (BibTeX/RIS) should stay .legacy, not be promoted to
        // .verifiedManual. That label is reserved for pipeline-verified records.
        let db = try makeDatabase()
        let refs = [Reference(title: "Imported Article"), Reference(title: "Imported Book")]
        _ = try db.batchImportReferences(refs)
        let all = try db.fetchAllReferences()
        XCTAssertTrue(all.allSatisfy { $0.verificationStatus == .legacy })
        XCTAssertTrue(all.allSatisfy { $0.reviewedBy == "file-import" })
    }

    func testBatchImportCanonicalizesBeforeDatabaseCSLAndCiteprocRendering() throws {
        let db = try makeDatabase()
        var imported = Reference(
            title: "  Imported   Stable Article ",
            authors: [AuthorName(given: "Zhang", family: "Sai")],
            year: 2024,
            journal: " Example Journal ",
            volume: " 12 ",
            issue: " 3 ",
            pages: " 45-56 ",
            doi: "https://doi.org/10.1890/12-2010.1",
            referenceType: .other,
            editors: Reference.encodeNames([
                AuthorName(given: "Kattner", family: "G."),
            ]),
            accessedDate: "2026-05-25",
            translators: Reference.encodeNames([
                AuthorName(given: "Graeve", family: "M."),
            ]),
            language: "zh_cn"
        )
        imported.verificationStatus = .legacy

        _ = try db.batchImportReferences([imported])
        let stored = try XCTUnwrap(try db.fetchAllReferences().first)

        XCTAssertEqual(stored.title, "Imported Stable Article")
        XCTAssertEqual(stored.journal, "Example Journal")
        XCTAssertEqual(stored.doi, "10.1890/12-2010.1")
        XCTAssertEqual(stored.referenceType, .journalArticle)
        XCTAssertNil(stored.accessedDate)
        XCTAssertEqual(stored.authors.first, AuthorName(given: "Sai", family: "Zhang"))
        XCTAssertEqual(stored.parsedEditors.first, AuthorName(given: "G", family: "Kattner"))
        XCTAssertEqual(stored.parsedTranslators.first, AuthorName(given: "M", family: "Graeve"))
        XCTAssertEqual(stored.language, "zh-CN")

        let csl = CSLExportService.cslJSONObject(for: stored)
        XCTAssertEqual(csl["type"] as? String, "article-journal")
        XCTAssertEqual(csl["DOI"] as? String, "10.1890/12-2010.1")
        XCTAssertNil(csl["accessed"])
        XCTAssertEqual((csl["editor"] as? [[String: String]])?.first?["family"], "Kattner")
        XCTAssertEqual((csl["editor"] as? [[String: String]])?.first?["given"], "G")
        XCTAssertEqual((csl["translator"] as? [[String: String]])?.first?["family"], "Graeve")
        XCTAssertEqual((csl["translator"] as? [[String: String]])?.first?["given"], "M")

        let styleXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0">
          <info>
            <title>Import Pipeline Test</title>
            <id>import-pipeline-test</id>
          </info>
          <citation>
            <layout prefix="(" suffix=")">
              <date variable="issued"><date-part name="year"/></date>
            </layout>
          </citation>
          <bibliography>
            <layout suffix=".">
              <text variable="title"/>
              <text variable="DOI" prefix=" doi:"/>
            </layout>
          </bibliography>
        </style>
        """
        let localeXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <locale xmlns="http://purl.org/net/xbiblio/csl" xml:lang="en-US"><terms /></locale>
        """
        let engine = try CiteprocJSCoreEngine(styleXML: styleXML, localeXML: localeXML)
        engine.setItems([csl])
        let rendered = try engine.renderDocument(citationClusters: [
            CitationDocumentCluster(
                id: "citation-1",
                itemIDs: [String(try XCTUnwrap(stored.id))],
                position: 0
            )
        ])

        XCTAssertEqual(rendered.citationTexts["citation-1"], "(2024)")
        XCTAssertTrue(rendered.bibliographyText.contains("Imported Stable Article"))
        XCTAssertTrue(rendered.bibliographyText.contains("10.1890/12-2010.1"))
    }

    func testMergePreservesVerifiedFieldsWhenIncomingIsWeaker() throws {
        // When a BibTeX re-import (batchImportReferences) matches an already-verified
        // record, the verified bibliographic fields must not be silently overwritten
        // by the weaker .legacy source.
        //
        // Note: this protection only applies to the batchImportReferences path; a
        // direct saveReference call promotes the record to verifiedManual first and
        // therefore falls outside this guard (intentional — a direct save is user intent).
        let db = try makeDatabase()

        // First: insert a pipeline-verified record directly.
        var verified = Reference(title: "Verified Title")
        verified.doi = "10.1000/test"
        verified.journal = "Verified Journal"
        verified.year = 2024
        verified.verificationStatus = .verifiedAuto
        verified.metadataSource = .crossRef
        verified.reviewedBy = "auto-verify"
        try db.saveReference(&verified)

        // Then: re-import via batchImportReferences (simulating a BibTeX file import
        // for the same paper, with lower-quality metadata).
        var incoming = Reference(title: "Different Title from BibTeX")
        incoming.doi = "10.1000/test"
        incoming.journal = "Wrong Journal Name"
        incoming.year = 2023
        // verificationStatus defaults to .legacy; batchImportReferences keeps it that way.
        _ = try db.batchImportReferences([incoming])

        let all = try db.fetchAllReferences()
        XCTAssertEqual(all.count, 1, "duplicate DOI should merge into one record")
        let merged = try XCTUnwrap(all.first)
        XCTAssertEqual(merged.journal, "Verified Journal", "verified journal must not be overwritten by weaker import")
        XCTAssertEqual(merged.year, 2024, "verified year must not be overwritten by weaker import")
        XCTAssertEqual(merged.verificationStatus, .verifiedAuto, "verification status must not be downgraded")
    }

    func testPersistCandidateResolutionCreatesPendingIntake() throws {
        let db = try makeDatabase()
        let evidence = makeEvidence(source: .cnki, recordKey: "CJFD-2024-001", sourceURL: "https://kns.cnki.net/detail")
        let candidate = MetadataCandidate(
            source: .cnki,
            title: "候选论文",
            authors: [AuthorName(given: "小明", family: "张")],
            journal: "测试期刊",
            year: 2024,
            detailURL: "https://kns.cnki.net/detail",
            score: 0.91
        )

        let result = try db.persistMetadataResolution(
            .candidate(
                CandidateEnvelope(
                    seed: MetadataResolutionSeed(fileName: "candidate.pdf", title: "候选论文", languageHint: .chinese, workKindHint: .journalArticle),
                    fallbackReference: Reference(title: "候选论文"),
                    currentReference: Reference(title: "候选论文"),
                    candidates: [candidate],
                    message: "需要人工确认。",
                    evidence: evidence
                )
            ),
            options: MetadataPersistenceOptions(sourceKind: .manualEntry, originalInput: "候选论文")
        )

        guard case .intake(let intake) = result else {
            return XCTFail("candidate 结果应当持久化为 MetadataIntake")
        }
        XCTAssertEqual(intake.verificationStatus, .candidate)
        XCTAssertEqual(intake.decodedCandidates.count, 1)
        XCTAssertEqual(try db.fetchPendingMetadataIntakes().count, 1)
    }

    func testPersistVerifiedResolutionWritesReference() throws {
        let db = try makeDatabase()
        let evidence = makeEvidence(recordKey: "doi:10.1000/example", sourceURL: "https://doi.org/10.1000/example")
        var verified = Reference(
            title: "Verified Entry",
            authors: [AuthorName(given: "Ada", family: "Lovelace")],
            year: 2024,
            doi: "10.1000/example"
        )
        verified.verificationStatus = .verifiedAuto
        verified.acceptedByRuleID = AcceptedRuleID.j1DOIExact.rawValue
        verified.recordKey = evidence.recordKey
        verified.verificationSourceURL = evidence.sourceURL
        verified.evidenceBundleHash = evidence.bundleHash
        verified.verifiedAt = Date()
        verified.metadataSource = evidence.source

        let result = try db.persistMetadataResolution(
            .verified(VerifiedEnvelope(reference: verified, evidence: evidence)),
            options: MetadataPersistenceOptions(sourceKind: .manualEntry, originalInput: "10.1000/example")
        )

        guard case .verified(let stored) = result else {
            return XCTFail("verified 结果应当直接写入资料库")
        }
        XCTAssertNotNil(stored.id)
        XCTAssertEqual(stored.verificationStatus, .verifiedAuto)
        XCTAssertEqual(try db.referenceCount(), 1)
        XCTAssertTrue(try db.fetchPendingMetadataIntakes().isEmpty)
    }

    func testPersistMetadataEnrichingResolutionWritesReferenceWithoutQueue() throws {
        let db = try makeDatabase()
        let evidence = makeEvidence(source: .webMeta, sourceURL: "https://example.com/article")
        var enriching = Reference(
            title: "Needs Enrichment",
            authors: [AuthorName(given: "Ada", family: "Lovelace")],
            year: 2024,
            journal: "Structured Web Journal",
            url: "https://example.com/article"
        )
        enriching.verificationStatus = .metadataEnriching
        enriching.metadataSource = .webMeta
        enriching.verificationSourceURL = evidence.sourceURL
        enriching.evidenceBundleHash = evidence.bundleHash
        enriching.verifiedAt = Date()

        let result = try db.persistMetadataResolution(
            .verified(VerifiedEnvelope(reference: enriching, evidence: evidence)),
            options: MetadataPersistenceOptions(sourceKind: .manualEntry, originalInput: "https://example.com/article")
        )

        guard case .verified(let stored) = result else {
            return XCTFail("metadataEnriching 结果应当直接写入资料库")
        }
        XCTAssertEqual(stored.verificationStatus, .metadataEnriching)
        XCTAssertEqual(try db.referenceCount(), 1)
        XCTAssertTrue(try db.fetchPendingMetadataIntakes().isEmpty)
    }

    func testPersistVerifiedResolutionUpdatesLinkedReferenceInsteadOfCreatingDuplicate() throws {
        let db = try makeDatabase()

        var original = Reference(title: "原始条目")
        original.notes = "旧备注"
        try db.saveReference(&original)

        let evidence = makeEvidence(
            source: .cnki,
            recordKey: "CJFD-2024-009",
            sourceURL: "https://kns.cnki.net/detail/example",
            fetchMode: .detail
        )
        var verified = Reference(
            title: "刷新后的权威条目",
            authors: [AuthorName(given: "明", family: "李")],
            year: 2024,
            journal: "知网测试期刊"
        )
        verified.verificationStatus = .verifiedManual
        verified.metadataSource = .cnki
        verified.recordKey = evidence.recordKey
        verified.verificationSourceURL = evidence.sourceURL
        verified.evidenceBundleHash = evidence.bundleHash
        verified.reviewedBy = "candidate-selection"
        verified.verifiedAt = Date()

        let result = try db.persistMetadataResolution(
            .verified(VerifiedEnvelope(reference: verified, evidence: evidence)),
            options: MetadataPersistenceOptions(
                sourceKind: .refresh,
                originalInput: "原始条目",
                linkedReferenceId: original.id
            )
        )

        guard case .verified(let stored) = result else {
            return XCTFail("verified 结果应当直接写入原始关联条目")
        }

        XCTAssertEqual(stored.id, original.id)
        XCTAssertEqual(try db.referenceCount(), 1)

        let refreshed = try XCTUnwrap(try db.fetchReferences(ids: [try XCTUnwrap(original.id)]).first)
        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.title, "刷新后的权威条目")
        XCTAssertEqual(refreshed.journal, "知网测试期刊")
        XCTAssertEqual(refreshed.verificationStatus, .verifiedManual)
        XCTAssertEqual(refreshed.metadataSource, .cnki)
        XCTAssertEqual(refreshed.recordKey, "CJFD-2024-009")
    }

    func testConfirmMetadataIntakePromotesToVerifiedManualReference() throws {
        let db = try makeDatabase()
        let evidence = makeEvidence(source: .cnki, recordKey: "CJFD-2024-002", sourceURL: "https://kns.cnki.net/detail")
        let unresolved = Reference(
            title: "待人工确认的条目",
            authors: [AuthorName(given: "华", family: "李")],
            year: 2024,
            journal: "工业验证期刊"
        )

        let persisted = try db.persistMetadataResolution(
            .rejected(
                RejectedEnvelope(
                    seed: MetadataResolutionSeed(fileName: "queued.pdf", title: unresolved.title, firstAuthor: "李华", year: 2024, journal: unresolved.journal, languageHint: .chinese, workKindHint: .journalArticle),
                    fallbackReference: unresolved,
                    currentReference: unresolved,
                    reason: .verifierRuleNotSatisfied,
                    message: "需要人工确认。",
                    evidence: evidence
                )
            ),
            options: MetadataPersistenceOptions(sourceKind: .importedPDF, originalInput: "queued.pdf", preferredPDFPath: "PDFs/queued.pdf")
        )

        guard case .intake(let intake) = persisted else {
            return XCTFail("rejected 结果应当进入待验证队列")
        }

        let confirmed = try db.confirmMetadataIntake(intake, reviewedBy: "unit-test")
        XCTAssertEqual(confirmed.verificationStatus, .verifiedManual)
        XCTAssertEqual(confirmed.reviewedBy, "unit-test")
        XCTAssertEqual(confirmed.pdfPath, "PDFs/queued.pdf")
        XCTAssertEqual(try db.referenceCount(), 1)
        XCTAssertTrue(try db.fetchPendingMetadataIntakes().isEmpty)
    }

    func testConfirmMetadataIntakeUpdatesLinkedReferenceWhenSnapshotHasNoID() throws {
        let db = try makeDatabase()

        var original = Reference(title: "待刷新原条目")
        try db.saveReference(&original)

        let snapshot = Reference(
            title: "人工确认后的条目",
            authors: [AuthorName(given: "华", family: "张")],
            year: 2025,
            journal: "人工确认期刊"
        )
        var intake = MetadataIntake(
            sourceKind: .refresh,
            verificationStatus: .rejectedAmbiguous,
            title: "人工确认后的条目",
            currentReferenceJSON: MetadataVerificationCodec.encodeToJSONString(snapshot),
            linkedReferenceId: original.id
        )
        try db.saveMetadataIntake(&intake)

        let confirmed = try db.confirmMetadataIntake(intake, reviewedBy: "unit-test")

        XCTAssertEqual(confirmed.id, original.id)
        XCTAssertEqual(confirmed.verificationStatus, .verifiedManual)
        XCTAssertEqual(confirmed.reviewedBy, "unit-test")
        XCTAssertEqual(try db.referenceCount(), 1)

        let refreshed = try XCTUnwrap(try db.fetchReferences(ids: [try XCTUnwrap(original.id)]).first)
        XCTAssertEqual(refreshed.title, "人工确认后的条目")
        XCTAssertEqual(refreshed.journal, "人工确认期刊")
        XCTAssertEqual(refreshed.verificationStatus, .verifiedManual)
    }

    // MARK: - Fetch All

    func testFetchAllReferences() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "FetchAll Test")
        try db.saveReference(&ref)

        let all = try db.fetchAllReferences()
        XCTAssertTrue(all.count >= 1, "Should have at least one reference")
    }

    func testFetchAllReferencesWithLimit() throws {
        let db = try makeDatabase()
        for i in 0..<5 {
            var ref = Reference(title: "Limit Test \(i)")
            try db.saveReference(&ref)
        }

        let limited = try db.fetchAllReferences(limit: 3)
        XCTAssertEqual(limited.count, 3)
    }

    // MARK: - Search

    func testSearchReferences() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Quantum Computing Advances")
        try db.saveReference(&ref)

        let results = try db.searchReferences(query: "Quantum")
        XCTAssertTrue(results.count >= 1,
                      "Search should find the reference with 'Quantum' in title")
    }

    func testSearchReferencesNoResults() throws {
        let db = try makeDatabase()
        let results = try db.searchReferences(query: "zzzNonExistentTermXYZ")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Collection CRUD

    func testSaveAndFetchCollection() throws {
        let db = try makeDatabase()
        var col = Collection(name: "Test Collection")
        try db.saveCollection(&col)
        XCTAssertNotNil(col.id)

        let all = try db.fetchAllCollections()
        XCTAssertTrue(all.contains(where: { $0.id == col.id }))
    }

    func testDeleteCollection() throws {
        let db = try makeDatabase()
        var col = Collection(name: "To Delete")
        try db.saveCollection(&col)
        let id = col.id!

        try db.deleteCollection(id: id)
        let all = try db.fetchAllCollections()
        XCTAssertFalse(all.contains(where: { $0.id == id }))
    }

    // MARK: - Workspace CRUD and Layout Snapshots

    func testSystemWorkspaceCreatedByMigration() throws {
        let db = try makeDatabase()

        let allWorkspace = try XCTUnwrap(try db.fetchAllWorkspaces().first(where: { $0.kind == .all }))

        XCTAssertEqual(allWorkspace.name, "全部文献")
        XCTAssertEqual(allWorkspace.icon, "books.vertical")
        XCTAssertTrue(allWorkspace.isSystem)
    }

    func testWorkspaceMembershipFiltersReferencesWithoutDuplicatingLibrary() throws {
        let db = try makeDatabase()
        var workspace = Workspace(name: "论文写作", icon: "graduationcap", kind: .manual)
        try db.saveWorkspace(&workspace)

        var included = Reference(title: "Included Reference")
        var excluded = Reference(title: "Excluded Reference")
        try db.saveReference(&included)
        try db.saveReference(&excluded)

        try db.addReferences(ids: [try XCTUnwrap(included.id)], toWorkspaceId: try XCTUnwrap(workspace.id))

        var filter = ReferenceFilter()
        filter.workspaceId = workspace.id
        let rows = try db.fetchReferenceListRows(scope: .all, filter: filter, limit: 0)

        XCTAssertEqual(rows.map(\.id), [included.id])
        XCTAssertEqual(try db.referenceCount(), 2)
    }

    func testWorkspaceLayoutSnapshotRoundTrips() throws {
        let db = try makeDatabase()
        var workspace = Workspace(name: "阅读布局", icon: "book.closed", kind: .manual)
        try db.saveWorkspace(&workspace)

        let snapshot = WorkspaceLayoutSnapshot(
            selectedReferenceId: 42,
            sidebarSelection: .tag(7),
            searchText: "transformer",
            columnVisibility: .doubleColumn,
            capturedAt: Date(timeIntervalSince1970: 1_800)
        )

        try db.saveWorkspaceLayoutSnapshot(snapshot, forWorkspaceId: try XCTUnwrap(workspace.id))

        let restored = try XCTUnwrap(try db.fetchWorkspaceLayoutSnapshot(workspaceId: try XCTUnwrap(workspace.id)))
        XCTAssertEqual(restored.selectedReferenceId, 42)
        XCTAssertEqual(restored.sidebarSelection, .tag(7))
        XCTAssertEqual(restored.searchText, "transformer")
        XCTAssertEqual(restored.columnVisibility, .doubleColumn)
        XCTAssertEqual(restored.capturedAt, Date(timeIntervalSince1970: 1_800))
    }

    // MARK: - Filter by Collection

    func testFetchReferencesByCollection() throws {
        let db = try makeDatabase()
        var col = Collection(name: "Filter Col")
        try db.saveCollection(&col)

        var ref = Reference(title: "In Collection")
        ref.collectionId = col.id
        try db.saveReference(&ref)

        let results = try db.fetchReferences(collectionId: col.id!)
        XCTAssertTrue(results.contains(where: { $0.id == ref.id }))
    }

    // MARK: - Tag CRUD

    func testSaveAndFetchTag() throws {
        let db = try makeDatabase()
        var tag = Tag(name: "Test Tag", color: "#FF0000")
        try db.saveTag(&tag)
        XCTAssertNotNil(tag.id)

        let all = try db.fetchAllTags()
        XCTAssertTrue(all.contains(where: { $0.id == tag.id }))
    }

    func testDeleteTag() throws {
        let db = try makeDatabase()
        var tag = Tag(name: "To Delete")
        try db.saveTag(&tag)
        let id = tag.id!

        try db.deleteTag(id: id)
        let all = try db.fetchAllTags()
        XCTAssertFalse(all.contains(where: { $0.id == id }))
    }

    // MARK: - Tag Assignment

    func testSetTagsForReference() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Tag Assignment Test")
        try db.saveReference(&ref)
        var tag1 = Tag(name: "Tag A")
        var tag2 = Tag(name: "Tag B")
        try db.saveTag(&tag1)
        try db.saveTag(&tag2)

        try db.setTags(forReference: ref.id!, tagIds: [tag1.id!, tag2.id!])
        let tags = try db.fetchTags(forReference: ref.id!)
        XCTAssertEqual(tags.count, 2)
    }

    func testFetchReferencesByTag() throws {
        let db = try makeDatabase()
        var tag = Tag(name: "Filter Tag")
        try db.saveTag(&tag)
        var ref = Reference(title: "Tagged Reference")
        try db.saveReference(&ref)
        try db.setTags(forReference: ref.id!, tagIds: [tag.id!])

        let results = try db.fetchReferences(tagId: tag.id!)
        XCTAssertTrue(results.contains(where: { $0.id == ref.id }))
    }

    // MARK: - Batch Import

    func testBatchImportReferences() throws {
        let db = try makeDatabase()
        let refs = [
            Reference(title: "Batch 1"),
            Reference(title: "Batch 2"),
            Reference(title: "Batch 3"),
        ]

        let result = try db.batchImportReferences(refs)
        XCTAssertEqual(result.total, 3)

        let all = try db.fetchAllReferences()
        XCTAssertEqual(all.count, 3)
    }

    func testBatchImportEmptyArray() throws {
        let db = try makeDatabase()
        let result = try db.batchImportReferences([])
        XCTAssertEqual(result.total, 0)
    }

    // MARK: - Reference Count

    func testReferenceCount() throws {
        let db = try makeDatabase()
        var ref1 = Reference(title: "Count 1")
        var ref2 = Reference(title: "Count 2")
        try db.saveReference(&ref1)
        try db.saveReference(&ref2)

        let count = try db.referenceCount()
        XCTAssertEqual(count, 2)
    }

    func testReferenceCountByCollection() throws {
        let db = try makeDatabase()
        var col = Collection(name: "Count Col")
        try db.saveCollection(&col)

        var ref1 = Reference(title: "In Col")
        ref1.collectionId = col.id
        var ref2 = Reference(title: "No Col")
        try db.saveReference(&ref1)
        try db.saveReference(&ref2)

        let count = try db.referenceCount(collectionId: col.id!)
        XCTAssertEqual(count, 1)
    }

    // MARK: - PDF Annotation CRUD

    func testSaveAndFetchAnnotation() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Annotation Test Ref")
        try db.saveReference(&ref)

        var annotation = PDFAnnotationRecord(
            referenceId: ref.id!,
            type: .highlight,
            selectedText: "Highlighted text",
            pageIndex: 3,
            rects: [CGRect(x: 10, y: 20, width: 100, height: 15)]
        )
        try db.saveAnnotation(&annotation)
        XCTAssertNotNil(annotation.id)

        let annotations = try db.fetchAnnotations(referenceId: ref.id!)
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].selectedText, "Highlighted text")
    }

    func testDeleteAnnotation() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Delete Annotation Ref")
        try db.saveReference(&ref)

        var annotation = PDFAnnotationRecord(
            referenceId: ref.id!,
            type: .note,
            noteText: "A note",
            pageIndex: 1,
            rects: [CGRect(x: 0, y: 0, width: 50, height: 10)]
        )
        try db.saveAnnotation(&annotation)
        let id = annotation.id!

        try db.deleteAnnotation(id: id)
        let annotations = try db.fetchAnnotations(referenceId: ref.id!)
        XCTAssertTrue(annotations.isEmpty)
    }

    func testAnnotationCount() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Annotation Count Ref")
        try db.saveReference(&ref)

        for i in 0..<3 {
            var a = PDFAnnotationRecord(
                referenceId: ref.id!,
                type: .highlight,
                pageIndex: i,
                rects: [CGRect(x: 0, y: 0, width: 50, height: 10)]
            )
            try db.saveAnnotation(&a)
        }

        let count = try db.annotationCount(referenceId: ref.id!)
        XCTAssertEqual(count, 3)
    }

    // MARK: - Web Annotation CRUD

    func testSaveAndFetchWebAnnotation() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Web Annotation Test")
        ref.url = "https://example.com/article"
        try db.saveReference(&ref)

        var annotation = WebAnnotationRecord(
            referenceId: ref.id!,
            type: .highlight,
            selectedText: "Important web content",
            anchorText: "Important"
        )
        try db.saveWebAnnotation(&annotation)
        XCTAssertNotNil(annotation.id)

        let annotations = try db.fetchWebAnnotations(referenceId: ref.id!)
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].selectedText, "Important web content")
    }

    func testDeleteWebAnnotation() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Delete Web Annotation")
        try db.saveReference(&ref)

        var annotation = WebAnnotationRecord(
            referenceId: ref.id!,
            type: .note,
            selectedText: "Selected",
            noteText: "My note",
            anchorText: "Selected"
        )
        try db.saveWebAnnotation(&annotation)
        let id = annotation.id!

        try db.deleteWebAnnotation(id: id)
        let annotations = try db.fetchWebAnnotations(referenceId: ref.id!)
        XCTAssertTrue(annotations.isEmpty)
    }

    func testWebAnnotationCount() throws {
        let db = try makeDatabase()
        var ref = Reference(title: "Web Annotation Count")
        try db.saveReference(&ref)

        for i in 0..<2 {
            var a = WebAnnotationRecord(
                referenceId: ref.id!,
                type: .highlight,
                selectedText: "Text \(i)",
                anchorText: "Text \(i)"
            )
            try db.saveWebAnnotation(&a)
        }

        let count = try db.webAnnotationCount(referenceId: ref.id!)
        XCTAssertEqual(count, 2)
    }
}
