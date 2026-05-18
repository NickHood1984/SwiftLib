import Foundation
import SwiftUI
import WebKit

// MARK: - WKWebView browser wrapper (stores ref in manager)

struct AIChatBrowserView: NSViewRepresentable {
    var url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        wv.allowsBackForwardNavigationGestures = true
        wv.isInspectable = true  // Enable Safari Web Inspector
        context.coordinator.webView = wv
        context.coordinator.currentURL = url

        // Store reference for JS evaluation
        AIChatWindowManager.shared.webView = wv

        context.coordinator.backObserver = NotificationCenter.default.addObserver(
            forName: .aiChatGoBack, object: nil, queue: .main
        ) { _ in wv.goBack() }
        context.coordinator.forwardObserver = NotificationCenter.default.addObserver(
            forName: .aiChatGoForward, object: nil, queue: .main
        ) { _ in wv.goForward() }

        DispatchQueue.main.async {
            wv.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
        }

        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            wv.load(URLRequest(url: url))
        }
        DispatchQueue.main.async {
            wv.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
        }
    }

    static func dismantleNSView(_ wv: WKWebView, coordinator: Coordinator) {
        if let obs = coordinator.backObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = coordinator.forwardObserver { NotificationCenter.default.removeObserver(obs) }
        AIChatWindowManager.shared.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var currentURL: URL?
        var backObserver: NSObjectProtocol?
        var forwardObserver: NSObjectProtocol?

        /// 拦截非 http/https 的 URL scheme，避免页面里触发 `bitbrowser://` / `weixin://`
        /// 这类自定义协议时 macOS 弹出「未设定应用程序」的系统提示。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased()
            switch scheme {
            case "http", "https", "about", "data", "blob", "file", nil:
                decisionHandler(.allow)
            default:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationStarted()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFinished()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFailure(error)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFailure(error)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFailure(AIChatWindowManager.AIChatError.pageInteractionFailed("Web 内容进程已终止，请刷新页面后重试。"))
            }
        }
    }
}
