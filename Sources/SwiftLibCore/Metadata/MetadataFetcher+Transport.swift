import Foundation

extension MetadataFetcher {
    // MARK: - Memory Cache (Hot Tier)

    /// In-memory cache for fetched references (keyed by identifier string).
    /// Avoids duplicate API calls during batch import or repeated lookups.
    private static let responseCache: NSCache<NSString, CachedReference> = {
        let cache = NSCache<NSString, CachedReference>()
        cache.countLimit = 200 // was 50: handles typical batch imports without thrashing
        return cache
    }()
    private static let cacheTTL: TimeInterval = 1800 // 30 minutes (was 5 minutes)

    private final class CachedReference {
        let reference: Reference
        let timestamp: Date
        init(_ ref: Reference) { self.reference = ref; self.timestamp = Date() }
    }

    private static func cachedReference(for key: String) -> Reference? {
        guard let entry = responseCache.object(forKey: key as NSString) else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > cacheTTL {
            responseCache.removeObject(forKey: key as NSString)
            return nil
        }
        return entry.reference
    }

    private static func cacheReference(_ ref: Reference, for key: String) {
        responseCache.setObject(CachedReference(ref), forKey: key as NSString)
    }

    // MARK: - Persistent Cache (Warm Tier)
    //
    // SQLite-backed cache; survives process restart. Write-through; read-on-miss.
    // Keyed by `"<source>:<identifier>"` to avoid cross-source collisions.

    private static let persistentCacheAPI = "metadataFetcher"

    private static func loadFromPersistentCache(key: String) -> Reference? {
        guard let ref = PersistentMetadataCache.getDecoded(
            Reference.self,
            key: key,
            sourceAPI: persistentCacheAPI
        ) else { return nil }
        // Hydrate hot tier too so subsequent hits skip the SQLite round-trip.
        cacheReference(ref, for: key)
        return ref
    }

    private static func storeInPersistentCache(_ ref: Reference, key: String) {
        PersistentMetadataCache.setEncoded(
            ref,
            key: key,
            sourceAPI: persistentCacheAPI,
            ttl: PersistentMetadataCache.defaultTTL
        )
    }

    /// Two-tier cache lookup: memory first, then SQLite.
    static func cachedOrPersisted(key: String) -> Reference? {
        if let hot = cachedReference(for: key) { return hot }
        return loadFromPersistentCache(key: key)
    }

    /// Two-tier cache store: writes to both memory and SQLite.
    static func storeInBothCaches(_ ref: Reference, for key: String) {
        cacheReference(ref, for: key)
        storeInPersistentCache(ref, key: key)
    }

    // MARK: - In-flight Request Coalescing

    /// Actor that ensures concurrent requests for the same identifier share a single
    /// in-flight network call instead of duplicating API traffic.
    actor InFlightCoalescer {
        static let shared = InFlightCoalescer()
        private var tasks: [String: Task<Reference, Error>] = [:]
        private var optionalTasks: [String: Task<Reference?, Error>] = [:]

        func dedupedFetch(key: String, fetch: @Sendable @escaping () async throws -> Reference) async throws -> Reference {
            if let existing = tasks[key] { return try await existing.value }
            let task = Task<Reference, Error> { try await fetch() }
            tasks[key] = task
            defer { tasks[key] = nil }
            return try await task.value
        }

        func dedupedOptionalFetch(key: String, fetch: @Sendable @escaping () async throws -> Reference?) async throws -> Reference? {
            if let existing = optionalTasks[key] { return try await existing.value }
            let task = Task<Reference?, Error> { try await fetch() }
            optionalTasks[key] = task
            defer { optionalTasks[key] = nil }
            return try await task.value
        }
    }

    /// User-Agent header value. Includes mailto when a contact email is configured.
    private static var userAgent: String {
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || !email.contains("@") {
            return "SwiftLib/1.1.1"
        }
        return "SwiftLib/1.1.1 (mailto:\(email))"
    }

    /// Polite-pool mailto parameter appended to URLs for providers that support it
    /// (CrossRef, OpenAlex). Returns empty string when no valid email is configured.
    static var politeMailtoQuery: String {
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.contains("@") else { return "" }
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return "&mailto=\(encoded)"
    }

    // MARK: - WebView Adapter Executor

    /// Unified adapter route execution: automatically dispatches to the
    /// WebView executor when `route.kind == .webView`, otherwise falls back
    /// to the standard HTTP `performRequest`.
    ///
    /// Use this in place of `performRequest` when the caller already has an
    /// adapter `Route` in hand so that future `kind: webView` adapters work
    /// without additional Swift changes.
    public static func fetchAdapterRequest<T>(
        route: SiteAdapterDefinition.Route,
        url: URL,
        parser: @Sendable (Data) throws -> T
    ) async throws -> T {
        if route.kind == .webView {
            guard let executor = webViewExecutor else {
                throw FetchError.unsupported("webView executor not registered")
            }
            let data = try await executor.execute(route: route, url: url)
            return try parser(data)
        }
        return try await performRequest(
            url: url,
            timeout: route.timeoutSeconds ?? 15,
            extraHeaders: route.headers ?? [:],
            parser: parser
        )
    }

