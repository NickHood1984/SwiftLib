import Foundation

/// Per-host dispatch-gap rate limiter.
///
/// For each API host we enforce a minimum gap between consecutive outgoing
/// requests. This is a simple but effective alternative to a token bucket for
/// I/O-bound usage where we mostly need to respect each provider's
/// requests-per-second policy.
///
/// Recommended limits (conservative, polite-pool friendly):
/// - `api.crossref.org`         : 5 rps  (polite pool allows 10/s for single DOI)
/// - `api.openalex.org`         : 8 rps  (polite pool allows 10/s)
/// - `api.semanticscholar.org`  : 1 rps  (anonymous pool is globally shared)
/// - `eutils.ncbi.nlm.nih.gov`  : 3 rps  (NCBI default without API key)
/// - `export.arxiv.org`         : 1 rps  (arXiv requests ≤3s between bursts; be safe)
/// - default                    : 5 rps
public actor HostRateLimiter {
    public static let shared = HostRateLimiter()

    private var intervalNanos: [String: UInt64] = [
        "api.crossref.org": 200_000_000,          // 5 rps
        "api.openalex.org": 125_000_000,          // 8 rps
        "api.semanticscholar.org": 1_000_000_000, // 1 rps
        "eutils.ncbi.nlm.nih.gov": 334_000_000,   // 3 rps
        "export.arxiv.org": 1_000_000_000,        // 1 rps
        "book.douban.com": 500_000_000,           // 2 rps (be gentle, gets CAPTCHA fast)
        "openlibrary.org": 200_000_000,
        "www.googleapis.com": 200_000_000,
        "xueshu.baidu.com": 1_000_000_000,
    ]
    private let defaultIntervalNanos: UInt64 = 200_000_000 // 5 rps
    private var lastDispatchAt: [String: UInt64] = [:]

    public init() {}

    /// Wait until the next request to `host` is allowed.
    ///
    /// IMPORTANT (actor reentrancy): the dispatch slot must be reserved
    /// *before* suspending on `Task.sleep`. Actors are reentrant across
    /// suspension points, so if we updated `lastDispatchAt` only after the
    /// sleep, every concurrent caller would read the same stale timestamp,
    /// sleep for the same duration, and then fire simultaneously — collapsing
    /// the rate limit exactly when it matters most (batch import / batch
    /// refresh). Reserving the slot up front makes concurrent callers queue
    /// at `interval` spacing: caller N is scheduled at `last + N * interval`.
    public func acquire(host: String) async {
        let host = host.lowercased()
        let interval = intervalNanos[host] ?? defaultIntervalNanos
        let now = DispatchTime.now().uptimeNanoseconds
        let scheduled = max(now, (lastDispatchAt[host] ?? 0) &+ interval)
        // Reserve our slot before any suspension point (see note above).
        lastDispatchAt[host] = scheduled
        if scheduled > now {
            // Task.sleep may throw on cancellation – we ignore that and let
            // the calling request surface the cancellation. The reserved slot
            // is intentionally kept: being slightly conservative after a
            // cancellation is safer than under-spacing the next request.
            try? await Task.sleep(nanoseconds: scheduled - now)
        }
    }

    /// Override the minimum inter-request interval for a host.
    /// Useful for tests or runtime reconfiguration.
    public func setInterval(host: String, requestsPerSecond: Double) {
        guard requestsPerSecond > 0 else { return }
        let nanos = UInt64(1_000_000_000.0 / requestsPerSecond)
        intervalNanos[host.lowercased()] = nanos
    }
}
