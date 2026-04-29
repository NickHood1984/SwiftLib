import Foundation

/// Abstract executor for `SiteAdapterDefinition.Route` where `kind == .webView`.
///
/// Concrete implementations are provided by the host app target (SwiftLib) because they
/// require WebKit (`WKWebView`). Register via `MetadataFetcher.webViewExecutor`.
///
/// Execution contract:
/// 1. Load the expanded URL in a webView session that reuses existing cookies
///    (e.g. via `WKWebsiteDataStore` profile matching the target host).
/// 2. Wait for the page to settle (JS-rendered SPA content, deferred meta tags).
/// 3. Return the raw response body encoded as UTF-8 `Data` so that
///    `SiteAdapterRuntime` can extract fields.
///
/// - For `extract.kind == .html` the implementation should return the
///   final DOM HTML (`document.documentElement.outerHTML`).
/// - For `extract.kind == .json` the implementation should return the
///   JSON text visible to the page (e.g. `document.body.innerText` when the
///   endpoint serves `application/json`, or the result of a minimal injected
///   JS snippet that serialises the desired data structure).
public protocol WebViewAdapterExecutor: Sendable {
    func execute(
        route: SiteAdapterDefinition.Route,
        url: URL
    ) async throws -> Data
}
