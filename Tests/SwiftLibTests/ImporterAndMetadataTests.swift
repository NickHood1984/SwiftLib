import Foundation
import XCTest
import WebKit
@testable import SwiftLib
@testable import SwiftLibCore

final class ImporterAndMetadataTests: XCTestCase {
    private struct VIPSearchScriptPayload: Decodable {
        struct Result: Decodable {
            var title: String
            var url: String?
            var authors: [String]
            var journal: String?
            var year: Int?
            var issue: String?
            var pages: String?
            var abstract: String
            var sourceRecordID: String?
        }

        var results: [Result]
    }

    func testBibTeXParseMapsEntryTypesAndPreservesNestedBraceContent() throws {
        let bibtex = """
        @article{smith2024,
          title = {Understanding {Swift} Testing},
          author = {Smith, John and Doe, Jane},
          year = {2024},
          journal = {Journal of Tests},
          volume = {12},
          number = {3},
          pages = {10--20},
          doi = {10.1000/test},
          url = {https://example.com/article},
          abstract = {A careful study.}
        }

        @inproceedings{lee2023,
          title = "Conference Paper",
          author = "Lee, Pat",
          year = "2023",
          booktitle = "Proceedings of SwiftConf"
        }
        """

        let references = BibTeXImporter.parse(bibtex)

        XCTAssertEqual(references.count, 2)

        let article = try XCTUnwrap(references.first)
        XCTAssertEqual(article.title, "Understanding {Swift} Testing")
        XCTAssertEqual(article.authors, [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe"),
        ])
        XCTAssertEqual(article.year, 2024)
        XCTAssertEqual(article.journal, "Journal of Tests")
        XCTAssertEqual(article.volume, "12")
        XCTAssertEqual(article.issue, "3")
        XCTAssertEqual(article.pages, "10--20")
        XCTAssertEqual(article.doi, "10.1000/test")
        XCTAssertEqual(article.url, "https://example.com/article")
        XCTAssertEqual(article.abstract, "A careful study.")
        XCTAssertEqual(article.referenceType, .journalArticle)

        let conference = references[1]
        XCTAssertEqual(conference.title, "Conference Paper")
        XCTAssertEqual(conference.authors, [AuthorName(given: "Pat", family: "Lee")])
        XCTAssertEqual(conference.journal, "Proceedings of SwiftConf")
        XCTAssertEqual(conference.referenceType, .conferencePaper)
    }

    func testRISParseBuildsReferencesIncludingTrailingEntryWithoutER() {
        let ris = """
        TY  - JOUR
        TI  - RIS Article
        AU  - Smith, John
        AU  - Doe, Jane
        PY  - 2022/05/01
        JO  - Parsing Today
        VL  - 8
        IS  - 2
        SP  - 15
        EP  - 30
        DO  - 10.1000/ris
        ER  -
        TY  - CHAP
        T1  - Final Chapter
        A1  - Lee, Pat
        Y1  - 2021
        T2  - Great Book
        """

        let references = RISImporter.parse(ris)

        XCTAssertEqual(references.count, 2)

        let article = references[0]
        XCTAssertEqual(article.title, "RIS Article")
        XCTAssertEqual(article.authors, [
            AuthorName(given: "John", family: "Smith"),
            AuthorName(given: "Jane", family: "Doe"),
        ])
        XCTAssertEqual(article.year, 2022)
        XCTAssertEqual(article.journal, "Parsing Today")
        XCTAssertEqual(article.volume, "8")
        XCTAssertEqual(article.issue, "2")
        XCTAssertEqual(article.pages, "15-30")
        XCTAssertEqual(article.doi, "10.1000/ris")
        XCTAssertEqual(article.referenceType, .journalArticle)

        let chapter = references[1]
        XCTAssertEqual(chapter.title, "Final Chapter")
        XCTAssertEqual(chapter.authors, [AuthorName(given: "Pat", family: "Lee")])
        XCTAssertEqual(chapter.year, 2021)
        XCTAssertEqual(chapter.journal, "Great Book")
        XCTAssertEqual(chapter.referenceType, .bookSection)
    }

