import Combine
import Foundation
import OSLog
import SwiftLibCore
import WebKit

private let clipperImportLog = Logger(subsystem: "SwiftLib", category: "WebpageImport")

/// 从网页添加条目时：用与在线阅读相同的 WKWebView + ClipperDefuddle / Readability 流水线抓取标题、摘要、作者。
@MainActor
final class ClipperWebMetadataExtractor: NSObject, ObservableObject {
    struct ExtractResult: Sendable {
        var title: String
        var abstract: String?
        var authors: [AuthorName]
        var resolvedURLString: String
        var siteHost: String?
        var webContent: String?
    }

    enum ExtractError: LocalizedError {
        case invalidURL
        case webViewNotReady
        case timedOut
        case navigationFailed(String)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "请输入以 http 或 https 开头的有效链接。"
            case .webViewNotReady: return "网页组件尚未就绪，请稍候再试。"
            case .timedOut: return "抓取超时，请检查网络或稍后重试。"
            case .navigationFailed(let s): return "无法打开页面：\(s)"
            case .extractionFailed(let s): return s
            }
        }
    }

    @Published private(set) var isExtracting = false

    let extractionManager = ReaderExtractionManager()

    private weak var webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<ExtractResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var startedURLString = ""

    override init() {
        super.init()
        extractionManager.onDefuddleSuccess = { [weak self] title, content, excerpt, byline in
            Task { @MainActor in
                self?.completeWithClipperResult(title: title, content: content, excerpt: excerpt, byline: byline, source: "Defuddle")
            }
        }
        extractionManager.onReadabilitySuccess = { [weak self] title, content, excerpt, byline in
            Task { @MainActor in
                self?.completeWithClipperResult(title: title, content: content, excerpt: excerpt, byline: byline, source: "Readability")
            }
        }
        extractionManager.onYouTubeFallbackSuccess = { [weak self] title, content, excerpt, byline in
            Task { @MainActor in
                self?.completeWithClipperResult(title: title, content: content, excerpt: excerpt, byline: byline, source: "YouTubeFallback")
            }
        }
        extractionManager.onTerminalFailure = { [weak self] message in
            Task { @MainActor in
                self?.failExtraction(.extractionFailed(message))
            }
        }
    }

    func registerWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
        extractionManager.hostWebView = webView
        extractionManager.isLiveReadableBusyContext = { [weak self] in
            self?.isExtracting ?? false
        }
    }

    /// 等待隐藏 WKWebView 挂载（SwiftUI 首帧可能略晚于用户点按）。
    private func requireWebView() async throws -> WKWebView {
        for _ in 0 ..< 80 {
            if let wv = webView { return wv }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw ExtractError.webViewNotReady
    }

    func extract(urlString raw: String) async throws -> ExtractResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw ExtractError.invalidURL
        }

        let wv = try await requireWebView()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExtractResult, Error>) in
            guard pendingContinuation == nil else {
                cont.resume(throwing: ExtractError.extractionFailed("已有进行中的抓取。"))
                return
            }
            pendingContinuation = cont
            startedURLString = url.absoluteString
            isExtracting = true

            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard !Task.isCancelled else { return }
                self.failExtraction(.timedOut)
            }

            extractionManager.resetForNewNavigation()
            wv.stopLoading()
            clipperImportLog.notice("开始 Clipper 抓取 url=\(trimmed, privacy: .public)")
            wv.load(URLRequest(url: url))
        }
    }

    private func completeWithClipperResult(title: String?, content: String?, excerpt: String?, byline: String?, source: String) {
        guard isExtracting, pendingContinuation != nil else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        isExtracting = false

        let host = webView?.url.flatMap { $0.host }
        let resolved = webView?.url?.absoluteString ?? startedURLString
        let abstract = excerpt.map { Self.plainTextFromHTMLFragment($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let authors = AuthorName.parseList(byline ?? "")
        let webContent = Reference.encodeWebContent(content, format: .html)
        let titleTrim = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalTitle: String
        if !titleTrim.isEmpty {
            finalTitle = titleTrim
        } else if let h = host, !h.isEmpty {
            finalTitle = h
        } else {
            finalTitle = "Webpage"
        }

        clipperImportLog.notice("Clipper 抓取成功 source=\(source, privacy: .public) titleLen=\(finalTitle.count) abstractLen=\(abstract?.count ?? 0) bodyLen=\(webContent?.count ?? 0)")

        let result = ExtractResult(
            title: finalTitle,
            abstract: abstract,
            authors: authors,
            resolvedURLString: resolved,
            siteHost: host,
            webContent: webContent
        )
        pendingContinuation?.resume(returning: result)
        pendingContinuation = nil
    }

    private func failExtraction(_ error: ExtractError) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        isExtracting = false
        webView?.stopLoading()
        clipperImportLog.error("Clipper 抓取失败 \(error.localizedDescription, privacy: .public)")
        cont.resume(throwing: error)
    }

    private static func plainTextFromHTMLFragment(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        return stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - WKNavigationDelegate

extension ClipperWebMetadataExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isExtracting else { return }
        let pageURL = webView.url?.absoluteString ?? startedURLString
        clipperImportLog.notice("WK didFinish 即将注入 Clipper url=\(pageURL, privacy: .public)")

        if Reference.isLikelyYouTubeWatchURL(urlString: pageURL) {
            clipperImportLog.notice("YouTube：延迟 2.5s 再抽取（与在线阅读一致）")
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, self.isExtracting, self.webView === webView else { return }
                self.extractionManager.isYouTubeExtractionContext = true
                self.extractionManager.runOnlineArticleExtraction(from: webView)
            }
        } else {
            extractionManager.isYouTubeExtractionContext = false
            extractionManager.runOnlineArticleExtraction(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isExtracting else { return }
        failExtraction(.navigationFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isExtracting else { return }
        failExtraction(.navigationFailed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isExtracting else { return }
        failExtraction(.extractionFailed("网页渲染进程已终止。"))
    }
}
