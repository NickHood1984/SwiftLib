import XCTest
import WebKit
@testable import SwiftLib

@MainActor
final class SiteAdapterConfigTests: XCTestCase {
    private struct AdapterPayload: Decodable {
        struct SourceFlags: Decodable {
            var siteAdapter: Bool?
            var adapterId: String?
            var highwire: Bool?
        }

        var title: String?
        var authors: [String]?
        var doi: String?
        var journal: String?
        var volume: String?
        var issue: String?
        var pages: String?
        var date: String?
        var abstract: String?
        var keywords: [String]?
        var url: String?
        var itemType: String?
        var language: String?
        var _sources: SourceFlags?
    }

    func testHighwireAdapterDeduplicatesRepeatedAuthorSequenceAndKeepsCitationFields() async throws {
        let payload = try await evaluateAdapter(
            id: "highwire-journal-page",
            html: """
            <html>
              <head>
                <meta name="citation_title" content="洱海流域水环境变化及调控对策">
                <meta name="citation_author" content="陈小锋">
                <meta name="citation_author" content="揣小明">
                <meta name="citation_author" content="杨柳燕">
                <meta name="citation_author" content="陈小锋">
                <meta name="citation_author" content="揣小明">
                <meta name="citation_author" content="杨柳燕">
                <meta name="citation_journal_title" content="生态环境学报">
                <meta name="citation_volume" content="23">
                <meta name="citation_issue" content="3">
                <meta name="citation_firstpage" content="438">
                <meta name="citation_lastpage" content="443">
                <meta name="citation_publication_date" content="2014-03-18">
                <meta name="citation_doi" content="10.16258/j.cnki.1674-5906.2014.03.012">
                <meta name="citation_abstract" content="以洱海流域为对象分析水环境变化。">
                <meta name="citation_keywords" content="洱海, 水环境">
              </head>
              <body><h1>洱海流域水环境变化及调控对策</h1></body>
            </html>
            """,
            baseURL: URL(string: "https://www.ere.ac.cn/cn/article/id/10723")!
        )

        XCTAssertEqual(payload._sources?.adapterId, "highwire-journal-page")
        XCTAssertEqual(payload._sources?.siteAdapter, true)
        XCTAssertEqual(payload._sources?.highwire, true)
        XCTAssertEqual(payload.title, "洱海流域水环境变化及调控对策")
        XCTAssertEqual(payload.authors, ["陈小锋", "揣小明", "杨柳燕"])
        XCTAssertEqual(payload.journal, "生态环境学报")
        XCTAssertEqual(payload.volume, "23")
        XCTAssertEqual(payload.issue, "3")
        XCTAssertEqual(payload.pages, "438-443")
        XCTAssertEqual(payload.date, "2014-03-18")
        XCTAssertEqual(payload.doi, "10.16258/j.cnki.1674-5906.2014.03.012")
        XCTAssertEqual(payload.itemType, "journalArticle")
        XCTAssertEqual(payload.language, "zh")
    }

