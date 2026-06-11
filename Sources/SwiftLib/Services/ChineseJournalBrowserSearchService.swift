import Foundation
import OSLog
import SwiftLibCore
import WebKit

private let chineseBrowserSearchLog = Logger(subsystem: "SwiftLib", category: "ChineseBrowserSearch")

enum ChineseJournalBrowserSearchService {
    enum Channel: String {
        case wanfang
        case vip

        var source: MetadataSource {
            switch self {
            case .wanfang: return .wanfang
            case .vip: return .vip
            }
        }

        var displayName: String {
            switch self {
            case .wanfang: return "万方"
            case .vip: return "维普"
            }
        }
    }

    enum SearchOutcome {
        case candidates([MetadataCandidate])
        case noResult
        case blockedByVerification
    }

    @MainActor private static let wanfangEngine = ChineseJournalBrowserSearchEngine()
    @MainActor private static let vipEngine = ChineseJournalBrowserSearchEngine()

    @MainActor
    static func search(channel: Channel, seed: MetadataResolutionSeed) async -> SearchOutcome {
        await engine(for: channel).search(channel: channel, seed: seed)
    }

    @MainActor
    private static func engine(for channel: Channel) -> ChineseJournalBrowserSearchEngine {
        switch channel {
        case .wanfang: return wanfangEngine
        case .vip: return vipEngine
        }
    }
}

@MainActor
final class ChineseJournalBrowserSearchEngine: NSObject, WKNavigationDelegate {
    private struct RawResult: Decodable {
        var title: String
        var url: String?
        var authors: [String]?
        var journal: String?
        var year: Int?
        var volume: String?
        var issue: String?
        var pages: String?
        var abstract: String?
        var sourceRecordID: String?
    }

    private struct SearchResponse: Decodable {
        var status: String
        var results: [RawResult]
        var itemCount: Int?
        var pageTitle: String?
        var message: String?
        var pageURL: String?
    }

    private struct DirectSearchResponse: Decodable {
        var status: String
        var httpStatus: Int?
        var htmlLength: Int?
        var message: String?
        var pageTitle: String?
        var pageURL: String?
    }

    private struct PendingSearch {
        var channel: ChineseJournalBrowserSearchService.Channel
        var seed: MetadataResolutionSeed
        var query: String
        var searchSubmitted = false
        var extractionScheduled = false
    }

    private var webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<SearchResponse, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingSearch: PendingSearch?

    func search(
        channel: ChineseJournalBrowserSearchService.Channel,
        seed: MetadataResolutionSeed
    ) async -> ChineseJournalBrowserSearchService.SearchOutcome {
        // Serialize overlapping searches instead of bailing out: batch refresh
        // runs up to 3 references concurrently, and returning `.noResult` here
        // silently dropped the Wanfang/VIP fallback for every caller but the
        // first — those references then failed with "未找到候选" even though
        // the channel was merely busy. Each in-flight search is bounded by the
        // 30s page-load timeout, so the wait below is bounded too.
        var waitedNanos: UInt64 = 0
        let maxWaitNanos: UInt64 = 65_000_000_000 // ~2 queued searches
        while pendingContinuation != nil, waitedNanos < maxWaitNanos {
            try? await Task.sleep(nanoseconds: 250_000_000)
            waitedNanos += 250_000_000
        }
        guard pendingContinuation == nil else { return .noResult }

        let query = Self.queryString(for: seed)
        guard !query.isEmpty else { return .noResult }

        let wv = ensureWebView()
        let response = await withCheckedContinuation { (continuation: CheckedContinuation<SearchResponse, Never>) in
            pendingContinuation = continuation
            pendingSearch = PendingSearch(channel: channel, seed: seed, query: query)
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self, weak wv] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                self?.complete(with: self?.fallbackResponse(from: wv, status: "timeout", message: "页面加载超时"))
            }

