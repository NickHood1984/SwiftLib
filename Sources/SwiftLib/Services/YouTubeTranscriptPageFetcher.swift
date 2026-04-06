import Foundation
import OSLog
import SwiftLibCore
import WebKit

private let transcriptDOMLog = Logger(subsystem: "SwiftLib", category: "YouTubeTranscriptDOM")

@MainActor
final class YouTubeTranscriptPageFetcher: NSObject, ObservableObject {
    private static let navigationTimeoutNanoseconds: UInt64 = 20_000_000_000
    private static let postLoadSettleNanoseconds: UInt64 = 3_000_000_000

    private weak var webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var fetchSequence: UInt64 = 0

    func registerWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
    }

    func fetchTranscript(urlString: String) async -> String? {
        guard Reference.isLikelyYouTubeWatchURL(urlString: urlString),
              let url = URL(string: urlString) else {
            return nil
        }

        guard let webView = await requireWebView() else {
            transcriptDOMLog.notice("隐藏 YouTube transcript WebView 未就绪")
            return nil
        }

        guard pendingContinuation == nil else {
            transcriptDOMLog.notice("隐藏 YouTube transcript WebView 正忙，跳过新的抓取请求")
            return nil
        }

        fetchSequence &+= 1
        let sequence = fetchSequence

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation

            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.navigationTimeoutNanoseconds)
                guard !Task.isCancelled, self.fetchSequence == sequence else { return }
                self.finishFetch(sequence: sequence, transcript: nil)
            }

            transcriptDOMLog.notice("隐藏 YouTube transcript WebView 开始加载 \(url.absoluteString, privacy: .public)")
            webView.stopLoading()
            webView.load(URLRequest(url: url))
        }
    }

    private func requireWebView() async -> WKWebView? {
        for _ in 0 ..< 80 {
            if let webView {
                return webView
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }

    private func finishFetch(sequence: UInt64, transcript: String?) {
        guard fetchSequence == sequence, let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: transcript)
    }
}

extension YouTubeTranscriptPageFetcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard pendingContinuation != nil else { return }
        let sequence = fetchSequence

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.postLoadSettleNanoseconds)
            guard let self, self.fetchSequence == sequence, self.pendingContinuation != nil else { return }

            let transcript = await ReaderExtractionManager.fetchYouTubeTranscriptFromLoadedPage(in: webView)
            if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcriptDOMLog.notice("隐藏 YouTube transcript WebView DOM fallback 成功 length=\(transcript.count, privacy: .public)")
            } else {
                transcriptDOMLog.notice("隐藏 YouTube transcript WebView DOM fallback 未返回内容")
            }
            self.finishFetch(sequence: sequence, transcript: transcript)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        transcriptDOMLog.notice("隐藏 YouTube transcript WebView 导航失败 \(error.localizedDescription, privacy: .public)")
        finishFetch(sequence: fetchSequence, transcript: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        transcriptDOMLog.notice("隐藏 YouTube transcript WebView 预导航失败 \(error.localizedDescription, privacy: .public)")
        finishFetch(sequence: fetchSequence, transcript: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        transcriptDOMLog.notice("隐藏 YouTube transcript WebView 进程终止")
        finishFetch(sequence: fetchSequence, transcript: nil)
    }
}