    func testMetadataFetcherExtractIdentifierPrioritizesSupportedFormats() {
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "https://doi.org/10.1000/xyz.123."),
            matches: .doi("10.1000/xyz.123")
        )
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "9780306406157"),
            matches: .isbn("9780306406157")
        )
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "arXiv:2301.07041v2"),
            matches: .arxiv("2301.07041")
        )
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "12345678"),
            matches: .pmid("12345678")
        )
        XCTAssertNil(MetadataFetcher.extractIdentifier(from: "not an identifier"))
    }

    func testMetadataFetcherPrefersDOIOverOtherNumericPatterns() {
        assertIdentifier(
            MetadataFetcher.extractIdentifier(from: "doi:10.1000/123456789X"),
            matches: .doi("10.1000/123456789X")
        )
    }

    func testCNKIDetailResolutionRejectsGatewayTitles() {
        XCTAssertNil(CNKIMetadataProvider.resolveTitle(extractedTitle: "自动登录"))
        XCTAssertNil(CNKIMetadataProvider.resolveTitle(extractedTitle: "卢慧斌 陈光杰 蔡燕凤 王教元 陈小林"))
        XCTAssertEqual(
            CNKIMetadataProvider.resolveTitle(extractedTitle: "多目标驱动的太湖调度水位研究"),
            "多目标驱动的太湖调度水位研究"
        )
    }

    func testCNKIDetailResolutionFallsBackToCandidateTitleWhenDetailTitleIsGatewayText() {
        XCTAssertEqual(
            CNKIMetadataProvider.resolvedDetailTitle(
                extractedTitle: "自动登录",
                fallbackCandidateTitle: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析"
            ),
            "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析"
        )
    }

    func testCNKIDetailResolutionFallsBackToCandidateTitleWhenDetailTitleLooksLikeAuthors() {
        XCTAssertEqual(
            CNKIMetadataProvider.resolvedDetailTitle(
                extractedTitle: "卢慧斌 陈光杰 蔡燕凤 王教元 陈小林 段立曾 张虎才",
                fallbackCandidateTitle: "近百年来洱海水生生态环境演化及其驱动机制"
            ),
            "近百年来洱海水生生态环境演化及其驱动机制"
        )
    }

    func testCNKIDetailResolutionUsesOnlyExtractedAuthors() {
        XCTAssertTrue(CNKIMetadataProvider.resolveAuthors(extractedAuthors: []).isEmpty)
        XCTAssertEqual(
            CNKIMetadataProvider.resolveAuthors(extractedAuthors: ["吴浩云", "刘敏", "金科"]),
            [
                AuthorName(given: "", family: "吴浩云"),
                AuthorName(given: "", family: "刘敏"),
                AuthorName(given: "", family: "金科"),
            ]
        )
    }

    func testCNKIDetailResolutionDropsShellNoiseAuthors() {
        XCTAssertEqual(
            CNKIMetadataProvider.resolveAuthors(
                extractedAuthors: ["李锐", "杨智", "印刷版", "有限公司", "编辑部", "华兆晖"]
            ),
            [
                AuthorName(given: "", family: "李锐"),
                AuthorName(given: "", family: "杨智"),
                AuthorName(given: "", family: "华兆晖"),
            ]
        )
    }

    func testCNKIDetailResolutionFallsBackToCandidateAuthorsWhenDetailAuthorsMissing() {
        let fallbackAuthors = [
            AuthorName(given: "", family: "华兆晖"),
            AuthorName(given: "", family: "李钰"),
        ]

        XCTAssertEqual(
            CNKIMetadataProvider.resolvedDetailAuthors(
                extractedAuthors: [],
                fallbackAuthors: fallbackAuthors
            ),
            fallbackAuthors
        )
    }

    func testCNKIDetailVerificationAuthorsDoNotUseCandidateFallback() {
        XCTAssertTrue(
            CNKIMetadataProvider.verificationDetailAuthors(extractedAuthors: []).isEmpty
        )
    }

    func testCNKISearchExpressionsSanitizeBrokenAuthorAndRetryTitleOnly() {
        let seed = MetadataResolutionSeed(
            fileName: "热带亚热带水库浮游动物群落结构与水质的关系",
            title: "热带亚热带水库浮游动物群落结构与水质的关系",
            firstAuthor: "林秋奇 韩博平",
            year: 2003,
            journal: "生态学报",
            languageHint: .chinese,
            workKindHint: .journalArticle
        )

        XCTAssertEqual(
            CNKIMetadataProvider.searchExpressions(for: seed),
            [
                "(TI %= '热带亚热带水库浮游动物群落结构与水质的关系') AND AU='林秋奇'",
                "TI %= '热带亚热带水库浮游动物群落结构与水质的关系'",
            ]
        )
    }

    func testCNKISearchExpressionsDropObviousNonAuthorTokens() {
        let seed = MetadataResolutionSeed(
            fileName: "热带亚热带水库浮游动物群落结构与水质的关系",
            title: "热带亚热带水库浮游动物群落结构与水质的关系",
            firstAuthor: "编辑部",
            year: 2003,
            journal: "生态学报",
            languageHint: .chinese,
            workKindHint: .journalArticle
        )

        XCTAssertEqual(
            CNKIMetadataProvider.searchExpressions(for: seed),
            ["TI %= '热带亚热带水库浮游动物群落结构与水质的关系'"]
        )
    }

    func testNormalizeCNKIExportAuthors() {
        // 知网紧凑格式：前几位作者空格拼接，"等"作为 et al.，最后是通讯作者
        XCTAssertEqual(
            CNKIMetadataProvider.normalizeCNKIExportAuthors("匡晨亿 王森洋, 等 梁智策"),
            "匡晨亿;王森洋;梁智策"
        )
        // 只有两位作者，无"等"
        XCTAssertEqual(
            CNKIMetadataProvider.normalizeCNKIExportAuthors("吴浩云 刘敏"),
            "吴浩云;刘敏"
        )
        // 已经是分号分隔
        XCTAssertEqual(
            CNKIMetadataProvider.normalizeCNKIExportAuthors("吴浩云；刘敏；金科"),
            "吴浩云;刘敏;金科"
        )
        // 已经是逗号分隔（无空格拼接的汉字）
        XCTAssertEqual(
            CNKIMetadataProvider.normalizeCNKIExportAuthors("Smith, John"),
            "Smith, John"
        )
        // 单独一位
        XCTAssertEqual(
            CNKIMetadataProvider.normalizeCNKIExportAuthors("梁智策"),
            "梁智策"
        )
    }

    func testNormalizeCNKIExportAuthorsResultsInCorrectAuthorNames() {
        let authors = AuthorName.parseList(
            CNKIMetadataProvider.normalizeCNKIExportAuthors("匡晨亿 王森洋, 等 梁智策")
        )
        XCTAssertEqual(authors.count, 3)
        XCTAssertEqual(authors[0], AuthorName(given: "", family: "匡晨亿"))
        XCTAssertEqual(authors[1], AuthorName(given: "", family: "王森洋"))
        XCTAssertEqual(authors[2], AuthorName(given: "", family: "梁智策"))
        XCTAssertEqual(authors.displayString, "匡晨亿, 王森洋, 梁智策")
    }

    func testCNKIDetailResolutionAcceptsStructuredDetailWithoutAuthors() {
        XCTAssertTrue(
            CNKIMetadataProvider.shouldAcceptResolvedDetail(
                resolvedTitle: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
                resolvedAuthors: [],
                journal: "湖泊科学",
                doi: nil,
                yearText: "2024 36(06)",
                pages: "100-112",
                institution: nil,
                thesisType: nil
            )
        )
    }

    @MainActor
    func testCNKIDetailReferenceFillsVolumeIssuePagesFromVisiblePublicationLine() {
        let provider = CNKIMetadataProvider()
        let candidate = MetadataCandidate(
            source: .cnki,
            title: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
            authors: [
                AuthorName(given: "", family: "华兆晖"),
                AuthorName(given: "", family: "李锐"),
            ],
            journal: "湖泊科学",
            year: 2024,
            detailURL: "https://kns.cnki.net/kcms2/article/abstract?v=sample",
            score: 1,
            workKind: .journalArticle,
            cnkiExport: CNKIExportLocator(dbname: "CJFQ", filename: "FLKX202406003")
        )
        let payload = CNKIMetadataProvider.DetailPayload(
            blocked: false,
            blockedReason: nil,
            title: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
            authors: ["华兆晖", "李锐", "杨智"],
            authorSource: "titleRegion",
            journal: "湖泊科学 .",
            doi: nil,
            abstract: "洱海是我国重要高原湖泊，水体营养状态长期变化具有显著生态意义。",
            volume: nil,
            issue: nil,
            firstPage: nil,
            lastPage: nil,
            yearText: nil,
            bodyText: """
            湖泊科学 . 2024 ,36 (06) : 1639-1650 查看该刊数据库收录来源
            2017—2022年洱海水体营养状态的时空变化趋势及其成因分析
            华兆晖 李锐 杨智
            """,
            url: candidate.detailURL
        )

        let record = provider.reference(
            from: payload,
            fallbackCandidate: candidate,
            resolvedTitle: candidate.title,
            resolvedAuthors: CNKIMetadataProvider.resolveAuthors(extractedAuthors: payload.authors),
            displayAuthors: CNKIMetadataProvider.resolveAuthors(extractedAuthors: payload.authors)
        )

        XCTAssertEqual(record.reference.volume, "36")
        XCTAssertEqual(record.reference.issue, "06")
        XCTAssertEqual(record.reference.pages, "1639-1650")
        XCTAssertTrue(record.evidence.verificationHints.hasStructuredPages)
    }

    @MainActor
    func testWanfangSearchScriptSplitsUnseparatedChineseAuthorRuns() async throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftLib/Resources/wanfang-search.js")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let html = """
        <html>
          <head><title>万方搜索</title></head>
          <body>
            <section>
              1. 高原山地—湖泊地区雨季地表水补给来源的空间格局及形成机制 [期刊论文]
              廖会柴娟角勇梅媛 - 《地理学报》 2024年
              摘要: 高原山地湖泊地区雨季地表水补给来源具有空间差异。关键词: 地表水 补给来源
              <a href="https://www.wanfangdata.com.cn/wf/detail/periodical?id=dlxb-example">详情</a>
            </section>
            <section>
              2. 基于EFDC模型的洱海水温模拟 [期刊论文]
              张锦吴鹏田越 - 《环境工程技术学报》 2020年
              摘要: 基于EFDC模型模拟洱海水温时空变化。关键词: EFDC 洱海 水温
              <a href="https://www.wanfangdata.com.cn/wf/detail/periodical?id=hjjsgc-example">详情</a>
            </section>
            <section>
              3. 洞庭湖春秋季浮游植物群落结构及其与环境因子的关系 [期刊论文]
              王昊潘保柱赵耿楠 - 《长江流域资源与环境》 2021年
              摘要: 洞庭湖春秋季浮游植物群落结构与环境因子存在显著关系。关键词: 洞庭湖 浮游植物 环境因子
              <a href="https://www.wanfangdata.com.cn/wf/detail/periodical?id=cjlyzyyhj-example">详情</a>
            </section>
          </body>
        </html>
        """

        let webView = WKWebView(frame: .zero)
        let loader = HTMLLoadDelegate()
        webView.navigationDelegate = loader
        try await loader.load(
            html: html,
            in: webView,
            baseURL: URL(string: "https://s.wanfangdata.com.cn/paper")!
        )

        let raw = try await webView.evaluateJavaScript(script) as? String
        let data = try XCTUnwrap(raw?.data(using: .utf8))
        let payload = try JSONDecoder().decode(VIPSearchScriptPayload.self, from: data)
        let plateau = try XCTUnwrap(payload.results.first { $0.title.contains("高原山地") })
        let erhai = try XCTUnwrap(payload.results.first { $0.title.contains("EFDC") })
        let dongting = try XCTUnwrap(payload.results.first { $0.title.contains("洞庭湖") })

        XCTAssertEqual(plateau.authors.prefix(4), ["廖会", "柴娟", "角勇", "梅媛"])
        XCTAssertEqual(erhai.authors.prefix(3), ["张锦", "吴鹏", "田越"])
        XCTAssertEqual(dongting.authors.prefix(3), ["王昊", "潘保柱", "赵耿楠"])
    }

    @MainActor
    func testVIPSearchScriptIgnoresYearRangeInTitleWhenParsingPublicationYear() async throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftLib/Resources/vip-search.js")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let html = """
        <html>
          <body>
            <dl>
              <dt>
                <a href="/Qikan/Article/Detail?id=HS725032017004002&amp;from=Qikan_Search_Index">
                  <u>2015~</u><u>2016</u><u>年</u><u>洱海</u><u>水质</u><u>参数</u><u>季节性</u><u>变化</u>
                </a>
              </dt>
              <dd>
                <span class="author">
                  <span class="label">作者</span>
                  <span><a href="/Qikan/Search/Index?key=A%3d%e6%9c%b1%e6%a2%a6%e5%a7%9d"><span>朱梦姝</span></a></span>
                  <span><a href="/Qikan/Search/Index?key=A%3d%e5%bc%a0%e8%99%8e%e6%89%8d"><span>张虎才</span></a></span>
                  <span style="display:none"><a href="/Qikan/Search/Index?key=A%3d%e5%b8%b8%e5%87%a4%e7%90%b4"><span>常凤琴</span></a></span>
                </span>
                <a href="/Qikan/Journal/Summary?gch=72503X">《环境保护前沿》</a>
                2017年第4期297-308,共12页
              </dd>
              <dd>
                <span class="abstract">
                  <span>随着洱海流域建设和生产、生活规模的快速扩展,对洱海水质的影响也日益增强。为了解和认识其水质现状和变化过程,我们对洱海进行了定位水质监测。</span>
                  <span style="display:none;">随着洱海流域建设和生产、生活规模的快速扩展,对洱海水质的影响也日益增强。为了解和认识其水质现状和变化过程,我们对洱海进行了定位水质监测。洱海不同湖区水体的温度、叶绿素-a、溶解氧、pH以及浊度的季节性变化特征显著,并存在明显的空间异质性。 展开更多</span>
                </span>
              </dd>
              <dd>
                <span class="subject"><span class="label">关键词</span> 洱海 水质参数 气温 风浪扰动 空间异质性</span>
              </dd>
            </dl>
          </body>
        </html>
        """

        let webView = WKWebView(frame: .zero)
        let loader = HTMLLoadDelegate()
        webView.navigationDelegate = loader
        try await loader.load(
            html: html,
            in: webView,
            baseURL: URL(string: "https://qikan.cqvip.com/Qikan/Search/Index")!
        )

        let raw = try await webView.evaluateJavaScript(script) as? String
        let data = try XCTUnwrap(raw?.data(using: .utf8))
        let payload = try JSONDecoder().decode(VIPSearchScriptPayload.self, from: data)
        let result = try XCTUnwrap(payload.results.first)

        XCTAssertEqual(result.title, "2015~2016年洱海水质参数季节性变化")
        XCTAssertEqual(result.year, 2017)
        XCTAssertEqual(result.issue, "4")
        XCTAssertEqual(result.pages, "297-308")
        XCTAssertEqual(result.journal, "环境保护前沿")
        XCTAssertEqual(result.sourceRecordID, "HS725032017004002")
        XCTAssertEqual(result.authors.prefix(3), ["朱梦姝", "张虎才", "常凤琴"])
        XCTAssertFalse(result.abstract.contains("关键词"))
    }

    @MainActor
    func testCNKISelectorConfigLoadsBundledSelectorsIntoScripts() {
        let config = CNKISelectorService.shared.config

        XCTAssertGreaterThanOrEqual(config.version, 1)
        XCTAssertEqual(config.groups["detailTitle"]?.contains(".wx-tit > h1"), true)
        XCTAssertEqual(config.groups["searchRows"]?.contains("tr[data-dbcode]"), true)
        XCTAssertFalse(CNKIMetadataProvider.detailExtractionScript.contains("%%CNKI_SELECTORS%%"))
        XCTAssertTrue(CNKIMetadataProvider.detailExtractionScript.contains("\"detailTitle\""))
        XCTAssertTrue(CNKIMetadataProvider.searchExtractionScript.contains("\"searchRows\""))
    }

    func testCNKIDetailResolutionRejectsBodyTextOnlyFallback() {
        XCTAssertFalse(
            CNKIMetadataProvider.shouldAcceptResolvedDetail(
                resolvedTitle: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
                resolvedAuthors: [],
                journal: "湖泊科学",
                doi: nil,
                yearText: "2024 36(06)",
                pages: nil,
                institution: nil,
                thesisType: nil
            )
        )
    }

    func testCNKIPageResolutionPrefersResolvedDetailOverBlockedMarker() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: true,
            searchRowCount: 0,
            hasDetailTitle: true,
            hasDetailAuthors: true,
            hasDetailSummary: true
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .resolvedDetail
        )
    }

    func testCNKIPageResolutionPrefersResolvedSearchOverBlockedMarker() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: true,
            searchRowCount: 3,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .resolvedSearch
        )
    }

    func testCNKIPageResolutionReportsBlockedWhenNoUsableContentExists() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: true,
            searchRowCount: 0,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .blocked
        )
    }

    func testCNKIPageResolutionTreatsEmptySearchStateAsResolvedSearch() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: false,
            searchRowCount: 0,
            hasSearchEmptyState: true,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .resolvedSearch
        )
    }

    func testCNKIPageResolutionReportsLoadingWhenSignalsAreAbsent() {
        let payload = CNKIMetadataProvider.PageAssessmentPayload(
            markerBlocked: false,
            searchRowCount: 0,
            hasDetailTitle: false,
            hasDetailAuthors: false,
            hasDetailSummary: false
        )

        XCTAssertEqual(
            CNKIMetadataProvider.pageResolutionState(from: payload),
            .loadingOrUnknown
        )
    }

    private func assertIdentifier(_ actual: MetadataFetcher.Identifier?, matches expected: MetadataFetcher.Identifier) {
        switch (actual, expected) {
        case (.doi(let lhs), .doi(let rhs)):
            XCTAssertEqual(lhs, rhs)
        case (.pmid(let lhs), .pmid(let rhs)):
            XCTAssertEqual(lhs, rhs)
        case (.arxiv(let lhs), .arxiv(let rhs)):
            XCTAssertEqual(lhs, rhs)
        case (.isbn(let lhs), .isbn(let rhs)):
            XCTAssertEqual(lhs, rhs)
        default:
            XCTFail("Identifier mismatch: actual=\(String(describing: actual)) expected=\(expected)")
        }
    }
}
