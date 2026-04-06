import WebKit

/// A pre-warming pool for WKWebView instances that host the TipTap note editor.
/// By creating and loading the HTML upfront, we eliminate the ~500ms delay
/// users would otherwise see when opening the editor for the first time.
@MainActor
final class NoteEditorPool {
    static let shared = NoteEditorPool()

    private var warmWebView: WKWebView?
    private var isWarm = false
    private var warmUpHandler: WarmUpHandler?

    private init() {}

    // MARK: - Public API

    /// Pre-create a WKWebView and load the TipTap editor HTML.
    /// Call this when a reader view appears so the editor is ready when needed.
    func warmUp() {
        guard warmWebView == nil else { return }
        prepareNewWebView()
    }

    /// Acquire a pre-warmed WKWebView. Returns nil if none is ready (rare).
    /// Automatically starts warming the next instance in the background.
    func acquire() -> WKWebView? {
        let webView = warmWebView
        let wasWarm = isWarm
        warmWebView = nil
        isWarm = false
        warmUpHandler = nil

        // Start warming the next instance immediately
        prepareNewWebView()

        return wasWarm ? webView : webView
    }

    /// Release a WKWebView back to the pool after use.
    /// Clears the editor content and marks it as warm for reuse.
    func release(_ webView: WKWebView) {
        // Clear content for reuse
        webView.evaluateJavaScript("window.NoteEditor?.clear()", completionHandler: nil)
        webView.evaluateJavaScript("window.NoteEditor?.setEditable(true)", completionHandler: nil)

        // If we don't have a warm instance, keep this one
        if warmWebView == nil {
            warmWebView = webView
            isWarm = true
            warmUpHandler = nil
        }
        // Otherwise, the returned view is discarded (pool size = 1)
    }

    /// Tear down all pooled resources.
    func teardown() {
        warmUpHandler = nil
        warmWebView?.stopLoading()
        warmWebView = nil
        isWarm = false
    }

    // MARK: - Internal

    private func prepareNewWebView() {
        let controller = WKUserContentController()
        let handler = WarmUpHandler { [weak self] in
            self?.isWarm = true
        }
        controller.add(handler, name: "noteEditorReady")

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 340, height: 200), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false

        // Load the TipTap editor HTML from the app bundle
        if let url = Bundle.module.url(forResource: "NoteEditor", withExtension: "html", subdirectory: "Resources") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let url = Bundle.module.url(forResource: "NoteEditor", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        warmWebView = webView
        warmUpHandler = handler
    }

    /// Minimal WKScriptMessageHandler that only listens for the editor-ready signal.
    private final class WarmUpHandler: NSObject, WKScriptMessageHandler {
        private let onReady: () -> Void

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
            super.init()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "noteEditorReady" {
                onReady()
            }
        }
    }
}
