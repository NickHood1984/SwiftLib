import Foundation
import OSLog
import SwiftLibCore
import WebKit

private let baiduLog = Logger(subsystem: "SwiftLib", category: "BaiduScholar")

/// 百度学术搜索服务。
/// 用隐藏 WKWebView 加载搜索页，注入 baidu-scholar-search.js 提取结果，替代原 Node.js /search-cn 路径。
/// 调用入口保持 static，内部委托给 MainActor 共享实例 BaiduScholarWebEngine。
enum BaiduScholarService {
    enum SearchOutcome {
        case reference(Reference)
        case noResult
        case blockedByVerification
    }

    @MainActor static let sharedEngine = BaiduScholarWebEngine.shared

    /// 搜索百度学术：两层降级（标题+作者 → 仅标题）。
    static func search(title: String, author: String? = nil) async -> Reference? {
        switch await sharedEngine.searchOutcome(title: title, author: author) {
        case .reference(let reference):
            return reference
        case .noResult, .blockedByVerification:
            return nil
        }
    }

    static func searchOutcome(title: String, author: String? = nil) async -> SearchOutcome {
        await sharedEngine.searchOutcome(title: title, author: author)
    }
}

// MARK: - WKWebView Engine

/// 实际执行 WKWebView 搜索的内部引擎（单例，@MainActor）。
@MainActor
final class BaiduScholarWebEngine: NSObject, WKNavigationDelegate, ObservableObject {

    static let shared = BaiduScholarWebEngine()

    // MARK: - Types

    private struct RawResult: Decodable {
        var title: String
        var url: String?
        var paperId: String?
        var authors: [String]?
        var journal: String?
        var year: Int?
        var abstract: String?
        var doi: String?
    }

    private struct SearchResponse: Decodable {
        var status: String
        var results: [RawResult]
        var pageTitle: String?
        var message: String?
        var pageURL: String?
    }

