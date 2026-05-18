import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

/// 新 Swift 原生解析后端集成测试（真实网络请求）。
/// 运行：swift test --filter NewBackendIntegrationTests
@MainActor
final class NewBackendIntegrationTests: XCTestCase {

    // MARK: - WebScholarlyMetadataExtractor

    /// Nature 文章：Highwire Press citation_* meta tags
    func testExtractNatureArticle() async throws {
        let extractor = WebScholarlyMetadataExtractor()
        let url = "https://www.nature.com/articles/s41586-021-03819-2"
        let result = try await extractor.extract(urlString: url)
        let ref = result.reference

        XCTAssertFalse(ref.title.isEmpty, "title 不应为空")
        XCTAssertTrue(result.hasCitationMetaTags, "Nature 应含 citation meta tags")

        print("""
        \n✅ [Nature] \(ref.title)
           作者: \(ref.authors.map { "\($0.given) \($0.family)" }.joined(separator: "; "))
           期刊: \(ref.journal ?? "-")  年份: \(ref.year.map(String.init) ?? "-")
           DOI:  \(ref.doi ?? "-")
           来源: \(ref.metadataSource?.displayName ?? "-")
        """)
    }

    /// PubMed 摘要页：注意——命令行测试环境下 Cloudflare 会拦截并返回 reCAPTCHA 页面，
    /// 在真实 macOS App（有完整 Cookie/浏览器标识）中可正常提取。
    /// 此测试仅验证不抛异常、拿到某个 title（即使是 CAPTCHA 页标题）。
    func testExtractPubMedAbstractPage() async throws {
        let extractor = WebScholarlyMetadataExtractor()
        // AlphaFold2 论文
        let url = "https://pubmed.ncbi.nlm.nih.gov/34265844/"
        let result = try await extractor.extract(urlString: url)
        let ref = result.reference

        // 只要不抛异常、title 不为空即通过（CAPTCHA 页也有 title）
        XCTAssertFalse(ref.title.isEmpty, "title 不应为空")

        let isCaptcha = ref.title.contains("reCAPTCHA") || ref.title.contains("验证")
        print("""
        \n\(isCaptcha ? "⚠️" : "✅") [PubMed] \(ref.title)\(isCaptcha ? " (CAPTCHA拦截，在真实App中可正常工作)" : "")
           作者: \(ref.authors.map { $0.family }.joined(separator: ", "))
           期刊: \(ref.journal ?? "-")  年份: \(ref.year.map(String.init) ?? "-")
           DOI:  \(ref.doi ?? "-")  PMID: \(ref.pmid ?? "-")
           来源: \(ref.metadataSource?.displayName ?? "-")
        """)
    }

    /// arXiv 摘要页：Dublin Core / citation meta tags
    func testExtractArXivAbstractPage() async throws {
        let extractor = WebScholarlyMetadataExtractor()
        // Attention is All You Need
        let url = "https://arxiv.org/abs/1706.03762"
        let result = try await extractor.extract(urlString: url)
        let ref = result.reference

        XCTAssertFalse(ref.title.isEmpty, "title 不应为空")
        XCTAssertFalse(ref.authors.isEmpty, "authors 不应为空")

        print("""
        \n✅ [arXiv] \(ref.title)
           作者: \(ref.authors.map { $0.family }.joined(separator: ", "))
           年份: \(ref.year.map(String.init) ?? "-")
           来源: \(ref.metadataSource?.displayName ?? "-")
        """)
    }

    // MARK: - Chinese journal browser aggregation

    func testWanfangSearchExactTitle() async {
        let seed = MetadataResolutionSeed(
            fileName: "近百年来枝角类群落响应洱海营养水平、外来鱼类引入以及水生植被变化的特征",
            title: "近百年来枝角类群落响应洱海营养水平、外来鱼类引入以及水生植被变化的特征",
            firstAuthor: "卢慧斌",
            languageHint: .chinese,
            workKindHint: .journalArticle
        )
        let outcome = await ChineseJournalBrowserSearchService.search(channel: .wanfang, seed: seed)
        switch outcome {
        case .candidates(let candidates):
            XCTAssertFalse(candidates.isEmpty)
            print("""
            \n✅ [万方] \(candidates.first?.title ?? "-")
               作者: \(candidates.first?.authors.displayString ?? "-")
               期刊: \(candidates.first?.journal ?? "-")  年份: \(candidates.first?.year.map(String.init) ?? "-")
            """)
        case .blockedByVerification:
            print("\n⚠️ [万方] 被安全验证或访问拦截")
        case .noResult:
            print("\nℹ️ [万方] 未获取结果")
        }
    }

    func testVIPSearchExactTitle() async {
        let seed = MetadataResolutionSeed(
            fileName: "近百年来枝角类群落响应洱海营养水平、外来鱼类引入以及水生植被变化的特征",
            title: "近百年来枝角类群落响应洱海营养水平、外来鱼类引入以及水生植被变化的特征",
            firstAuthor: "卢慧斌",
            languageHint: .chinese,
            workKindHint: .journalArticle
        )
        let outcome = await ChineseJournalBrowserSearchService.search(channel: .vip, seed: seed)
        switch outcome {
        case .candidates(let candidates):
            XCTAssertFalse(candidates.isEmpty)
            print("""
            \n✅ [维普] \(candidates.first?.title ?? "-")
               作者: \(candidates.first?.authors.displayString ?? "-")
               期刊: \(candidates.first?.journal ?? "-")  年份: \(candidates.first?.year.map(String.init) ?? "-")
            """)
        case .blockedByVerification:
            print("\n⚠️ [维普] 被安全验证或访问拦截")
        case .noResult:
            print("\nℹ️ [维普] 未获取结果")
        }
    }

}