            chineseBrowserSearchLog.notice("\(channel.displayName, privacy: .public) 搜索 query=\(query, privacy: .public)")
            wv.stopLoading()
            wv.load(URLRequest(url: searchURL(channel: channel, query: query)))
        }

        if Self.isBlocked(response) {
            return .blockedByVerification
        }

        let candidates = response.results
            .map { Self.candidate(from: $0, channel: channel, seed: seed, pageURL: response.pageURL) }
            .filter { candidate in
                guard let expected = seed.title?.swiftlib_nilIfBlank else { return true }
                return MetadataResolution.titleSimilarity(expected, candidate.title) >= 0.30
            }
            .sorted { $0.score > $1.score }

        guard !candidates.isEmpty else { return .noResult }
        return .candidates(candidates)
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(config)
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 4, height: 4), configuration: config)
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func searchURL(channel: ChineseJournalBrowserSearchService.Channel, query: String) -> URL {
        switch channel {
        case .wanfang:
            var components = URLComponents(string: "https://s.wanfangdata.com.cn/paper")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            return components.url!
        case .vip:
            return URL(string: "https://qikan.cqvip.com/Qikan/Search/Index")!
        }
    }

    private func pollUntilReadyAndExtract(
        channel: ChineseJournalBrowserSearchService.Channel,
        maxAttempts: Int,
        intervalNanoseconds: UInt64 = 300_000_000
    ) {
        guard pendingContinuation != nil,
              var pending = pendingSearch,
              !pending.extractionScheduled else { return }
        pending.extractionScheduled = true
        pendingSearch = pending

        Task { @MainActor [weak self] in
            guard let self, self.pendingContinuation != nil else { return }
            for _ in 0..<maxAttempts {
                guard self.pendingContinuation != nil else { return }
                if await self.isCurrentPageReady(for: channel) {
                    break
                }
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
            await self.extractCurrentPage()
        }
    }

    private func isCurrentPageReady(for channel: ChineseJournalBrowserSearchService.Channel) async -> Bool {
        guard let webView else { return false }
        do {
            let script = Self.readinessScript(for: channel)
            return (try await webView.evaluateJavaScript(script) as? Bool) ?? false
        } catch {
            return false
        }
    }

    private func startVIPSearchIfNeeded(in webView: WKWebView) {
        guard pendingContinuation != nil,
              var pending = pendingSearch,
              pending.channel == .vip,
              !pending.searchSubmitted else {
            return
        }

        pending.searchSubmitted = true
        pendingSearch = pending

        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView, self.pendingContinuation != nil else { return }
            let runtimeReady = await self.waitForVIPRuntime(in: webView)
            if runtimeReady, await self.executeVIPDirectSearch(in: webView) {
                await self.extractCurrentPage()
                return
            }

            await self.submitVIPSearchFormFallback(in: webView)
            self.pollUntilReadyAndExtract(channel: .vip, maxAttempts: 32)
        }
    }

    private func waitForVIPRuntime(in webView: WKWebView) async -> Bool {
        for _ in 0..<12 {
            guard pendingContinuation != nil else { return false }
            do {
                let ready = try await webView.evaluateJavaScript("""
                Boolean(window.SearchParamModel && document.querySelector('#searchlist'))
                """) as? Bool
                if ready == true { return true }
            } catch {
                return false
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func executeVIPDirectSearch(in webView: WKWebView) async -> Bool {
        guard let pending = pendingSearch else { return false }
        do {
            let raw = try await webView.callAsyncJavaScript(
                Self.vipDirectSearchScript(query: pending.query),
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard let json = raw as? String,
                  let data = json.data(using: .utf8),
                  let response = try? JSONDecoder().decode(DirectSearchResponse.self, from: data) else {
                return false
            }
            chineseBrowserSearchLog.notice(
                "维普直连 SearchList status=\(response.status, privacy: .public) http=\(response.httpStatus ?? 0) bytes=\(response.htmlLength ?? 0)"
            )
            if response.status == "blocked" {
                complete(with: SearchResponse(
                    status: "blocked",
                    results: [],
                    itemCount: nil,
                    pageTitle: response.pageTitle,
                    message: response.message ?? "维普页面触发安全验证或访问拦截",
                    pageURL: response.pageURL
                ))
                return true
            }
            return response.status == "ok" && (response.httpStatus ?? 0) < 400 && (response.htmlLength ?? 0) > 0
        } catch {
            chineseBrowserSearchLog.notice("维普直连 SearchList 失败 \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func submitVIPSearchFormFallback(in webView: WKWebView) async {
        guard let pending = pendingSearch else { return }
        let queryLiteral = Self.jsonStringLiteral(pending.query)
        let script = """
        (function() {
            var query = \(queryLiteral);
            var input = document.querySelector('input[name="searchKeywords"]');
            if (!input) return JSON.stringify({ status: 'missing-input', pageTitle: document.title, pageURL: location.href });
            input.focus();
            var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            setter.call(input, query);
            input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
            input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
            var buttons = Array.prototype.slice.call(document.querySelectorAll('button'));
            var button = buttons.find(function (item) { return /检索/.test(item.innerText || item.textContent || ''); });
            if (button) {
                button.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, composed: true }));
                button.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, composed: true }));
                button.click();
            } else if (input.form) {
                input.form.submit();
            }
            return JSON.stringify({ status: 'submitted', pageTitle: document.title, pageURL: location.href });
        })();
        """
        _ = try? await webView.evaluateJavaScript(script)
    }

    private func extractCurrentPage() async {
        guard let webView,
              let pending = pendingSearch else { return }

        guard let script = Self.loadScript(for: pending.channel) else {
            complete(with: fallbackResponse(from: webView, status: "error", message: "缺少抓取脚本"))
            return
        }

        do {
            let result = try await webView.evaluateJavaScript(script)
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
                complete(with: fallbackResponse(from: webView, status: "error", message: "抓取结果无法解析"))
                return
            }
            chineseBrowserSearchLog.notice(
                "\(pending.channel.displayName, privacy: .public) 搜索完成 status=\(response.status, privacy: .public) results=\(response.results.count)"
            )
            complete(with: response)
        } catch {
            complete(with: fallbackResponse(from: webView, status: "error", message: error.localizedDescription))
        }
    }

    private func fallbackResponse(from webView: WKWebView?, status: String, message: String) -> SearchResponse {
        SearchResponse(
            status: status,
            results: [],
            itemCount: nil,
            pageTitle: webView?.title,
            message: message,
            pageURL: webView?.url?.absoluteString
        )
    }

    private func complete(with response: SearchResponse?) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingSearch = nil
        continuation.resume(returning: response ?? SearchResponse(
            status: "error",
            results: [],
            itemCount: nil,
            pageTitle: nil,
            message: "抓取未返回结果",
            pageURL: nil
        ))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView, let pending = self.pendingSearch else { return }
            switch pending.channel {
            case .wanfang:
                self.pollUntilReadyAndExtract(channel: .wanfang, maxAttempts: 24)
            case .vip:
                self.startVIPSearchIfNeeded(in: webView)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self, weak webView] in
            self?.complete(with: self?.fallbackResponse(from: webView, status: "error", message: error.localizedDescription))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self, weak webView] in
            self?.complete(with: self?.fallbackResponse(from: webView, status: "error", message: error.localizedDescription))
        }
    }

    private static func loadScript(for channel: ChineseJournalBrowserSearchService.Channel) -> String? {
        let name: String
        switch channel {
        case .wanfang: name = "wanfang-search"
        case .vip: name = "vip-search"
        }

        if let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Resources")
            ?? Bundle.module.url(forResource: name, withExtension: "js"),
           let code = try? String(contentsOf: url, encoding: .utf8)
        {
            return code
        }
        return nil
    }

    private static func queryString(for seed: MetadataResolutionSeed) -> String {
        [seed.title, seed.firstAuthor]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func candidate(
        from raw: RawResult,
        channel: ChineseJournalBrowserSearchService.Channel,
        seed: MetadataResolutionSeed,
        pageURL: String?
    ) -> MetadataCandidate {
        // Han names must not go through the Western-oriented AuthorName.parse —
        // it splits "张 三" into given/family and corrupts CSL output.
        let authors = (raw.authors ?? []).map(MetadataResolution.structuredChineseAuthor(from:))

        // Honest multi-field score (title/author/year/journal), on the same
        // scale as CNKI candidates. The previous `max(titleScore, 0.45)` floor
        // let weakly related Wanfang/VIP rows outrank well-matched CNKI
        // candidates in the merged confirmation list and showed users a
        // misleading "45%" for junk results.
        let score = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed,
            title: raw.title,
            authors: authors,
            journal: raw.journal?.swiftlib_nilIfBlank,
            year: raw.year
        )

        let matchedBy = [
            "title",
            raw.authors?.isEmpty == false ? "author" : nil,
            raw.year == nil ? nil : "year",
            raw.journal?.swiftlib_nilIfBlank == nil ? nil : "journal",
            raw.abstract?.swiftlib_nilIfBlank == nil ? nil : "abstract",
        ].compactMap { $0 }

        return MetadataCandidate(
            source: channel.source,
            title: raw.title,
            authors: authors,
            journal: raw.journal?.swiftlib_nilIfBlank,
            year: raw.year,
            detailURL: raw.url?.swiftlib_nilIfBlank ?? pageURL ?? "",
            score: score,
            snippet: raw.abstract?.swiftlib_nilIfBlank,
            workKind: .journalArticle,
            referenceType: .journalArticle,
            sourceRecordID: raw.sourceRecordID?.swiftlib_nilIfBlank,
            matchedBy: matchedBy
        )
    }

    private static func isBlocked(_ response: SearchResponse) -> Bool {
        if response.status.lowercased() == "blocked" { return true }
        let marker = [
            response.status,
            response.pageTitle ?? "",
            response.message ?? "",
            response.pageURL ?? "",
        ]
        .joined(separator: " ")
        .lowercased()
        return marker.contains("安全验证")
            || marker.contains("访问异常")
            || marker.contains("captcha")
            || marker.contains("fault filter abort")
            || marker.contains("412 precondition")
    }

    private static func readinessScript(for channel: ChineseJournalBrowserSearchService.Channel) -> String {
        let resultSelector: String
        let textMarker: String
        switch channel {
        case .wanfang:
            resultSelector = "a[href*='/wf/detail'], a[href*='wanfangdata.com.cn']"
            textMarker = "[期刊论文]"
        case .vip:
            resultSelector = "a[href*='/Qikan/Article/Detail']"
            textMarker = "/Qikan/Article/Detail"
        }
        let selectorLiteral = jsonStringLiteral(resultSelector)
        let textMarkerLiteral = jsonStringLiteral(textMarker)

        return """
        (function () {
            var text = [document.title, location.href, document.body && document.body.innerText].join(' ');
            var blocked = /安全验证|访问异常|captcha|fault filter abort|412 precondition/i.test(text);
            var noResult = /未找到|没有找到|暂无数据|无相关|0\\s*条/.test(text);
            var hasResult = Boolean(document.querySelector(\(selectorLiteral))) || text.indexOf(\(textMarkerLiteral)) >= 0;
            return blocked || noResult || hasResult;
        })();
        """
    }

    private static func vipDirectSearchScript(query: String) -> String {
        let queryLiteral = jsonStringLiteral(query)
        return """
        return (async function () {
            function done(payload) {
                payload.pageTitle = document.title;
                payload.pageURL = location.href;
                return JSON.stringify(payload);
            }

            var query = \(queryLiteral);
            if (typeof SearchParamModel !== 'function') {
                return done({ status: 'missing-runtime', message: 'SearchParamModel unavailable' });
            }

            var model = new SearchParamModel();
            model.ObjectType = 1;
            model.SearchKeyList = [];
            model.SearchExpression = null;
            model.BeginYear = null;
            model.EndYear = null;
            model.UpdateTimeType = null;
            model.JournalRange = null;
            model.DomainRange = null;
            model.ClusterFilter = '';
            model.ClusterLimit = 0;
            model.ClusterUseType = 'Article';
            model.UrlParam = 'U=' + query;
            model.Sort = '0';
            model.SortField = null;
            model.UserID = '0';
            model.PageNum = 1;
            model.PageSize = 20;
            model.SType = null;
            model.StrIds = null;
            model.IsRefOrBy = 0;
            model.ShowRules = '  任意字段=' + query + '  ';
            model.IsNoteHistory = 0;
            model.AdvShowTitle = null;
            model.ObjectId = null;
            model.ObjectSearchType = 0;
            model.ChineseEnglishExtend = 0;
            model.SynonymExtend = 0;
            model.ShowTotalCount = 0;
            model.AdvTabGuid = '';

            var controller = new AbortController();
            var timeout = setTimeout(function () { controller.abort(); }, 10000);
            try {
                var params = new URLSearchParams();
                params.set('searchParamModel', JSON.stringify(model));
                var response = await fetch('/Search/SearchList', {
                    method: 'POST',
                    credentials: 'include',
                    signal: controller.signal,
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                        'X-Requested-With': 'XMLHttpRequest'
                    },
                    body: params.toString()
                });
                var html = await response.text();
                clearTimeout(timeout);
                var container = document.querySelector('#searchlist');
                if (!container) {
                    container = document.createElement('div');
                    container.id = 'searchlist';
                    document.body.appendChild(container);
                }
                container.innerHTML = html || '';
                var marker = [document.title, location.href, html].join(' ');
                var blocked = /安全验证|访问异常|captcha|412 precondition/i.test(marker);
                return done({
                    status: blocked ? 'blocked' : 'ok',
                    httpStatus: response.status,
                    htmlLength: html.length,
                    message: response.ok ? null : response.statusText
                });
            } catch (error) {
                clearTimeout(timeout);
                return done({ status: 'error', message: String(error && error.message ? error.message : error) });
            }
        })();
        """
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }
}
