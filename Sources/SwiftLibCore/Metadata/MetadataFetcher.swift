import Foundation
import OSLog

/// Automatic metadata fetching from DOI, PMID, arXiv, ISBN, titles.
/// Uses free public APIs — no API keys required.
///
/// Reliability stack (applied to every outbound request):
/// 1. **Two-tier cache**: in-memory `NSCache` (hot) → SQLite persistent cache (cross-session) → network
/// 2. **In-flight coalescing**: concurrent requests for the same identifier share one network call
/// 3. **Per-host rate limiter**: enforces provider rps limits (CrossRef polite pool, OpenAlex, etc.)
/// 4. **Per-host circuit breaker**: short-circuits when an upstream is repeatedly failing
/// 5. **Exponential backoff + jitter retry** on transient errors (5xx, 429, timeouts)
/// 6. **Structured errors**: `.notFound` vs `.transient` so callers can distinguish "no such record"
///    from "network/provider blipped and we should retry elsewhere"
public enum MetadataFetcher {
    static let log = Logger(subsystem: "com.swiftlib.fetcher", category: "network")

    /// Contact email for CrossRef / OpenAlex polite pool.
    /// Set this from the app layer (e.g. from user preferences) at launch.
    /// CrossRef grants faster rate limits to callers who provide a real mailto.
    public static var contactEmail: String = ""

    /// Concrete executor for `kind == .webView` adapter routes.
    /// Must be set by the host app target (which has WebKit access) at launch.
    public static var webViewExecutor: (any WebViewAdapterExecutor)?
}
