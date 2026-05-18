import SwiftUI
import WebKit

@MainActor
struct HiddenWKWebViewHost: NSViewRepresentable {
    var configure: (WKWebViewConfiguration) -> Void = { _ in }
    var onCreate: (WKWebView) -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        container.wantsLayer = true

        let configuration = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(configuration)
        configure(configuration)

        let webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.isHidden = true

        container.addSubview(webView)
        onCreate(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