    // MARK: - Core Request Helper

    /// Execute a GET request with the full reliability stack (circuit breaker +
    /// rate limiter + retry). Parses the response body with `parser`.
    ///
    /// Classification:
    /// - HTTP 200 → `parser(data)` — any parser failure is `.parseError`
    /// - HTTP 404/410 → `.notFound` (not retried, does not count as breaker failure)
    /// - HTTP 429 / 5xx → `.httpError` (retried; counts as breaker failure)
    /// - Other 4xx → `.httpError` (not retried)
    /// - URLError timeouts / connection lost → retried; counts as breaker failure
    static func performRequest<T>(
        url: URL,
        timeout: TimeInterval = 15,
        extraHeaders: [String: String] = [:],
        parser: @Sendable (Data) throws -> T
    ) async throws -> T {
        let host = url.host?.lowercased() ?? ""

        // Circuit-breaker short-circuit.
        if !host.isEmpty {
            switch await HostCircuitBreaker.shared.check(host: host) {
            case .allow:
                break
            case .reject(let retryAfter):
                log.warning("⛔︎ circuit-open host=\(host, privacy: .public) retryAfter=\(retryAfter)")
                throw FetchError.transient("upstream unavailable for \(host)")
            }
        }

        return try await withRetry {
            if !host.isEmpty {
                await HostRateLimiter.shared.acquire(host: host)
            }

            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
            request.timeoutInterval = timeout

            do {
                let (data, response) = try await NetworkClient.session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 200...299:
                    if !host.isEmpty { await HostCircuitBreaker.shared.recordSuccess(host: host) }
                    return try parser(data)
                case 404, 410:
                    // A genuine "not here" – don't count as breaker failure.
                    throw FetchError.notFound
                case 429, 500...599:
                    if !host.isEmpty { await HostCircuitBreaker.shared.recordFailure(host: host) }
                    throw FetchError.httpError(status)
                default:
                    // Non-retryable 4xx.
                    throw FetchError.httpError(status)
                }
            } catch let error as FetchError {
                throw error
            } catch let error as URLError {
                if !host.isEmpty,
                   [URLError.Code.timedOut,
                    .networkConnectionLost,
                    .cannotConnectToHost,
                    .cannotFindHost,
                    .notConnectedToInternet].contains(error.code) {
                    await HostCircuitBreaker.shared.recordFailure(host: host)
                }
                throw error
            } catch {
                throw FetchError.parseError
            }
        }
    }

    // MARK: - Errors

    public enum FetchError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case parseError
        case unrecognizedIdentifier
        case unsupported(String)
        /// The upstream confirmed the record does not exist (404/410). Not retryable.
        case notFound
        /// Transient upstream condition (circuit-open, unexpected connection failure).
        /// Retryable.
        case transient(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .httpError(let code): return "HTTP error \(code)"
            case .parseError: return "Failed to parse response"
            case .unrecognizedIdentifier: return "Could not recognize identifier (DOI, PMID, arXiv, or ISBN)"
            case .unsupported(let msg): return msg
            case .notFound: return "Record not found"
            case .transient(let msg): return "Temporarily unavailable: \(msg)"
            }
        }

        /// Whether this error is transient and may succeed on retry (5xx, timeout, rate-limited).
        var isRetryable: Bool {
            switch self {
            case .httpError(let code): return code >= 500 || code == 429
            case .transient: return true
            default: return false
            }
        }
    }

    // MARK: - Retry Helper

    /// Execute an async operation with up to `maxAttempts` retries and exponential backoff.
    /// Retries on 5xx HTTP errors, 429 rate-limiting, `.transient`, and network timeouts.
    static func withRetry<T>(
        maxAttempts: Int = 3,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch let error as FetchError where error.isRetryable {
                lastError = error
                let baseDelay: UInt64 = {
                    if case .httpError(429) = error { return 3_000_000_000 } // 3s base for rate-limit
                    if case .transient = error { return 2_000_000_000 }      // 2s base for transient
                    return 1_000_000_000 // 1s base for server errors
                }()
                let delay = baseDelay * UInt64(1 << attempt)
                let jitteredDelay = UInt64(Double(delay) * Double.random(in: 0.5...1.5))
                try await Task.sleep(nanoseconds: jitteredDelay)
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                lastError = error
                let delay: UInt64 = 1_000_000_000 * UInt64(1 << attempt)
                let jitteredDelay = UInt64(Double(delay) * Double.random(in: 0.5...1.5))
                try await Task.sleep(nanoseconds: jitteredDelay)
            }
        }
        throw lastError ?? FetchError.transient("retries exhausted")
    }
}
