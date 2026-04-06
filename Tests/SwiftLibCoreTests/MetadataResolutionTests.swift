import XCTest
@testable import SwiftLibCore

final class MetadataResolutionTests: XCTestCase {
    func testSeedExtractionPrefersFilenamePatternForChinesePDF() {
        let extracted = PDFService.ExtractedMetadata(
            title: nil,
            authors: [],
            year: 2023,
            doi: "10.18307/2023.0320",
            abstract: nil,
            journal: nil
        )

        let seed = MetadataResolutionSeed.fromImportedPDF(
            url: URL(fileURLWithPath: "/tmp/多目标驱动的太湖调度水位研究_吴浩云(1).pdf"),
            extracted: extracted
        )

        XCTAssertEqual(seed.title, "多目标驱动的太湖调度水位研究")
        XCTAssertEqual(seed.firstAuthor, "吴浩云")
        XCTAssertEqual(seed.year, 2023)
        XCTAssertEqual(seed.doi, "10.18307/2023.0320")
        XCTAssertEqual(seed.languageHint, .chinese)
    }

    func testCleanPDFSeedFilenameRemovesDownloadNoise() {
        XCTAssertEqual(
            MetadataResolution.cleanPDFSeedFilename("多目标驱动的太湖调度水位研究_吴浩云（1）_中国知网.pdf"),
            "多目标驱动的太湖调度水位研究_吴浩云"
        )
    }

    func testCNKICandidateScoringPrefersTitleAndAuthorMatch() {
        let seed = MetadataResolutionSeed(
            fileName: "多目标驱动的太湖调度水位研究_吴浩云",
            title: "多目标驱动的太湖调度水位研究",
            firstAuthor: "吴浩云",
            year: 2023,
            journal: "湖泊科学",
            languageHint: .chinese
        )

        let strong = MetadataResolution.buildCNKICandidate(
            title: "多目标驱动的太湖调度水位研究",
            metaText: "吴浩云，张三 湖泊科学 2023年第3期 120-128",
            snippet: nil,
            detailURL: "https://kns.cnki.net/detail/strong",
            seed: seed
        )

        let weak = MetadataResolution.buildCNKICandidate(
            title: "太湖水位调度研究综述",
            metaText: "李四 水资源研究 2021年第2期 90-96",
            snippet: nil,
            detailURL: "https://kns.cnki.net/detail/weak",
            seed: seed
        )

        XCTAssertNotNil(strong)
        XCTAssertNotNil(weak)
        XCTAssertTrue((strong?.score ?? 0) > (weak?.score ?? 0))
        XCTAssertEqual(strong?.authors.first?.family, "吴浩云")
        XCTAssertEqual(strong?.journal, "湖泊科学")
    }

    func testTitleSimilarityHandlesYearPrefixAndMinorChineseFunctionWords() {
        let lhs = "洱海营养状态时空变化趋势及成因分析"
        let rhs = "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析"

        XCTAssertGreaterThanOrEqual(MetadataResolution.titleSimilarity(lhs, rhs), 0.85)
    }

    func testCNKICandidateKeepsNearMatchWhenTitleHasCNKIVariants() {
        let seed = MetadataResolutionSeed(
            fileName: "洱海营养状态时空变化趋势及成因分析",
            title: "洱海营养状态时空变化趋势及成因分析",
            firstAuthor: "华必晖",
            year: 2024,
            journal: "湖泊科学",
            languageHint: .chinese
        )

        let candidate = MetadataResolution.buildCNKICandidate(
            title: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
            metaText: "华必晖，李锐，杨智，文紫豪，单航 | 湖泊科学 | 2024",
            snippet: nil,
            detailURL: "https://kns.cnki.net/detail/test-variant",
            seed: seed
        )

        XCTAssertNotNil(candidate)
        XCTAssertGreaterThanOrEqual(candidate?.score ?? 0, MetadataResolution.cnkiCandidateThreshold)
        XCTAssertEqual(candidate?.authors.first?.family, "华必晖")
    }

    func testCNKICandidateAuthorExtractionIgnoresCNKINoiseTokens() {
        let seed = MetadataResolutionSeed(
            fileName: "云南九大高原湖泊水质变化趋势及成因分析",
            title: "云南九大高原湖泊水质变化趋势及成因分析",
            firstAuthor: "杨进腊",
            year: 2025,
            journal: "环境科学研究",
            languageHint: .chinese
        )

        let candidate = MetadataResolution.buildCNKICandidate(
            title: "云南九大高原湖泊水质变化趋势及成因分析",
            metaText: "杨进腊, 温雯雯, 胡潇芮, 黄林培, 陈丽 | 环境科学研究 | 2025 | 下载 | 期刊",
            snippet: nil,
            detailURL: "https://kns.cnki.net/detail/test-authors",
            seed: seed
        )

        XCTAssertNotNil(candidate)
        XCTAssertEqual(
            candidate?.authors.map(\.family),
            ["杨进腊", "温雯雯", "胡潇芮", "黄林培", "陈丽"]
        )
    }

    func testParseVolumeIssuePagesHandlesChinesePatterns() {
        let parsed = MetadataResolution.parseVolumeIssuePages(from: "湖泊科学 2023年第35卷第3期 页码: 120-128")

        XCTAssertEqual(parsed.volume, "35")
        XCTAssertEqual(parsed.issue, "3")
        XCTAssertEqual(parsed.pages, "120-128")
    }

    func testNormalizeJournalNameTrimsTrailingPunctuation() {
        XCTAssertEqual(MetadataResolution.normalizeJournalName("湖泊科学 ."), "湖泊科学")
    }

