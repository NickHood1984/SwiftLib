import Foundation
import OSLog
import SwiftLibCore
import WebKit

private let executorLog = Logger(subsystem: "com.swiftlib.fetcher", category: "WebViewAdapterExecutor")

/// Concrete `WebViewAdapterExecutor` for the macOS app target.
///
/// Reuses `WebSessionBroker` for cookie/session isolation, spins up a hidden
/// `WKWebView`, waits for navigation + JS-render settle, then returns the
/// page source as UTF-8 `Data` for downstream `SiteAdapterRuntime` extraction.
@MainActor
final class WebViewAdapterExecutorImpl: NSObject, WebViewAdapterExecutor, WKNavigationDelegate {

    private var webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<Data, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var currentRoute: SiteAdapterDefinition.Route?
    private var startedURL: URL?

    // MARK: - WebViewAdapterExecutor

    func execute(
        route: SiteAdapterDefinition.Route,
        url: URL
    ) async throws -> Data {
        let profile = WebSessionBroker.shared.scholarlyProfile(for: url)
        let wv = ensureWebView(profile: profile)

        return try await withCheckedThrowingContinuation { [weak self] (cont: CheckedContinuation<Data, Error>) in
            guard let self else {
                cont.resume(throwing: MetadataFetcher.FetchError.unsupported("executor deallocated"))
                return
            }
            self.pendingContinuation = cont
            self.currentRoute = route
            self.startedURL = url

            let timeoutSeconds = route.timeoutSeconds ?? 20
            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.fail(.transient("webView timeout after \(timeoutSeconds)s"))
            }

            executorLog.notice("webView adapter loading url=\(url.absoluteString, privacy: .public) profile=\(profile.id, privacy: .public)")
            wv.load(URLRequest(url: url))
        }
    }

    // MARK: - Lifecycle

    private func ensureWebView(profile: WebSessionBroker.Profile) -> WKWebView {
        if let wv = webView { return wv }

        let configuration = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(configuration)
        WebSessionBroker.shared.configure(configuration, profile: profile)

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 4, height: 4), configuration: configuration)
        wv.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        wv.navigationDelegate = self
        webView = wv
        return wv
    }

    private func cleanUp() {
        timeoutTask?.cancel()
        timeoutTask = nil
        currentRoute = nil
        startedURL = nil
    }

    private func complete(with data: Data) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        cleanUp()
        executorLog.notice("webView adapter completed bytes=\(data.count)")
        cont.resume(returning: data)
    }

    private func fail(_ error: MetadataFetcher.FetchError) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        cleanUp()
        webView?.stopLoading()
        executorLog.error("webView adapter failed: \(error.localizedDescription, privacy: .public)")
        cont.resume(throwing: error)
    }

    // MARK: - Content extraction

    private func extractPageContent(from webView: WKWebView) async {
        let extractKind = currentRoute?.extract.kind

        let script: String
        switch extractKind {
        case .html, .none:
            // Default: return the fully-rendered DOM HTML.
            script = "document.documentElement.outerHTML"
        case .json:
            // For JSON endpoints served inside a browser context,
            // body.innerText usually contains the raw JSON string.
            script = "document.body ? document.body.innerText : document.documentElement.outerHTML"
        }

        do {
            let raw = try await webView.evaluateJavaScript(script)
            guard let text = raw as? String, !text.isEmpty else {
                fail(.parseError)
                return
            }
            if let data = text.data(using: .utf8) {
                complete(with: data)
            } else {
                fail(.parseError)
            }
        } catch {
            fail(.parseError)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard pendingContinuation != nil else { return }
        let pageURL = webView.url?.absoluteString ?? startedURL?.absoluteString ?? "unknown"
        executorLog.notice("webView didFinish url=\(pageURL, privacy: .public)")

        // Allow 1 s for deferred JS meta-tag injection (same delay as
        // `WebScholarlyMetadataExtractor`).
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, self.pendingContinuation != nil else { return }
            await self.extractPageContent(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard pendingContinuation != nil else { return }
        fail(.transient(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard pendingContinuation != nil else { return }
        fail(.transient(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard pendingContinuation != nil else { return }
        fail(.transient("webView content process terminated"))
    }
}