    struct VerificationSession: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
        let message: String
        let continueLabel: String
    }

    // MARK: - State

    @Published private(set) var verificationSession: VerificationSession?
    private var _webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<SearchResponse?, Error>?
    private var verificationContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    private static let similarityThreshold = 0.55

    // MARK: - Public

    func continueVerification() {
        let continuation = verificationContinuation
        verificationContinuation = nil
        verificationSession = nil
        continuation?.resume()
    }

    func cancelVerification() {
        let continuation = verificationContinuation
        verificationContinuation = nil
        verificationSession = nil
        continuation?.resume(throwing: CancellationError())
    }

    func searchOutcome(title: String, author: String? = nil) async -> BaiduScholarService.SearchOutcome {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noResult }

        var encounteredBlocked = false

        // 策略1: 标题 + 作者
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            let query = "\(trimmed) \(author)"
            baiduLog.notice("百度学术策略1: \"\(query, privacy: .public)\"")
            switch await searchAndMatch(query: query, expectedTitle: trimmed) {
            case .reference(let reference):
                return .reference(reference)
            case .blockedByVerification:
                encounteredBlocked = true
            case .noResult:
                break
            }
        }

        // 策略2: 仅标题
        baiduLog.notice("百度学术策略2: \"\(trimmed, privacy: .public)\"")
        switch await searchAndMatch(query: trimmed, expectedTitle: trimmed) {
        case .reference(let reference):
            return .reference(reference)
        case .blockedByVerification:
            return .blockedByVerification
        case .noResult:
            return encounteredBlocked ? .blockedByVerification : .noResult
        }
    }

    // MARK: - Search

    private func searchAndMatch(query: String, expectedTitle: String) async -> BaiduScholarService.SearchOutcome {
        var components = URLComponents(string: "https://xueshu.baidu.com/s")!
        components.queryItems = [
            URLQueryItem(name: "wd", value: query),
            URLQueryItem(name: "ie", value: "utf-8"),
            URLQueryItem(name: "tn", value: "SE_baiduxueshu_c1gjeupa"),
        ]
        guard let url = components.url else { return .noResult }

        var verificationAttempts = 0

        while true {
            let response: SearchResponse?
            do {
                response = try await loadAndExtract(url: url)
            } catch {
                baiduLog.error("百度学术加载失败: \(error.localizedDescription, privacy: .public)")
                return .noResult
            }

            guard let resp = response else { return .noResult }
            baiduLog.notice("百度学术: pageTitle=\(resp.pageTitle ?? "-", privacy: .public) 结果数=\(resp.results.count)")

            if isBlockedResponse(resp) {
                baiduLog.warning("百度学术: 页面被安全验证拦截，pageTitle=\(resp.pageTitle ?? "-", privacy: .public)")
                guard verificationAttempts < 1 else { return .blockedByVerification }
                verificationAttempts += 1
                do {
                    try await requestVerification(
                        at: URL(string: resp.pageURL ?? "") ?? url,
                        title: "需要继续百度学术会话",
                        message: "百度学术触发了安全验证。请在窗口中完成验证，并保持当前搜索结果页打开，然后点击“继续检查”。",
                        continueLabel: "继续检查"
                    )
                    continue
                } catch {
                    return .blockedByVerification
                }
            }

            var bestResult: RawResult?
            var bestScore: Double = 0
            for result in resp.results.prefix(5) {
                let score = MetadataResolution.titleSimilarity(expectedTitle, result.title)
                if score > bestScore { bestScore = score; bestResult = result }
            }

            guard let candidate = bestResult, bestScore >= Self.similarityThreshold else {
                baiduLog.notice("百度学术: 最佳候选相似度=\(bestScore) 低于阈值")
                return .noResult
            }

            baiduLog.notice("百度学术: 命中 \"\(candidate.title, privacy: .public)\" score=\(bestScore)")
            return .reference(buildReference(from: candidate))
        }
    }

    // MARK: - WKWebView

    private func loadAndExtract(url: URL) async throws -> SearchResponse? {
        let wv = ensureWebView()
        return try await withCheckedThrowingContinuation { cont in
            pendingContinuation = cont

            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s
                guard !Task.isCancelled else { return }
                self?.pendingContinuation?.resume(returning: nil)
                self?.pendingContinuation = nil
            }

            wv.stopLoading()
            wv.load(URLRequest(url: url))
        }
    }

    private func ensureWebView() -> WKWebView {
        if let wv = _webView { return wv }
        let config = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(config)
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 4, height: 4), configuration: config)
        wv.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        wv.navigationDelegate = self
        _webView = wv
        return wv
    }

    // MARK: - JS Injection

    private func injectSearchScript(in webView: WKWebView) {
        guard let script = Self.loadSearchScript() else {
            baiduLog.error("未找到 baidu-scholar-search.js")
            pendingContinuation?.resume(returning: nil)
            pendingContinuation = nil
            return
        }

        // 等待页面 JS 渲染稳定
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard let self, self.pendingContinuation != nil else { return }

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }
                self.timeoutTask?.cancel()
                defer { self.pendingContinuation = nil }

                if let error {
                    baiduLog.error("baidu-scholar-search.js 执行失败: \(error.localizedDescription, privacy: .public)")
                    self.pendingContinuation?.resume(returning: nil)
                    return
                }

                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let resp = try? JSONDecoder().decode(SearchResponse.self, from: data)
                else {
                    baiduLog.error("百度学术 JSON 解析失败")
                    self.pendingContinuation?.resume(returning: nil)
                    return
                }

                self.pendingContinuation?.resume(returning: resp)
            }
        }
    }

    private static func loadSearchScript() -> String? {
        if let url = Bundle.module.url(forResource: "baidu-scholar-search", withExtension: "js", subdirectory: "Resources")
            ?? Bundle.module.url(forResource: "baidu-scholar-search", withExtension: "js"),
           let code = try? String(contentsOf: url, encoding: .utf8)
        {
            return code
        }
        return nil
    }

    private func isBlockedResponse(_ response: SearchResponse) -> Bool {
        let marker = "\(response.pageTitle ?? "") \(response.message ?? "")".lowercased()
        if marker.contains("安全验证") || marker.contains("captcha") || marker.contains("访问异常") {
            return true
        }
        if let pageURL = response.pageURL?.lowercased(),
           pageURL.contains("seccaptcha") || pageURL.contains("/verify/") || pageURL.contains("wappass.baidu.com") {
            return true
        }
        return false
    }

    private func requestVerification(
        at url: URL,
        title: String,
        message: String,
        continueLabel: String
    ) async throws {
        guard verificationContinuation == nil else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            verificationContinuation = continuation
            verificationSession = VerificationSession(
                url: url,
                title: title,
                message: message,
                continueLabel: continueLabel
            )
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.injectSearchScript(in: webView)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.timeoutTask?.cancel()
            self.pendingContinuation?.resume(returning: nil)
            self.pendingContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.timeoutTask?.cancel()
            self.pendingContinuation?.resume(returning: nil)
            self.pendingContinuation = nil
        }
    }

    // MARK: - Reference Builder

    private func buildReference(from raw: RawResult) -> Reference {
        let authors = (raw.authors ?? []).map { AuthorName.parse($0) }
        return Reference(
            title: raw.title,
            authors: authors,
            year: raw.year,
            journal: raw.journal,
            doi: raw.doi,
            url: raw.url,
            abstract: raw.abstract,
            referenceType: .journalArticle,
            metadataSource: .baiduScholar
        )
    }
}
