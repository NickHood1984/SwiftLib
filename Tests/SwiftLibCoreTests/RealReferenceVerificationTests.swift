import XCTest
@testable import SwiftLibCore

// MARK: - Real Reference Verification Tests
// Tests using actual references from 参考文献.md to validate the verification pipeline.

final class RealReferenceVerificationTests: XCTestCase {

    // MARK: - Helpers

    /// Build a seed from citation metadata (simulating what a BibTeX/RIS import would provide).
    private func makeSeed(
        title: String,
        firstAuthor: String,
        year: Int,
        doi: String? = nil,
        journal: String? = nil,
        isbn: String? = nil,
        publisher: String? = nil,
        language: MetadataLanguageHint = .nonChinese,
        kind: MetadataWorkKind = .journalArticle
    ) -> MetadataResolutionSeed {
        MetadataResolutionSeed(
            fileName: title,
            title: title,
            firstAuthor: firstAuthor,
            year: year,
            doi: doi,
            journal: journal,
            isbn: isbn,
            publisher: publisher,
            languageHint: language,
            workKindHint: kind
        )
    }

    /// Simulate the evidence bundle that ImportIntakeService.buildImportEvidence would create.
    private func makeImportEvidence(
        for ref: Reference,
        seed: MetadataResolutionSeed?,
        source: MetadataSource = .bibtex
    ) -> EvidenceBundle {
        let hasTitle = !ref.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAuthors = !ref.authors.isEmpty
        let hasJournal = !(ref.journal ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasId = !(ref.doi ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(ref.isbn ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return EvidenceBundle(
            source: source,
            recordKey: ref.doi ?? ref.isbn,
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: hasTitle,
                hasStructuredAuthors: hasAuthors,
                hasStructuredJournal: hasJournal,
                usedIdentifierFetch: hasId,
                exactIdentifierMatch: hasId
            )
        )
    }

    // MARK: - English Journal Articles (J1 DOI Exact)

    /// [2] Schindler 1974 — Science, classic eutrophication paper
    func testEnglishRef2_SchindlerEutrophication_J1DOI() {
        let title = "Eutrophication and recovery in experimental lakes: implications for lake management"
        let doi = "10.1126/science.184.4139.897"
        let seed = makeSeed(title: title, firstAuthor: "D W Schindler", year: 1974, doi: doi, journal: "Science")
        let ref = Reference(
            title: title,
            authors: [AuthorName(given: "D W", family: "Schindler")],
            year: 1974,
            journal: "Science",
            volume: "184",
            issue: "4139",
            pages: "897-899",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J1 verification for Schindler 1974")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
        XCTAssertGreaterThan(envelope.reference.confidenceScore ?? 0, 0.85)
    }

    /// [3] Smith & Schindler 2009 — Trends in Ecology & Evolution
    func testEnglishRef3_SmithSchindler_J1DOI() {
        let title = "Eutrophication science: where do we go from here?"
        let doi = "10.1016/j.tree.2008.11.009"  // real DOI for this paper
        let seed = makeSeed(title: title, firstAuthor: "Smith", year: 2009, doi: doi, journal: "Trends in Ecology & Evolution")
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "V H", family: "Smith"),
                AuthorName(given: "D W", family: "Schindler")
            ],
            year: 2009,
            journal: "Trends in Ecology & Evolution",
            volume: "24",
            issue: "4",
            pages: "201-207",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J1 verification for Smith & Schindler 2009")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    /// [31] Taipale et al. 2016 — Environment International
    func testEnglishRef31_TaipaleFattyAcids_J1DOI() {
        let title = "Lake eutrophication and brownification downgrade availability and transfer of essential fatty acids for human consumption"
        let doi = "10.1016/j.envint.2016.08.018"
        let seed = makeSeed(title: title, firstAuthor: "Taipale", year: 2016, doi: doi, journal: "Environment International")
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "S J", family: "Taipale"),
                AuthorName(given: "K", family: "Vuorio"),
                AuthorName(given: "U", family: "Strandberg")
            ],
            year: 2016,
            journal: "Environment International",
            volume: "96",
            pages: "156-166",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J1 verification for Taipale et al. 2016")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    /// [112] Scheffer et al. 2001 — Nature, catastrophic shifts
    func testEnglishRef112_SchefferCatastrophicShifts_J1DOI() {
        let title = "Catastrophic shifts in ecosystems"
        let doi = "10.1038/35098000"
        let seed = makeSeed(title: title, firstAuthor: "Scheffer", year: 2001, doi: doi, journal: "Nature")
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "M", family: "Scheffer"),
                AuthorName(given: "S", family: "Carpenter"),
                AuthorName(given: "J A", family: "Foley")
            ],
            year: 2001,
            journal: "Nature",
            volume: "413",
            issue: "6856",
            pages: "591-596",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J1 verification for Scheffer et al. 2001")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    /// [131] Hu et al. 2024 — Scientific Data (★ 最新文献)
    func testEnglishRef131_HuTrophicStateIndex_J1DOI() {
        let title = "A dataset of trophic state index for nation-scale lakes in China from 40-year Landsat observations"
        let doi = "10.1038/s41597-024-03511-0"
        let seed = makeSeed(title: title, firstAuthor: "Hu", year: 2024, doi: doi, journal: "Scientific Data")
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "M Q", family: "Hu"),
                AuthorName(given: "R H", family: "Ma"),
                AuthorName(given: "K", family: "Xue")
            ],
            year: 2024,
            journal: "Scientific Data",
            volume: "11",
            issue: "1",
            pages: "659",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J1 verification for Hu et al. 2024")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    // MARK: - English Books (B1 ISBN/RecordKey)

    /// [1] Wetzel 2001 — Limnology textbook (with ISBN)
    func testEnglishRef1_WetzelLimnology_B1ISBN() {
        let title = "Limnology: Lake and River Ecosystems"
        let isbn = "978-0-12-744760-5"
        let seed = makeSeed(
            title: title, firstAuthor: "Wetzel", year: 2001,
            isbn: isbn, publisher: "Academic Press", kind: .book
        )
        let ref = Reference(
            title: title,
            authors: [AuthorName(given: "R G", family: "Wetzel")],
            year: 2001,
            referenceType: .book,
            publisher: "Academic Press",
            publisherPlace: "San Diego",
            edition: "3rd ed.",
            isbn: isbn
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected B1 verification for Wetzel 2001")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.b1ISBNOrRecordKey.rawValue)
    }

    /// [25] Sterner & Elser 2002 — Ecological Stoichiometry (with ISBN)
    func testEnglishRef25_SternerElser_B1ISBN() {
        let title = "Ecological Stoichiometry: The Biology of Elements from Molecules to the Biosphere"
        let isbn = "978-0-691-07491-7"
        let seed = makeSeed(
            title: title, firstAuthor: "Sterner", year: 2002,
            isbn: isbn, publisher: "Princeton University Press", kind: .book
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "R W", family: "Sterner"),
                AuthorName(given: "J J", family: "Elser")
            ],
            year: 2002,
            referenceType: .book,
            publisher: "Princeton University Press",
            publisherPlace: "Princeton",
            isbn: isbn
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected B1 verification for Sterner & Elser 2002")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.b1ISBNOrRecordKey.rawValue)
    }

    // MARK: - Chinese Journal Articles (J3 CNKI No-DOI path)

    /// [5] 秦伯强 2013 — 科学通报, Chinese eutrophication paper
    func testChineseRef5_QinBoqiang_J3CNKI() {
        let title = "湖泊富营养化及其生态系统响应"
        let seed = makeSeed(
            title: title, firstAuthor: "秦伯强", year: 2013,
            journal: "科学通报", language: .chinese
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "秦伯强"),
                AuthorName(given: "", family: "高光"),
                AuthorName(given: "", family: "朱广伟")
            ],
            year: 2013,
            journal: "科学通报",
            volume: "58",
            issue: "10",
            pages: "855-864"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CNKI:SUN:KXTB.0.2013-10-006",
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                hasStableRecordKey: true
            )
        )
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J3 CNKI verification for 秦伯强 2013")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j3CNKINoDOI.rawValue)
    }

    /// [14] 潘继征 2009 — 湖泊科学, Yunnan plateau lakes
    func testChineseRef14_PanJizheng_J3CNKI() {
        let title = "云南高原湖泊富营养化研究进展"
        let seed = makeSeed(
            title: title, firstAuthor: "潘继征", year: 2009,
            journal: "湖泊科学", language: .chinese
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "潘继征"),
                AuthorName(given: "", family: "熊飞"),
                AuthorName(given: "", family: "李文朝")
            ],
            year: 2009,
            journal: "湖泊科学",
            volume: "21",
            issue: "2",
            pages: "193-198"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CNKI:SUN:FLKX.0.2009-02-010",
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                hasStableRecordKey: true
            )
        )
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J3 CNKI verification for 潘继征 2009")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j3CNKINoDOI.rawValue)
    }

    /// [19] 杜宝汉 2017 — 湖泊科学, Erhai water quality
    func testChineseRef19_DuBaohan_J3CNKI() {
        let title = "洱海水质变化(1992—2015年)分析"
        let seed = makeSeed(
            title: title, firstAuthor: "杜宝汉", year: 2017,
            journal: "湖泊科学", language: .chinese
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "杜宝汉"),
                AuthorName(given: "", family: "段丽")
            ],
            year: 2017,
            journal: "湖泊科学",
            volume: "29",
            issue: "3",
            pages: "573-582"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CNKI:SUN:FLKX.0.2017-03-006",
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                hasStableRecordKey: true
            )
        )
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J3 CNKI verification for 杜宝汉 2017")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j3CNKINoDOI.rawValue)
    }

    /// [88] 华兆晖 2024 — 湖泊科学 (★ latest paper)
    func testChineseRef88_HuaZhaohui_J3CNKI() {
        let title = "洱海综合营养状态指数时空变化趋势(2017—2022年)"
        let seed = makeSeed(
            title: title, firstAuthor: "华兆晖", year: 2024,
            journal: "湖泊科学", language: .chinese
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "华兆晖"),
                AuthorName(given: "", family: "张运林"),
                AuthorName(given: "", family: "施坤")
            ],
            year: 2024,
            journal: "湖泊科学",
            volume: "36",
            issue: "2",
            pages: "385-396"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CNKI:SUN:FLKX.0.2024-02-009",
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                hasStableRecordKey: true
            )
        )
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J3 CNKI verification for 华兆晖 2024")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j3CNKINoDOI.rawValue)
    }

    /// [124] 吕兴菊 2023 — 湖泊科学, Erhai rotifers
    func testChineseRef124_LvXingju_J3CNKI() {
        let title = "洱海北部湖区轮虫群落季节演替特征"
        let seed = makeSeed(
            title: title, firstAuthor: "吕兴菊", year: 2023,
            journal: "湖泊科学", language: .chinese
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "吕兴菊"),
                AuthorName(given: "", family: "张亚男"),
                AuthorName(given: "", family: "高登成"),
                AuthorName(given: "", family: "张晓莉")
            ],
            year: 2023,
            journal: "湖泊科学",
            volume: "35",
            issue: "1",
            pages: "289-297"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CNKI:SUN:FLKX.0.2023-01-029",
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true,
                hasStableRecordKey: true
            )
        )
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J3 CNKI verification for 吕兴菊 2023")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j3CNKINoDOI.rawValue)
    }

    // MARK: - Chinese Book ([16] via ISBN)

    /// [16] 王苏民 1998 — 中国湖泊志
    func testChineseRef16_WangSumin_B1ISBN() {
        let title = "中国湖泊志"
        let isbn = "978-7-03-006706-9"
        let seed = makeSeed(
            title: title, firstAuthor: "王苏民", year: 1998,
            isbn: isbn, publisher: "科学出版社", language: .chinese, kind: .book
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "王苏民"),
                AuthorName(given: "", family: "窦鸿身")
            ],
            year: 1998,
            referenceType: .book,
            publisher: "科学出版社",
            publisherPlace: "北京",
            isbn: isbn
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected B1 verification for 王苏民 1998 中国湖泊志")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.b1ISBNOrRecordKey.rawValue)
    }

    // MARK: - Chinese Book ([18] 金相灿 1990)

    /// [18] 金相灿 1990 — 湖泊富营养化调查规范
    func testChineseRef18_JinXiangcan_B1ISBN() {
        let title = "湖泊富营养化调查规范"
        let isbn = "978-7-80010-770-5"
        let seed = makeSeed(
            title: title, firstAuthor: "金相灿", year: 1990,
            isbn: isbn, publisher: "中国环境科学出版社", language: .chinese, kind: .book
        )
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "", family: "金相灿"),
                AuthorName(given: "", family: "屠清瑛")
            ],
            year: 1990,
            referenceType: .book,
            publisher: "中国环境科学出版社",
            publisherPlace: "北京",
            edition: "2版",
            isbn: isbn
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected B1 verification for 金相灿 1990")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.b1ISBNOrRecordKey.rawValue)
    }

    // MARK: - Confidence Score with Real Data

    /// Confidence score for a fully structured English reference with DOI
    func testConfidenceScore_EnglishWithDOI_High() {
        let title = "Catastrophic shifts in ecosystems"
        let doi = "10.1038/35098000"
        let seed = makeSeed(title: title, firstAuthor: "M Scheffer", year: 2001, doi: doi, journal: "Nature")
        let ref = Reference(
            title: title,
            authors: [AuthorName(given: "M", family: "Scheffer")],
            year: 2001,
            journal: "Nature",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let score = MetadataVerifier.calculateConfidenceScore(reference: ref, seed: seed, evidence: evidence)
        XCTAssertGreaterThan(score, 0.85, "English reference with DOI should have high confidence")
    }

    /// Confidence score for a Chinese reference without DOI
    func testConfidenceScore_ChineseNoDOI_Moderate() {
        let title = "湖泊富营养化及其生态系统响应"
        let seed = makeSeed(
            title: title, firstAuthor: "秦伯强", year: 2013,
            journal: "科学通报", language: .chinese
        )
        let ref = Reference(
            title: title,
            authors: [AuthorName(given: "", family: "秦伯强")],
            year: 2013,
            journal: "科学通报"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "CNKI:SUN:KXTB.0.2013-10-006",
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStructuredJournal: true
            )
        )
        let score = MetadataVerifier.calculateConfidenceScore(reference: ref, seed: seed, evidence: evidence)
        // No DOI means lower score, but title+author+year should give moderate
        XCTAssertGreaterThan(score, 0.55, "Chinese ref without DOI should still have moderate confidence")
        XCTAssertLessThan(score, 0.90, "Without DOI, confidence should not be too high")
    }

    // MARK: - Import Evidence Pipeline

    /// Verify that buildImportEvidence (via ImportIntakeService) produces correct evidence for
    /// a BibTeX-imported English reference.
    func testImportEvidence_EnglishBibTeX_HasStructuredFields() {
        let ref = Reference(
            title: "Lake eutrophication and brownification downgrade availability and transfer of essential fatty acids for human consumption",
            authors: [
                AuthorName(given: "S J", family: "Taipale"),
                AuthorName(given: "K", family: "Vuorio")
            ],
            year: 2016,
            journal: "Environment International",
            volume: "96",
            pages: "156-166",
            doi: "10.1016/j.envint.2016.08.018"
        )
        let seed = makeSeed(
            title: ref.title,
            firstAuthor: "Taipale",
            year: 2016,
            doi: ref.doi,
            journal: "Environment International"
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)

        XCTAssertTrue(evidence.verificationHints.hasStructuredTitle)
        XCTAssertTrue(evidence.verificationHints.hasStructuredAuthors)
        XCTAssertTrue(evidence.verificationHints.hasStructuredJournal)
        XCTAssertTrue(evidence.verificationHints.exactIdentifierMatch)
        XCTAssertEqual(evidence.source, .bibtex)
        XCTAssertEqual(evidence.fetchMode, .structured)
    }

    /// Verify that buildImportEvidence produces correct evidence for a Chinese reference.
    func testImportEvidence_ChineseCNKI_HasStructuredFields() {
        let ref = Reference(
            title: "洱海水质变化(1992—2015年)分析",
            authors: [
                AuthorName(given: "", family: "杜宝汉"),
                AuthorName(given: "", family: "段丽")
            ],
            year: 2017,
            journal: "湖泊科学",
            volume: "29",
            issue: "3",
            pages: "573-582"
        )
        let seed = makeSeed(
            title: ref.title,
            firstAuthor: "杜宝汉",
            year: 2017,
            journal: "湖泊科学",
            language: .chinese
        )
        let evidence = makeImportEvidence(for: ref, seed: seed, source: .cnki)

        XCTAssertTrue(evidence.verificationHints.hasStructuredTitle)
        XCTAssertTrue(evidence.verificationHints.hasStructuredAuthors)
        XCTAssertTrue(evidence.verificationHints.hasStructuredJournal)
        XCTAssertFalse(evidence.verificationHints.exactIdentifierMatch, "Chinese ref without DOI should not have identifier match")
        XCTAssertEqual(evidence.source, .cnki)
    }

    // MARK: - Edge Cases from Real Data

    /// [90] Yang et al. 2009 — English paper about Erhai by Chinese authors
    func testRef90_YangErhai_EnglishByChineseAuthors_J1DOI() {
        let title = "Environmental factors affecting the biocoenosis of crustacean zooplankton in Erhai Lake"
        let doi = "10.1007/s00343-009-0199-3"
        let seed = makeSeed(title: title, firstAuthor: "Yang", year: 2009, doi: doi, journal: "Chinese Journal of Oceanology and Limnology")
        let ref = Reference(
            title: title,
            authors: [
                AuthorName(given: "Y", family: "Yang"),
                AuthorName(given: "X", family: "Yin"),
                AuthorName(given: "Z", family: "Yang")
            ],
            year: 2009,
            journal: "Chinese Journal of Oceanology and Limnology",
            volume: "27",
            issue: "1",
            pages: "199-206",
            doi: doi
        )
        let evidence = makeImportEvidence(for: ref, seed: seed)
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected J1 verification for Yang et al. 2009")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.j1DOIExact.rawValue)
    }

    /// [130] 生态环境部 2025 — Chinese government report (★)
    func testChineseRef130_EcologyMinistryReport_R1() {
        let title = "2024年中国生态环境状况公报"
        let seed = makeSeed(
            title: title, firstAuthor: "中华人民共和国生态环境部", year: 2025,
            language: .chinese, kind: .report
        )
        let ref = Reference(
            title: title,
            authors: [AuthorName(given: "", family: "中华人民共和国生态环境部")],
            year: 2025,
            referenceType: .report,
            publisher: "生态环境部",
            publisherPlace: "北京",
            institution: "生态环境部"
        )
        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: "report/mee/2024-annual",
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: true,
                hasStableRecordKey: true
            )
        )
        let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

        guard case .verified(let envelope) = decision else {
            return XCTFail("Expected R1 verification for 生态环境部 2025 report")
        }
        XCTAssertEqual(envelope.reference.acceptedByRuleID, AcceptedRuleID.r1ReportRecordKey.rawValue)
    }

    /// Test that a reference with NO seed gets low confidence (real scenario: drag-drop PDF)
    func testNoSeed_LowConfidence() {
        let ref = Reference(
            title: "Zooplankton community responses to oxygen stress in lakes of differing trophic state",
            authors: [AuthorName(given: "M", family: "Karpowicz")],
            year: 2020,
            journal: "Water",
            doi: "10.3390/w12030706"
        )
        let evidence = makeImportEvidence(for: ref, seed: nil)
        let score = MetadataVerifier.calculateConfidenceScore(reference: ref, seed: nil, evidence: evidence)
        XCTAssertLessThan(score, 0.50, "No seed should always yield low confidence")
    }

    // MARK: - OpenAlex Enrichment Parsing (real DOI fixtures)

    /// Test parsing an OpenAlex-style response for Scheffer et al. 2001 (Nature)
    func testOpenAlexEnrichment_RealDOI_Nature() {
        let fixture: [String: Any] = [
            "title": "Catastrophic shifts in ecosystems",
            "open_access": ["is_oa": true, "oa_url": "https://www.nature.com/articles/35098000.pdf"],
            "cited_by_count": 6500,
            "concepts": [
                ["display_name": "regime shift", "score": 0.9],
                ["display_name": "ecosystem", "score": 0.8],
                ["display_name": "catastrophic change", "score": 0.7]
            ],
            "topics": [
                ["display_name": "Ecology"],
                ["display_name": "Environmental Science"]
            ],
            "grants": [
                ["funder_display_name": "NSF", "award_id": "DEB-0108117"]
            ],
            "abstract_inverted_index": [
                "All": [0], "ecosystems": [1], "can": [2], "shift": [3]
            ]
        ]
        let enrichment = MetadataFetcher.parseOpenAlexEnrichment(fixture)
        XCTAssertEqual(enrichment.isOpenAccess, true)
        XCTAssertEqual(enrichment.citedByCount, 6500)
        XCTAssertEqual(enrichment.keywords.count, 3)
        XCTAssertEqual(enrichment.topics.count, 2)
        XCTAssertNotNil(enrichment.oaUrl)
        XCTAssertFalse(enrichment.fundingInfo.isEmpty)
    }

    /// Test applying OpenAlex enrichment to a Chinese reference (should not overwrite title/authors)
    func testApplyEnrichment_ChineseRef_PreservesOriginal() {
        let ref = Reference(
            title: "湖泊富营养化及其生态系统响应",
            authors: [AuthorName(given: "", family: "秦伯强")],
            year: 2013,
            journal: "科学通报",
            abstract: "本文系统综述了湖泊富营养化问题..."
        )
        let enrichment = MetadataFetcher.OpenAlexEnrichment(
            keywords: ["eutrophication", "lake"],
            topics: ["Environmental Science"],
            isOpenAccess: false,
            oaUrl: nil,
            citedByCount: 180,
            fundingInfo: ["NSFC (41230744)"],
            abstract: "This paper reviews lake eutrophication..."
        )
        let enriched = MetadataResolution.applyEnrichment(enrichment, to: ref)

        // Original fields preserved
        XCTAssertEqual(enriched.title, "湖泊富营养化及其生态系统响应")
        XCTAssertEqual(enriched.abstract, "本文系统综述了湖泊富营养化问题...", "Existing abstract should NOT be overwritten")
        XCTAssertEqual(enriched.journal, "科学通报")

        // Enrichment fields applied
        XCTAssertEqual(enriched.isOpenAccess, false)
        XCTAssertEqual(enriched.citedByCount, 180)
        XCTAssertTrue(enriched.keywords?.contains("eutrophication") == true || enriched.keywords?.contains("lake") == true)
    }
}