    func testSuspiciousExtractedTitleRejectsGatewayTitles() {
        XCTAssertTrue(MetadataResolution.isSuspiciousExtractedTitle("自动登录"))
        XCTAssertTrue(MetadataResolution.isSuspiciousExtractedTitle("机构用户登录"))
        XCTAssertTrue(MetadataResolution.isSuspiciousExtractedTitle("卢慧斌 陈光杰 蔡燕凤 王教元 陈小林"))
        XCTAssertFalse(MetadataResolution.isSuspiciousExtractedTitle("多目标驱动的太湖调度水位研究"))
    }

    func testChineseSeedRejectsDirtyDOIResult() {
        let seed = MetadataResolutionSeed(
            fileName: "多目标驱动的太湖调度水位研究_吴浩云",
            title: "多目标驱动的太湖调度水位研究",
            firstAuthor: "吴浩云",
            year: 2023,
            doi: "10.18307/2023.0320",
            languageHint: .chinese
        )
        let dirtyDOI = Reference(
            title: "Multi-objective driven study on dispatching water level of Taihu Lake",
            authors: [AuthorName(given: "", family: "State Key Laboratory of Water Resources Engineering")],
            year: 2023,
            journal: "Journal of Lake Sciences",
            doi: "10.18307/2023.0320"
        )

        XCTAssertFalse(MetadataResolution.shouldAcceptDOIReference(dirtyDOI, seed: seed))
    }

    func testImportedChinesePDFPrefersCNKIWorkflowEvenWhenDOIExists() {
        let seed = MetadataResolutionSeed(
            fileName: "多目标驱动的太湖调度水位研究_吴浩云",
            title: "多目标驱动的太湖调度水位研究",
            firstAuthor: "吴浩云",
            year: 2023,
            doi: "10.18307/2023.0320",
            languageHint: .chinese
        )

        XCTAssertTrue(MetadataResolution.shouldPreferCNKIForImportedPDF(seed: seed))
    }

    func testImportedNonChinesePDFWithDOIDoesNotForceCNKIWorkflow() {
        let seed = MetadataResolutionSeed(
            fileName: "interesting-paper-smith",
            title: "Interesting Paper",
            firstAuthor: "Smith",
            year: 2024,
            doi: "10.1000/example",
            languageHint: .nonChinese
        )

        XCTAssertFalse(MetadataResolution.shouldPreferCNKIForImportedPDF(seed: seed))
    }

    func testReferenceSeedFallsBackToPDFFileName() {
        let reference = Reference(
            title: "CNKI",
            authors: [],
            year: 2023,
            journal: "湖泊科学",
            pdfPath: "/tmp/多目标驱动的太湖调度水位研究_吴浩云.pdf"
        )

        let seed = MetadataResolutionSeed.fromReference(reference)

        XCTAssertEqual(seed.title, "多目标驱动的太湖调度水位研究")
        XCTAssertEqual(seed.firstAuthor, "吴浩云")
        XCTAssertEqual(seed.languageHint, .chinese)
    }

    func testPreferredAutomaticCNKICandidateRequiresClearLead() {
        let strong = MetadataCandidate(
            source: .cnki,
            title: "多目标驱动的太湖调度水位研究",
            detailURL: "https://kns.cnki.net/detail/strong",
            score: 0.86
        )
        let weak = MetadataCandidate(
            source: .cnki,
            title: "太湖水位调度研究综述",
            detailURL: "https://kns.cnki.net/detail/weak",
            score: 0.70
        )
        let ambiguous = MetadataCandidate(
            source: .cnki,
            title: "多目标驱动的太湖调度水位研究",
            detailURL: "https://kns.cnki.net/detail/ambiguous",
            score: 0.83
        )

        XCTAssertEqual(
            MetadataResolution.preferredAutomaticCNKICandidate(from: [strong, weak])?.detailURL,
            strong.detailURL
        )
        XCTAssertNil(MetadataResolution.preferredAutomaticCNKICandidate(from: [strong, ambiguous]))
    }

    func testMergeRefreshedReferencePreservesLocalFields() {
        let existing = Reference(
            id: 42,
            title: "旧标题",
            authors: [AuthorName(given: "", family: "吴浩云")],
            year: 2022,
            journal: "旧期刊",
            doi: nil,
            url: "https://example.com/original",
            abstract: "旧摘要",
            pdfPath: "/tmp/sample.pdf",
            notes: "我的笔记",
            webContent: "<article>cached</article>",
            siteName: "自定义站点",
            favicon: "icon.png",
            referenceType: .journalArticle,
            collectionId: 7
        )
        let refreshed = Reference(
            title: "新标题",
            authors: [AuthorName(given: "", family: "吴浩云")],
            year: 2023,
            journal: "湖泊科学",
            doi: "10.18307/2023.0320",
            url: "https://kns.cnki.net/detail/test",
            abstract: "新摘要",
            referenceType: .journalArticle
        )

        let merged = MetadataResolution.mergeRefreshedReference(primary: refreshed, existing: existing)

        XCTAssertEqual(merged.id, 42)
        XCTAssertEqual(merged.collectionId, 7)
        XCTAssertEqual(merged.pdfPath, "/tmp/sample.pdf")
        XCTAssertEqual(merged.notes, "我的笔记")
        XCTAssertEqual(merged.webContent, "<article>cached</article>")
        XCTAssertEqual(merged.title, "新标题")
        XCTAssertEqual(merged.journal, "湖泊科学")
        XCTAssertEqual(merged.doi, "10.18307/2023.0320")
        XCTAssertTrue(MetadataResolution.hasMeaningfulRefreshChanges(original: existing, refreshed: merged))
    }
}