    func testCQVIPAdapterParsesVisibleChineseJournalLineWithoutChangingAuthorOrder() async throws {
        let payload = try await evaluateAdapter(
            id: "cqvip-article-detail",
            html: """
            <html>
              <body>
                <nav>
                  <a href="/Qikan/Search/Advance?from=Qikan_Article_Detail">高级检索</a>
                  <a href="/Qikan/Journal/JournalGuid?from=Qikan_Article_Detail">期刊导航</a>
                </nav>
                <h1 class="detail-title">洱海流域近50年气候变化特征及其对洱海水资源的影响</h1>
                <div>
                  <a href="/Qikan/Search/Index?key=A%3d%E9%BB%84%E6%85%A7%E5%90%9B">黄慧君</a>
                  <a href="/Qikan/Search/Index?key=A%3d%E7%8E%8B%E6%B0%B8%E5%B9%B3">王永平</a>
                  <a href="/Qikan/Search/Index?key=A%3d%E6%9D%8E%E5%BA%86%E7%BA%A2">李庆红</a>
                </div>
                <a href="/Qikan/Search/Index?key=S%3d%E4%BA%91%E5%8D%97%E7%9C%81%E5%A4%A7%E7%90%86%E5%B7%9E%E6%B0%94%E8%B1%A1%E5%B1%80">云南省大理州气象局</a>
                <a href="https://qikan.cqvip.com/Qikan/Journal/Summary?gch=95678X">气象</a>
                <p>《气象》 2013年第4期436-442,共7页</p>
                <section class="abstract">摘要：分析洱海流域近50年气候变化及水资源响应。</section>
                <section class="subject">
                  关键词：
                  <a href="/Qikan/Search/Index?key=K%3d%E6%B4%B1%E6%B5%B7%E6%B5%81%E5%9F%9F">洱海流域</a>
                  <a href="/Qikan/Search/Index?key=K%3d%E6%B0%94%E5%80%99%E5%8F%98%E5%8C%96">气候变化</a>
                  <a href="/Qikan/Search/Index?key=K%3d%E6%B0%B4%E8%B5%84%E6%BA%90">水资源</a>
                </section>
                <section class="class">
                  分类号：
                  <a href="/Qikan/Search/Index?key=C%3dP467">P467 [天文地球—大气科学及气象学]</a>
                  <a href="/Qikan/Search/Index?key=C%3dP333">P333 [天文地球—水文科学]</a>
                </section>
                <p>DOI：10.7519/j.issn.1000-0526.2013.04.005</p>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://qikan.cqvip.com/Qikan/Article/Detail?id=45515717")!
        )

        XCTAssertEqual(payload._sources?.adapterId, "cqvip-article-detail")
        XCTAssertEqual(payload.title, "洱海流域近50年气候变化特征及其对洱海水资源的影响")
        XCTAssertEqual(payload.authors, ["黄慧君", "王永平", "李庆红"])
        XCTAssertEqual(payload.journal, "气象")
        XCTAssertEqual(payload.date, "2013")
        XCTAssertEqual(payload.issue, "4")
        XCTAssertEqual(payload.pages, "436-442")
        XCTAssertEqual(payload.doi, "10.7519/j.issn.1000-0526.2013.04.005")
        XCTAssertEqual(payload.itemType, "journalArticle")
        XCTAssertEqual(payload.language, "zh")
    }

    func testWanfangAdapterParsesChineseDetailPageIntoCitationFields() async throws {
        let payload = try await evaluateAdapter(
            id: "wanfang-periodical-detail",
            html: """
            <html>
              <head>
                <meta name="citation_title" content="高原山地湖泊地区雨季地表水补给来源的空间格局及形成机制">
              </head>
              <body>
                <h1>高原山地湖泊地区雨季地表水补给来源的空间格局及形成机制</h1>
                <div class="authors">
                  <a href="/search/author?au=%E5%BB%96%E4%BC%9A">廖会</a>
                  <a href="/search/author?au=%E6%9F%B4%E5%A8%9F">柴娟</a>
                  <a href="/search/author?au=%E8%A7%92%E5%8B%87">角勇</a>
                  <a href="/search/author?au=%E6%A2%85%E5%AA%9B">梅媛</a>
                </div>
                <a href="/periodical/dlxb">地理学报</a>
                <p>《地理学报》 2024年第5期100-108,共9页</p>
                <div class="abstract">摘要：揭示高原山地湖泊地区雨季地表水补给来源空间格局。</div>
                <p>关键词：高原山地 湖泊 雨季 地表水</p>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://www.wanfangdata.com.cn/wf/detail/periodical?id=dlxb-example")!
        )

        XCTAssertEqual(payload._sources?.adapterId, "wanfang-periodical-detail")
        XCTAssertEqual(payload.title, "高原山地湖泊地区雨季地表水补给来源的空间格局及形成机制")
        XCTAssertEqual(payload.authors, ["廖会", "柴娟", "角勇", "梅媛"])
        XCTAssertEqual(payload.journal, "地理学报")
        XCTAssertEqual(payload.date, "2024")
        XCTAssertEqual(payload.issue, "5")
        XCTAssertEqual(payload.pages, "100-108")
        XCTAssertEqual(payload.itemType, "journalArticle")
        XCTAssertEqual(payload.language, "zh")
    }

    private func evaluateAdapter(id: String, html: String, baseURL: URL) async throws -> AdapterPayload {
        let config = try loadBundledSiteAdapterConfig()
        let adapter = try XCTUnwrap(config.adapters.first { $0.id == id }, "Missing site adapter \(id)")
        let script = try XCTUnwrap(SiteAdapterService.shared.buildScript(for: adapter))

        let webView = WKWebView(frame: .zero)
        let loader = HTMLLoadDelegate()
        webView.navigationDelegate = loader
        try await loader.load(html: html, in: webView, baseURL: baseURL)

        let raw = try await webView.evaluateJavaScript(script) as? String
        let data = try XCTUnwrap(raw?.data(using: .utf8))
        return try JSONDecoder().decode(AdapterPayload.self, from: data)
    }

    private func loadBundledSiteAdapterConfig() throws -> SiteAdapterConfig {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftLib/Resources/site-adapters.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SiteAdapterConfig.self, from: data)
    }
}
