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

    // MARK: - Logging

    static let log = Logger(subsystem: "com.swiftlib.fetcher", category: "network")

    /// Contact email for CrossRef / OpenAlex polite pool.
    /// Set this from the app layer (e.g. from user preferences) at launch.
    /// CrossRef grants faster rate limits to callers who provide a real mailto.
    public static var contactEmail: String = ""

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
    private static func cachedOrPersisted(key: String) -> Reference? {
        if let hot = cachedReference(for: key) { return hot }
        return loadFromPersistentCache(key: key)
    }

    /// Two-tier cache store: writes to both memory and SQLite.
    private static func storeInBothCaches(_ ref: Reference, for key: String) {
        cacheReference(ref, for: key)
        storeInPersistentCache(ref, key: key)
    }

    // MARK: - In-flight Request Coalescing

    /// Actor that ensures concurrent requests for the same identifier share a single
    /// in-flight network call instead of duplicating API traffic.
    private actor InFlightCoalescer {
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
    private static var politeMailtoQuery: String {
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.contains("@") else { return "" }
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return "&mailto=\(encoded)"
    }

    // MARK: - Identifier Detection

    public enum Identifier {
        case doi(String)
        case pmid(String)
        case arxiv(String)
        case isbn(String)
    }

    /// Parse raw text input and detect identifier type (priority: DOI > ISBN > arXiv > PMID)
    public static func extractIdentifier(from text: String) -> Identifier? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // DOI: 10.XXXX/... (most specific)
        if let doi = cleanDOI(trimmed) {
            return .doi(doi)
        }

        // ISBN: 10 or 13 digits, with checksum validation to avoid phone-number
        // style false positives (plain numeric strings are common).
        let digitsOnly = trimmed.replacingOccurrences(of: "[^0-9X]", with: "", options: .regularExpression)
        if digitsOnly.count == 13,
           digitsOnly.hasPrefix("978") || digitsOnly.hasPrefix("979"),
           isValidISBN13(digitsOnly) {
            return .isbn(digitsOnly)
        }
        if digitsOnly.count == 10, isValidISBN10(digitsOnly) {
            return .isbn(digitsOnly)
        }

        // arXiv: YYMM.NNNNN or category/NNNNNNN
        let arxivPatterns = [
            #"(\d{4}\.\d{4,5})(v\d+)?"#,
            #"([a-z\-]+/\d{7})"#,
            #"arXiv:(.+)"#
        ]
        for pattern in arxivPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                return .arxiv(String(trimmed[range]))
            }
        }

        // PMID: bare number. Modern PMIDs are 7–8 digits; we require ≥6 to avoid
        // grabbing arbitrary small integers (e.g. a random "42").
        if Int(trimmed) != nil, trimmed.count >= 6, trimmed.count <= 9 {
            return .pmid(trimmed)
        }

        return nil
    }

    /// Clean and extract DOI from various formats (URL, bare DOI, etc.).
    /// Preserve the input casing for display/storage; use `normalizedDOI`
    /// for cache keys and outbound requests.
    private static func cleanDOI(_ input: String) -> String? {
        var text = input
        // Handle doi.org URLs
        if let range = text.range(of: "doi.org/") {
            text = String(text[range.upperBound...])
        }
        // Handle "doi:" prefix
        if text.lowercased().hasPrefix("doi:") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        // Match DOI pattern: 10.XXXX/...
        let pattern = #"(10\.\d{4,}\/[^\s]+[^\s\.,;\]\)])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// Normalize a DOI for cache keys and outbound requests (lowercase, trimmed).
    static func normalizedDOI(_ doi: String) -> String {
        doi.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - ISBN Checksum Validation

    /// Validate ISBN-10 using the standard weighted-sum checksum.
    static func isValidISBN10(_ isbn: String) -> Bool {
        let digits = isbn.uppercased().unicodeScalars
        guard digits.count == 10 else { return false }
        var sum = 0
        for (i, scalar) in digits.enumerated() {
            let weight = 10 - i
            let digit: Int
            if scalar.value >= 0x30 && scalar.value <= 0x39 {
                digit = Int(scalar.value - 0x30)
            } else if i == 9 && scalar == "X" {
                digit = 10
            } else {
                return false
            }
            sum += digit * weight
        }
        return sum % 11 == 0
    }

    /// Validate ISBN-13 using the standard EAN-13 checksum.
    static func isValidISBN13(_ isbn: String) -> Bool {
        let digits = isbn.unicodeScalars
        guard digits.count == 13 else { return false }
        var sum = 0
        for (i, scalar) in digits.enumerated() {
            guard scalar.value >= 0x30 && scalar.value <= 0x39 else { return false }
            let digit = Int(scalar.value - 0x30)
            sum += (i % 2 == 0) ? digit : digit * 3
        }
        return sum % 10 == 0
    }

    /// Convert a valid ISBN-10 to its equivalent ISBN-13 (978 prefix).
    static func isbn10To13(_ isbn10: String) -> String? {
        guard isValidISBN10(isbn10) else { return nil }
        let prefix = "978" + String(isbn10.prefix(9))
        var sum = 0
        for (i, ch) in prefix.enumerated() {
            guard let digit = Int(String(ch)) else { return nil }
            sum += (i % 2 == 0) ? digit : digit * 3
        }
        let check = (10 - (sum % 10)) % 10
        return prefix + String(check)
    }

    /// Convert a valid 978-prefixed ISBN-13 to its ISBN-10 equivalent.
    static func isbn13To10(_ isbn13: String) -> String? {
        guard isValidISBN13(isbn13), isbn13.hasPrefix("978") else { return nil }
        let core = String(isbn13.dropFirst(3).prefix(9))
        var sum = 0
        for (i, ch) in core.enumerated() {
            guard let digit = Int(String(ch)) else { return nil }
            sum += digit * (10 - i)
        }
        let rem = sum % 11
        let checkValue = (11 - rem) % 11
        let check = checkValue == 10 ? "X" : String(checkValue)
        return core + check
    }

    // MARK: - WebView Adapter Executor

    /// Concrete executor for `kind == .webView` adapter routes.
    /// Must be set by the host app target (which has WebKit access) at launch.
    public static var webViewExecutor: (any WebViewAdapterExecutor)?

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

    // MARK: - DOI → Crossref API (adapter-driven)

    /// Fetch metadata from DOI via Crossref REST API.
    /// URL template, field paths, JATS abstract cleanup, and date-part
    /// extraction all live in `Resources/adapters/crossref-work.json`.
    public static func fetchFromDOI(_ doi: String, forceRefresh: Bool = false) async throws -> Reference {
        let normalized = normalizedDOI(doi)
        let cacheKey = "doi:\(normalized)"
        // Under forceRefresh the user explicitly asked for a fresh scrape
        // (e.g. the "Refresh Metadata" UI action); skip BOTH cache tiers.
        // storeInBothCaches at the end still writes the new value, so the
        // cache ends up updated, not invalidated.
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            guard let adapter = SiteAdapterRegistry.shared.adapter(id: "crossref-work"),
                  let route = adapter.routes["byDoi"] else {
                throw FetchError.unsupported("crossref-work adapter missing")
            }
            let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["doi": normalized])
            guard let url = URL(string: urlString) else {
                throw FetchError.invalidURL
            }

            var ref = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                try parseCrossrefResponse(data, doi: normalized)
            }

            // Crossref often lacks abstract (Nature, etc.) — fetch from S2 and OpenAlex in parallel, take first success.
            if ref.abstract == nil || ref.abstract?.isEmpty == true {
                async let s2Abstract = try? fetchAbstractFromSemanticScholar(doi: normalized)
                async let oaAbstract = try? fetchAbstractFromOpenAlex(doi: normalized)

                let (s2, oa) = await (s2Abstract, oaAbstract)
                // Prefer Semantic Scholar (tends to be higher quality for STEM).
                ref.abstract = (s2 ?? nil) ?? (oa ?? nil)
            }

            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    // MARK: - OpenAlex Enrichment

    /// Rich metadata returned by OpenAlex that supplements the core Reference fields.
    public struct OpenAlexEnrichment: Codable, Hashable, Sendable {
        public var keywords: [String]
        public var topics: [String]
        public var isOpenAccess: Bool
        public var oaUrl: String?
        public var citedByCount: Int
        public var fundingInfo: [String]
        public var referenceType: ReferenceType?
        public var openAlexId: String?
        public var abstract: String?
        public var reference: Reference?
    }

    /// Fetch rich enrichment data from OpenAlex by DOI.
    public static func enrichWithOpenAlex(doi: String) async -> OpenAlexEnrichment? {
        let normalized = normalizedDOI(doi)
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalized
        let urlString = "https://api.openalex.org/works/doi:\(encoded)?select=id,type,concepts,topics,open_access,cited_by_count,grants,abstract_inverted_index\(politeMailtoQuery)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw FetchError.parseError
                }
                return parseOpenAlexEnrichment(json)
            }
        } catch {
            log.debug("OpenAlex enrichment(doi=\(normalized, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Fetch rich enrichment data from OpenAlex by title search.
    public static func enrichWithOpenAlex(title: String) async -> OpenAlexEnrichment? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "https://api.openalex.org/works?search=\(encoded)&select=id,type,concepts,topics,open_access,cited_by_count,grants,abstract_inverted_index&per-page=1\(politeMailtoQuery)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let work = results.first else {
                    throw FetchError.notFound
                }
                return parseOpenAlexEnrichment(work)
            }
        } catch {
            return nil
        }
    }

    /// Parse OpenAlex work JSON into an enrichment struct.
    static func parseOpenAlexEnrichment(_ work: [String: Any]) -> OpenAlexEnrichment {
        let openAlexId = work["id"] as? String

        let keywords: [String] = {
            guard let concepts = work["concepts"] as? [[String: Any]] else { return [] }
            return concepts
                .sorted { ($0["score"] as? Double ?? 0) > ($1["score"] as? Double ?? 0) }
                .compactMap { $0["display_name"] as? String }
        }()

        let topics: [String] = {
            guard let topicList = work["topics"] as? [[String: Any]] else { return [] }
            return topicList.compactMap { $0["display_name"] as? String }
        }()

        let oa = work["open_access"] as? [String: Any]
        let isOpenAccess = oa?["is_oa"] as? Bool ?? false
        let oaUrl = oa?["oa_url"] as? String

        let citedByCount = work["cited_by_count"] as? Int ?? 0

        let fundingInfo: [String] = {
            guard let grants = work["grants"] as? [[String: Any]] else { return [] }
            return grants.compactMap { grant -> String? in
                let funder = grant["funder_display_name"] as? String
                let awardId = grant["award_id"] as? String
                guard let funder else { return nil }
                if let awardId, !awardId.isEmpty {
                    return "\(funder) (\(awardId))"
                }
                return funder
            }
        }()

        let referenceType: ReferenceType? = {
            switch work["type"] as? String {
            case "journal-article", "article": return .journalArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "preprint", "posted-content": return .preprint
            case "report": return .report
            case "dataset": return .dataset
            default: return nil
            }
        }()

        let abstract = reconstructAbstract(fromInvertedIndex: work["abstract_inverted_index"] as? [String: [Int]])

        return OpenAlexEnrichment(
            keywords: keywords,
            topics: topics,
            isOpenAccess: isOpenAccess,
            oaUrl: oaUrl,
            citedByCount: citedByCount,
            fundingInfo: fundingInfo,
            referenceType: referenceType,
            openAlexId: openAlexId,
            abstract: abstract
        )
    }

    /// Reconstruct a continuous abstract string from OpenAlex's inverted index format.
    /// Used by every OpenAlex parser that wants the abstract; centralized here.
    static func reconstructAbstract(fromInvertedIndex invertedIndex: [String: [Int]]?) -> String? {
        guard let invertedIndex else { return nil }
        var positions: [Int: String] = [:]
        for (word, indices) in invertedIndex {
            for idx in indices { positions[idx] = word }
        }
        guard !positions.isEmpty else { return nil }
        let abstract = positions.keys.sorted().compactMap { positions[$0] }.joined(separator: " ")
        return abstract.isEmpty ? nil : abstract
    }

    // MARK: - easyScholar Journal Rank

    /// Fetch journal rank data from easyScholar open API.
    public static func enrichWithEasyScholar(journal: String, secretKey: String) async -> EasyScholarRankResponse? {
        await EasyScholarRankProvider.fetchRank(publicationName: journal, secretKey: secretKey)
    }

    // MARK: - Semantic Scholar

    /// Rich result from Semantic Scholar Graph API.
    public struct S2PaperResult: Sendable {
        public var paperId: String
        public var title: String
        public var abstract: String?
        public var tldr: String?
        public var year: Int?
        public var venue: String?
        public var journal: S2Journal?
        public var authors: [AuthorName]
        public var citationCount: Int
        public var influentialCitationCount: Int
        public var isOpenAccess: Bool
        public var openAccessPdfUrl: String?
        public var externalIds: S2ExternalIds?
        public var publicationDate: String?
    }

    public struct S2Journal: Sendable {
        public var name: String?
        public var volume: String?
        public var pages: String?
    }

    public struct S2ExternalIds: Sendable {
        public var doi: String?
        public var arxivId: String?
        public var pmid: String?
        public var pmcid: String?
    }

    /// Fetch full paper data from Semantic Scholar by DOI. Goes through the
    /// `semantic-scholar-paper.byDoi` adapter; returns nil on any transport or
    /// parse failure so callers can fall through to other sources.
    public static func fetchFromSemanticScholar(doi: String) async -> S2PaperResult? {
        let normalized = normalizedDOI(doi)
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "semantic-scholar-paper"),
              let route = adapter.routes["byDoi"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["doi": normalized])
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }
            guard let row = rows.first else { return nil }
            return s2PaperResultFromRow(row)
        } catch {
            log.debug("S2 fetch(doi=\(normalized, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Search Semantic Scholar by exact title match. Adapter route `byTitleMatch`.
    public static func searchSemanticScholar(title: String) async -> S2PaperResult? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "semantic-scholar-paper"),
              let route = adapter.routes["byTitleMatch"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["title": title])
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }
            guard let row = rows.first else { return nil }
            return s2PaperResultFromRow(row)
        } catch {
            return nil
        }
    }

    /// Translate an S2 adapter row to `S2PaperResult`. Exposed internally so
    /// fixture-based tests can exercise the mapping without hitting the network.
    static func s2PaperResultFromRow(_ row: [String: String]) -> S2PaperResult? {
        guard let paperId = row["paperId"]?.swiftlib_nilIfBlank,
              let title = row["title"]?.swiftlib_nilIfBlank else { return nil }

        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parse(String($0)) }

        let journal: S2Journal? = {
            let name = row["journalName"]?.swiftlib_nilIfBlank
            let volume = row["journalVolume"]?.swiftlib_nilIfBlank
            let pages = row["journalPages"]?.swiftlib_nilIfBlank
            if name == nil && volume == nil && pages == nil { return nil }
            return S2Journal(name: name, volume: volume, pages: pages)
        }()

        let externalIds: S2ExternalIds? = {
            let doi = row["doi"]?.swiftlib_nilIfBlank
            let arxiv = row["arxivId"]?.swiftlib_nilIfBlank
            let pmid = row["pmid"]?.swiftlib_nilIfBlank
            let pmcid = row["pmcid"]?.swiftlib_nilIfBlank
            if doi == nil && arxiv == nil && pmid == nil && pmcid == nil { return nil }
            return S2ExternalIds(doi: doi, arxivId: arxiv, pmid: pmid, pmcid: pmcid)
        }()

        return S2PaperResult(
            paperId: paperId,
            title: title,
            abstract: row["abstract"]?.swiftlib_nilIfBlank,
            tldr: row["tldr"]?.swiftlib_nilIfBlank,
            year: row["year"].flatMap(Int.init),
            venue: row["venue"]?.swiftlib_nilIfBlank,
            journal: journal,
            authors: authors,
            citationCount: row["citationCount"].flatMap(Int.init) ?? 0,
            influentialCitationCount: row["influentialCitationCount"].flatMap(Int.init) ?? 0,
            isOpenAccess: row["isOpenAccess"] == "true",
            openAccessPdfUrl: row["openAccessPdfUrl"]?.swiftlib_nilIfBlank,
            externalIds: externalIds,
            publicationDate: row["publicationDate"]?.swiftlib_nilIfBlank
        )
    }

    /// Convert S2PaperResult to Reference for merge purposes.
    public static func referenceFromS2(_ s2: S2PaperResult) -> Reference {
        let doi = s2.externalIds?.doi
        let pages: String? = s2.journal?.pages
        return Reference(
            title: s2.title,
            authors: s2.authors,
            year: s2.year,
            journal: s2.journal?.name ?? (s2.venue?.isEmpty == false ? s2.venue : nil),
            volume: s2.journal?.volume,
            pages: pages,
            doi: doi,
            abstract: s2.abstract,
            referenceType: .journalArticle,
            metadataSource: .semanticScholar,
            pmid: s2.externalIds?.pmid,
            pmcid: s2.externalIds?.pmcid,
            isOpenAccess: s2.isOpenAccess ? true : nil,
            oaUrl: s2.openAccessPdfUrl,
            citedByCount: s2.citationCount > 0 ? s2.citationCount : nil
        )
    }

    /// Fetch abstract from Semantic Scholar via the `abstractByDoi` route.
    public static func fetchAbstractFromSemanticScholar(doi: String) async throws -> String? {
        let normalized = normalizedDOI(doi)
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "semantic-scholar-paper"),
              let route = adapter.routes["abstractByDoi"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["doi": normalized])
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                let rows = (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
                return rows.first?["abstract"]?.swiftlib_nilIfBlank
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    /// Fetch abstract from OpenAlex (free, no API key, covers ~250M works)
    public static func fetchAbstractFromOpenAlex(doi: String) async throws -> String? {
        let normalized = normalizedDOI(doi)
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalized
        let urlString = "https://api.openalex.org/works/doi:\(encoded)?select=abstract_inverted_index\(politeMailtoQuery)"
        return try await fetchOpenAlexAbstract(urlString)
    }

    /// Fetch abstract from OpenAlex using Title fallback
    public static func fetchAbstractFromOpenAlex(title: String) async throws -> String? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "https://api.openalex.org/works?search=\(encoded)&select=abstract_inverted_index&per-page=1\(politeMailtoQuery)"
        return try await fetchOpenAlexAbstract(urlString, isSearch: true)
    }

    private static func fetchOpenAlexAbstract(_ urlString: String, isSearch: Bool = false) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            return try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil as String?
                }
                let workData: [String: Any]?
                if isSearch {
                    guard let results = json["results"] as? [[String: Any]], let first = results.first else {
                        return nil as String?
                    }
                    workData = first
                } else {
                    workData = json
                }
                return reconstructAbstract(fromInvertedIndex: workData?["abstract_inverted_index"] as? [String: [Int]])
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - CrossRef Parser (adapter-driven)

    /// Parses a CrossRef `/works/{doi}` JSON body into a `Reference`.
    /// All schema knowledge lives in `crossref-work.byDoi` adapter;
    /// this function is a thin dispatcher + domain mapper.
    /// Kept as a named function so `fetchFromDOI` and existing unit tests
    /// (fixture-fed) can keep calling it.
    static func parseCrossrefResponse(_ data: Data, doi: String) throws -> Reference {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "crossref-work"),
              let route = adapter.routes["byDoi"] else {
            throw FetchError.parseError
        }
        let rows = (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
        guard let row = rows.first else { throw FetchError.parseError }
        return referenceFromCrossRefRow(row, doi: doi)
    }

    /// Translate a CrossRef adapter row to `Reference`. Applies the CJK-swap
    /// heuristic on a per-author basis and re-interleaves organization authors
    /// (which come via the `author[*].name` path) with person authors (via
    /// `author[*].given` / `author[*].family`).
    /// Exposed internally so tests can feed synthetic rows directly.
    static func referenceFromCrossRefRow(_ row: [String: String], doi: String) -> Reference {
        let title: String = {
            if let full = row["titleWithSubtitle"]?.swiftlib_nilIfBlank { return full }
            return row["title"]?.swiftlib_nilIfBlank ?? "Untitled"
        }()

        // First non-empty date wins: published-print → online → issued → created.
        let year: Int? = [
            row["yearPrint"], row["yearOnline"], row["yearIssued"], row["yearCreated"]
        ]
        .compactMap { $0?.swiftlib_nilIfBlank }
        .first
        .flatMap { Int($0.prefix(4)) }

        let referenceType: ReferenceType = {
            switch row["type"] {
            case "journal-article": return .journalArticle
            case "newspaper-article": return .newspaperArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "report", "report-component": return .report
            case "standard": return .standard
            case "posted-content": return .preprint
            case .none: return .journalArticle
            default: return .other
            }
        }()

        return Reference(
            title: title,
            authors: buildCrossRefAuthors(row: row),
            year: year,
            journal: row["journal"]?.swiftlib_nilIfBlank,
            volume: row["volume"]?.swiftlib_nilIfBlank,
            issue: row["issue"]?.swiftlib_nilIfBlank,
            pages: row["pages"]?.swiftlib_nilIfBlank,
            doi: doi,
            url: row["url"]?.swiftlib_nilIfBlank,
            abstract: row["abstract"]?.swiftlib_nilIfBlank,
            referenceType: referenceType
        )
    }

    private static func buildCrossRefAuthors(row: [String: String]) -> [AuthorName] {
        var authors: [AuthorName] = []

        // Organization-style authors (only have `name`).
        let orgNames = (row["authorsName"] ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for org in orgNames {
            authors.append(AuthorName.parse(org))
        }

        // Person-style authors (have parallel `given` + `family` arrays).
        let givens = (row["authorsGiven"] ?? "").components(separatedBy: "||")
        let families = (row["authorsFamily"] ?? "").components(separatedBy: "||")
        let personCount = max(givens.count, families.count)
        for i in 0..<personCount {
            let given = (i < givens.count ? givens[i] : "").trimmingCharacters(in: .whitespaces)
            let family = (i < families.count ? families[i] : "").trimmingCharacters(in: .whitespaces)
            guard !family.isEmpty || !given.isEmpty else { continue }
            if looksLikeCJKName(given: given, family: family) {
                // CrossRef often swaps given/family for romanized CJK names; correct that.
                authors.append(AuthorName(given: family, family: given))
            } else {
                authors.append(AuthorName(given: given, family: family))
            }
        }
        return authors
    }

    // MARK: - PMID → PubMed API

    /// Fetch metadata from PMID via NCBI esummary + (optional) efetch for abstract.
    public static func fetchFromPMID(_ pmid: String, forceRefresh: Bool = false) async throws -> Reference {
        let cacheKey = "pmid:\(pmid)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let urlString = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(pmid)&retmode=json\(pubmedIdentifyParams())"
            guard let url = URL(string: urlString) else {
                throw FetchError.invalidURL
            }

            var ref = try await performRequest(url: url) { data in
                try parsePubMedResponse(data, pmid: pmid)
            }

            // esummary doesn't include abstracts; efetch does. Try once, non-fatally.
            if (ref.abstract ?? "").isEmpty,
               let abs = try? await fetchAbstractFromPubMed(pmid: pmid) {
                ref.abstract = abs
            }

            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    /// Fetch abstract text from PubMed via efetch.
    public static func fetchAbstractFromPubMed(pmid: String) async throws -> String? {
        let urlString = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=\(pmid)&rettype=abstract&retmode=xml\(pubmedIdentifyParams())"
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await performRequest(url: url) { data in
                let parser = PubMedAbstractXMLParser(data: data)
                return parser.parse()
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    /// NCBI recommends every request carry `tool=` and `email=` parameters so
    /// they can contact the operator before rate-limiting or blocking.
    private static func pubmedIdentifyParams() -> String {
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = "&tool=SwiftLib"
        if !email.isEmpty, email.contains("@"),
           let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            components += "&email=\(encoded)"
        }
        return components
    }

    static func parsePubMedResponse(_ data: Data, pmid: String) throws -> Reference {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let article = result[pmid] as? [String: Any] else {
            throw FetchError.parseError
        }

        let title = (article["title"] as? String)?.trimmingCharacters(in: .init(charactersIn: ".")) ?? "Untitled"

        let authors: [AuthorName] = {
            guard let authorList = article["authors"] as? [[String: Any]] else { return [] }
            return authorList.compactMap { entry -> AuthorName? in
                guard let name = entry["name"] as? String else { return nil }
                return AuthorName.parse(name)
            }
        }()

        let year: Int? = {
            if let pubDate = article["pubdate"] as? String {
                let components = pubDate.components(separatedBy: " ")
                return components.first.flatMap { Int($0) }
            }
            return nil
        }()

        let articleIDs = article["articleids"] as? [[String: Any]] ?? []

        let doi: String? = {
            articleIDs.first(where: { ($0["idtype"] as? String) == "doi" })?["value"] as? String
        }()

        let pmcid: String? = {
            articleIDs.first(where: { ($0["idtype"] as? String) == "pmc" })?["value"] as? String
        }()

        return Reference(
            title: title,
            authors: authors,
            year: year,
            journal: article["source"] as? String,
            volume: article["volume"] as? String,
            issue: article["issue"] as? String,
            pages: article["pages"] as? String,
            doi: doi,
            referenceType: .journalArticle,
            pmid: pmid,
            pmcid: pmcid
        )
    }

    // MARK: - arXiv

    /// Fetch metadata from arXiv ID via arXiv Atom API.
    public static func fetchFromArXiv(_ arxivId: String, forceRefresh: Bool = false) async throws -> Reference {
        let cacheKey = "arxiv:\(arxivId)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let urlString = "https://export.arxiv.org/api/query?id_list=\(arxivId)&max_results=1"
            guard let url = URL(string: urlString) else {
                throw FetchError.invalidURL
            }

            let ref = try await performRequest(url: url) { data in
                try parseArXivResponse(data, arxivId: arxivId)
            }
            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    static func parseArXivResponse(_ data: Data, arxivId: String) throws -> Reference {
        let parser = ArXivXMLParser(data: data)
        guard var entry = parser.parse() else {
            throw FetchError.parseError
        }
        entry.url = "https://arxiv.org/abs/\(arxivId)"
        return entry
    }

    // MARK: - OpenAlex Full Fetch (adapter-driven)

    /// Fetch Reference + OpenAlexEnrichment from OpenAlex by DOI.
    /// Goes through the `openalex-work.byDoi` adapter — URL, field paths, and
    /// abstract reconstruction are all declared in JSON and can be repaired
    /// without a Swift rebuild when OpenAlex evolves its schema.
    public static func fetchFullFromOpenAlex(doi: String) async -> (Reference, OpenAlexEnrichment)? {
        let normalized = normalizedDOI(doi)
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openalex-work"),
              let route = adapter.routes["byDoi"] else {
            log.warning("openalex-work adapter missing; OpenAlex DOI fetch disabled")
            return nil
        }
        let urlString = SiteAdapterRuntime.expandURL(
            route.url,
            context: ["doi": normalized, "mailto": contactEmail]
        )
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }
            guard let row = rows.first else { return nil }
            return referenceAndEnrichmentFromOpenAlexRow(row)
        } catch {
            return nil
        }
    }

    /// Fetch Reference + OpenAlexEnrichment from OpenAlex by title.
    /// Same adapter infrastructure; `byTitle` route. Gated by title similarity
    /// so we never accept a completely unrelated first result.
    public static func fetchFullFromOpenAlex(title: String, maxResults: Int = 5) async -> (Reference, OpenAlexEnrichment)? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openalex-work"),
              let route = adapter.routes["byTitle"] else {
            return nil
        }
        let urlString = SiteAdapterRuntime.expandURL(
            route.url,
            context: [
                "title": title,
                "perPage": String(maxResults),
                "mailto": contactEmail
            ]
        )
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }

            // Strong-match pass (similarity ≥ 0.80).
            for row in rows {
                let fetchedTitle = row["title"] ?? ""
                if MetadataResolution.titleSimilarity(title, fetchedTitle) >= 0.80 {
                    return referenceAndEnrichmentFromOpenAlexRow(row)
                }
            }
            // Weak-match fallback (≥ 0.55) for first result only.
            if let first = rows.first {
                let fetchedTitle = first["title"] ?? ""
                if MetadataResolution.titleSimilarity(title, fetchedTitle) >= 0.55 {
                    return referenceAndEnrichmentFromOpenAlexRow(first)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Translate an OpenAlex adapter row (`[String: String]`) to our domain
    /// types. Exposed internally so fixture-based tests can exercise the
    /// mapping without hitting the network.
    static func referenceAndEnrichmentFromOpenAlexRow(
        _ row: [String: String]
    ) -> (Reference, OpenAlexEnrichment) {
        let title = row["title"] ?? "Untitled"
        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parse(String($0)) }
        let year = row["year"].flatMap { Int($0.prefix(4)) }

        // Prefer the template-rendered "firstPage-lastPage" when both were
        // present; otherwise fall back to firstPage alone.
        let pages: String? = {
            if let both = row["pagesWhenBothPresent"]?.swiftlib_nilIfBlank { return both }
            return row["firstPage"]?.swiftlib_nilIfBlank
        }()

        let referenceType: ReferenceType = {
            switch row["type"] {
            case "journal-article", "article": return .journalArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "preprint", "posted-content": return .preprint
            case "report": return .report
            case "dataset": return .dataset
            default: return .journalArticle
            }
        }()

        let ref = Reference(
            title: title,
            authors: authors,
            year: year,
            journal: row["journal"]?.swiftlib_nilIfBlank,
            volume: row["volume"]?.swiftlib_nilIfBlank,
            issue: row["issue"]?.swiftlib_nilIfBlank,
            pages: pages,
            doi: row["doi"]?.swiftlib_nilIfBlank,
            abstract: row["abstract"]?.swiftlib_nilIfBlank,
            referenceType: referenceType,
            metadataSource: .openAlex
        )

        // Re-compose funding entries as "Funder (AwardID)" pairs when both sides are present.
        let funders = (row["grantFunders"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true).map(String.init)
        let awards = (row["grantAwards"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true).map(String.init)
        var fundingInfo: [String] = []
        for (i, funder) in funders.enumerated() {
            if i < awards.count, !awards[i].isEmpty {
                fundingInfo.append("\(funder) (\(awards[i]))")
            } else {
                fundingInfo.append(funder)
            }
        }

        let enrichment = OpenAlexEnrichment(
            keywords: (row["conceptNames"] ?? "")
                .split(separator: "|", omittingEmptySubsequences: true).map(String.init),
            topics: (row["topicNames"] ?? "")
                .split(separator: "|", omittingEmptySubsequences: true).map(String.init),
            isOpenAccess: row["isOpenAccess"] == "true",
            oaUrl: row["oaUrl"]?.swiftlib_nilIfBlank,
            citedByCount: row["citedByCount"].flatMap(Int.init) ?? 0,
            fundingInfo: fundingInfo,
            referenceType: referenceType,
            openAlexId: row["openAlexId"]?.swiftlib_nilIfBlank,
            abstract: row["abstract"]?.swiftlib_nilIfBlank
        )
        return (ref, enrichment)
    }

    /// Build a Reference from an OpenAlex work JSON object.
    static func buildReferenceFromOpenAlexWork(_ work: [String: Any]) -> Reference {
        let fetchedTitle = work["title"] as? String ?? "Untitled"
        let year = work["publication_year"] as? Int

        let authors: [AuthorName] = {
            guard let authorships = work["authorships"] as? [[String: Any]] else { return [] }
            return authorships.compactMap { authorship -> AuthorName? in
                guard let author = authorship["author"] as? [String: Any],
                      let name = author["display_name"] as? String else { return nil }
                return AuthorName.parse(name)
            }
        }()

        let doi: String? = {
            guard let raw = work["doi"] as? String else { return nil }
            if let range = raw.range(of: "doi.org/") {
                return String(raw[range.upperBound...])
            }
            return raw
        }()

        let journal: String? = {
            guard let location = work["primary_location"] as? [String: Any],
                  let source = location["source"] as? [String: Any] else { return nil }
            return source["display_name"] as? String
        }()

        let biblio = work["biblio"] as? [String: Any]
        let volume = biblio?["volume"] as? String
        let issue = biblio?["issue"] as? String
        let firstPage = biblio?["first_page"] as? String
        let lastPage = biblio?["last_page"] as? String
        let pages: String? = {
            guard let f = firstPage else { return nil }
            if let l = lastPage, l != f { return "\(f)-\(l)" }
            return f
        }()

        let abstract = reconstructAbstract(fromInvertedIndex: work["abstract_inverted_index"] as? [String: [Int]])

        let referenceType: ReferenceType = {
            switch work["type"] as? String {
            case "journal-article", "article": return .journalArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "preprint", "posted-content": return .preprint
            case "report": return .report
            default: return .journalArticle
            }
        }()

        return Reference(
            title: fetchedTitle,
            authors: authors,
            year: year,
            journal: journal,
            volume: volume,
            issue: issue,
            pages: pages,
            doi: doi,
            abstract: abstract,
            referenceType: referenceType,
            metadataSource: .openAlex
        )
    }

    // MARK: - OpenAlex Title Search (full metadata)

    /// Search OpenAlex by title and return a full Reference (for articles without identifiers).
    /// Gated by title similarity (≥0.80 strong, ≥0.55 weak fallback) so we never accept a
    /// completely unrelated first result.
    public static func fetchFromOpenAlexByTitle(_ title: String) async throws -> Reference? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "https://api.openalex.org/works?search=\(encoded)&select=id,doi,title,authorships,publication_year,primary_location,biblio,abstract_inverted_index,type&per-page=3\(politeMailtoQuery)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let results: [[String: Any]] = try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    throw FetchError.notFound
                }
                return results
            }

            for work in results {
                let fetchedTitle = work["title"] as? String ?? ""
                let score = MetadataResolution.titleSimilarity(title, fetchedTitle)
                if score >= 0.80 {
                    return buildReferenceFromOpenAlexWork(work)
                }
            }
            if let first = results.first {
                let score = MetadataResolution.titleSimilarity(title, first["title"] as? String ?? "")
                if score >= 0.55 {
                    return buildReferenceFromOpenAlexWork(first)
                }
            }
            return nil
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - ISBN → Open Library + Google Books

    /// Fetch book metadata from ISBN via Open Library (primary) with Google Books fallback.
    /// Also tries the ISBN-10 ↔ ISBN-13 alternate form if the primary form fails.
    public static func fetchFromISBN(_ isbn: String, forceRefresh: Bool = false) async throws -> Reference {
        let cacheKey = "isbn:\(isbn)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let candidates = isbnCandidates(for: isbn)

            for candidate in candidates {
                if let ref = try? await fetchFromOpenLibrary(isbn: candidate) {
                    storeInBothCaches(ref, for: cacheKey)
                    return ref
                }
            }
            for candidate in candidates {
                if let ref = try? await fetchFromGoogleBooks(isbn: candidate) {
                    storeInBothCaches(ref, for: cacheKey)
                    return ref
                }
            }
            throw FetchError.notFound
        }
    }

    /// Return the list of ISBN variants worth trying. Primary form first,
    /// followed by the 10↔13 conversion if applicable.
    private static func isbnCandidates(for isbn: String) -> [String] {
        var out = [isbn]
        if isbn.count == 13, let ten = isbn13To10(isbn) { out.append(ten) }
        if isbn.count == 10, let thirteen = isbn10To13(isbn) { out.append(thirteen) }
        return out
    }

    // MARK: - Open Library / Google Books (adapter-driven)

    private static func fetchFromOpenLibrary(isbn: String) async throws -> Reference? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openlibrary-book"),
              let route = adapter.routes["byIsbn"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["isbn": isbn])
        guard let url = URL(string: urlString) else { return nil }
        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                // `itemsPath` is templated as `ISBN:{isbn}` — context must be passed through.
                let rows = (try? SiteAdapterRuntime.extractJSON(
                    route: route,
                    data: data,
                    context: ["isbn": isbn]
                )) ?? []
                guard let row = rows.first else { return nil as Reference? }
                return referenceFromOpenLibraryIsbnRow(row, isbn: isbn)
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    private static func fetchFromGoogleBooks(isbn: String) async throws -> Reference? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "google-books-volume"),
              let route = adapter.routes["byIsbn"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["isbn": isbn])
        guard let url = URL(string: urlString) else { return nil }
        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                let rows = (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
                guard let row = rows.first else { return nil as Reference? }
                return referenceFromGoogleBooksRow(row, fallbackISBN: isbn)
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - Book adapter row → Reference mappers

    /// Map an Open Library `byIsbn` / `byTitle` adapter row to `Reference`.
    static func referenceFromOpenLibraryIsbnRow(_ row: [String: String], isbn: String) -> Reference {
        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parse(String($0)) }

        let title: String = {
            if let sub = row["subtitle"]?.swiftlib_nilIfBlank,
               let main = row["title"]?.swiftlib_nilIfBlank {
                return "\(main): \(sub)"
            }
            return row["title"]?.swiftlib_nilIfBlank ?? "Untitled"
        }()

        let publisher: String? = (row["publisher"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .first.map(String.init)

        return Reference(
            title: title,
            authors: authors,
            year: row["year"].flatMap(Int.init),
            url: row["url"]?.swiftlib_nilIfBlank,
            abstract: row["description"]?.swiftlib_nilIfBlank,
            referenceType: .book,
            publisher: publisher,
            isbn: row["isbn13"]?.swiftlib_nilIfBlank
                ?? row["isbn10"]?.swiftlib_nilIfBlank
                ?? isbn,
            numberOfPages: row["pageCount"]?.swiftlib_nilIfBlank
        )
    }

    /// Map a Google Books `byIsbn` / `byTitle` adapter row to `Reference`.
    /// Picks ISBN_13 over ISBN_10; falls back to caller-supplied ISBN.
    static func referenceFromGoogleBooksRow(
        _ row: [String: String],
        fallbackISBN: String? = nil
    ) -> Reference {
        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parse(String($0)) }

        let title: String = {
            if let full = row["titleWithSubtitle"]?.swiftlib_nilIfBlank { return full }
            return row["title"]?.swiftlib_nilIfBlank ?? "Untitled"
        }()

        // Pick best identifier from parallel `industryIdentifiers` arrays.
        let bestISBN: String? = {
            let types = (row["identifierTypes"] ?? "").components(separatedBy: "||")
            let values = (row["identifierValues"] ?? "").components(separatedBy: "||")
            let pairs = zip(types, values)
            if let match = pairs.first(where: { $0.0 == "ISBN_13" }), !match.1.isEmpty { return match.1 }
            if let match = pairs.first(where: { $0.0 == "ISBN_10" }), !match.1.isEmpty { return match.1 }
            return fallbackISBN
        }()

        return Reference(
            title: title,
            authors: authors,
            year: row["year"].flatMap(Int.init),
            abstract: row["description"]?.swiftlib_nilIfBlank,
            referenceType: .book,
            publisher: row["publisher"]?.swiftlib_nilIfBlank,
            isbn: bestISBN,
            numberOfPages: row["pageCount"]?.swiftlib_nilIfBlank
        )
    }

    // MARK: - Book Title Search

    /// Search for book metadata by title when no ISBN is available.
    /// For Chinese titles: tries Douban first, then falls back to Open Library / Google Books.
    /// For non-Chinese titles: tries Open Library first, then Google Books.
    /// Returns nil if no result meets the title similarity threshold.
    public static func searchBookByTitle(_ title: String, forceRefresh: Bool = false) async throws -> Reference? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let cacheKey = "book-title:\(normalized.lowercased())"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedOptionalFetch(key: cacheKey) {
            // For Chinese titles, Douban is the most reliable source
            if MetadataResolution.containsHanCharacters(normalized) {
                if let ref = try? await searchDoubanBookByTitle(normalized) {
                    storeInBothCaches(ref, for: cacheKey)
                    return ref
                }
            }

            if let ref = try? await searchOpenLibraryByTitle(normalized) {
                storeInBothCaches(ref, for: cacheKey)
                return ref
            }

            if let ref = try? await searchGoogleBooksByTitle(normalized) {
                storeInBothCaches(ref, for: cacheKey)
                return ref
            }

            return nil
        }
    }

    /// Search Douban Books by title.
    ///
    /// This function is now a thin orchestrator: **all** URL templates, JSON
    /// paths, filters, and HTML regexes live in `Resources/adapters/douban-book.json`
    /// and are executed via `SiteAdapterRuntime`. When the upstream schema
    /// drifts (which Douban does on a ~yearly cadence) we can ship a fix by
    /// editing the JSON — no Swift rebuild — and the canary harness plus
    /// `scripts/canary.sh` will flag the drift before users hit it.
    ///
    /// Returns nil silently on network failure so non-CN users (where Douban
    /// is often unreachable) fall through to Open Library / Google Books.
    public static func searchDoubanBookByTitle(_ title: String) async throws -> Reference? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "douban-book") else {
            log.warning("douban-book adapter missing; Douban search disabled")
            return nil
        }
        guard let searchRoute = adapter.routes["search"] else { return nil }

        let searchURLString = SiteAdapterRuntime.expandURL(searchRoute.url, context: ["query": normalized])
        guard let searchURL = URL(string: searchURLString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: searchRoute,
                url: searchURL
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: searchRoute, data: data)) ?? []
            }

            for row in rows {
                guard let resultTitle = row["title"], !resultTitle.isEmpty else { continue }
                let similarity = MetadataResolution.titleSimilarity(normalized, resultTitle)
                guard similarity >= 0.55 else { continue }

                let authors = parseDoubanAuthors(row["authorRaw"] ?? "")
                let year = row["year"].flatMap { Int($0.prefix(4)) }
                let subjectUrl = row["subjectUrl"]
                    ?? row["subjectId"].map { "https://book.douban.com/subject/\($0)/" }

                var ref = Reference(
                    title: resultTitle,
                    authors: authors,
                    year: year,
                    url: subjectUrl,
                    referenceType: .book,
                    metadataSource: .douban,
                    publisher: row["publisher"]?.swiftlib_nilIfBlank,
                    isbn: row["isbn"]?.swiftlib_nilIfBlank
                )

                // Follow detail route for ISBN / publisher / pages / abstract.
                if let subjectUrl,
                   let detailRoute = adapter.routes["detail"],
                   let detail = try? await fetchDoubanDetail(subjectUrl: subjectUrl, route: detailRoute) {
                    mergeDoubanDetail(&ref, detail: detail)
                }

                return ref
            }
            return nil
        } catch {
            log.debug("Douban search failed (graceful): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func parseDoubanAuthors(_ raw: String) -> [AuthorName] {
        guard !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: CharacterSet(charactersIn: "/／,，"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Strip Chinese role suffixes: "刘建康 编" → "刘建康".
            .map { $0.replacingOccurrences(of: #"\s*(编|著|译|等|主编)$"#, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { AuthorName.parse($0) }
    }

    private static func mergeDoubanDetail(_ ref: inout Reference, detail: [String: String]) {
        if ref.isbn?.swiftlib_nilIfBlank == nil,
           let isbn = detail["isbn"]?.swiftlib_nilIfBlank {
            ref.isbn = isbn
        }
        if ref.publisher?.swiftlib_nilIfBlank == nil,
           let publisher = detail["publisher"]?.swiftlib_nilIfBlank {
            ref.publisher = publisher
        }
        if ref.year == nil, let yearStr = detail["year"], let year = Int(yearStr.prefix(4)) {
            ref.year = year
        }
        if ref.numberOfPages?.swiftlib_nilIfBlank == nil,
           let pages = detail["pages"]?.swiftlib_nilIfBlank {
            ref.numberOfPages = pages
        }
        if ref.authors.isEmpty, let authorRaw = detail["authorRaw"]?.swiftlib_nilIfBlank {
            ref.authors = parseDoubanAuthors(authorRaw)
        }
        if (ref.abstract ?? "").isEmpty, let abs = detail["abstract"]?.swiftlib_nilIfBlank {
            ref.abstract = abs
        }
    }

    /// Fetch and parse a Douban subject detail page via the adapter runtime.
    /// Returns the raw extracted `[String: String]` row — callers map these
    /// strings onto `Reference` fields via `mergeDoubanDetail(_:detail:)`.
    static func fetchDoubanDetail(
        subjectUrl: String,
        route: SiteAdapterDefinition.Route
    ) async throws -> [String: String]? {
        let expanded = SiteAdapterRuntime.expandURL(route.url, context: ["subjectUrl": subjectUrl])
        // Special-case: `{subjectUrl}` is itself a full URL, not a query param.
        // `expandURL` percent-encodes it; reverse that one key.
        let finalURLString = route.url == "{subjectUrl}" ? subjectUrl : expanded
        guard let url = URL(string: finalURLString) else { return nil }

        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                guard let html = String(data: data, encoding: .utf8) else { return nil as [String: String]? }
                return (try? SiteAdapterRuntime.extractHTML(route: route, html: html)) ?? [:]
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - Douban Detail Page Parser (test-facing shim)

    /// Simple struct exposed to tests. Internal production code uses the
    /// adapter runtime's `[String: String]` rows directly — this shim exists
    /// so the existing fixture-based parser tests keep compiling.
    struct DoubanDetail: Sendable, Equatable {
        var isbn: String?
        var publisher: String?
        var publisherPlace: String?
        var year: Int?
        var pages: String?
        var authors: [AuthorName] = []
        var abstract: String?
    }

    /// Parse the Douban `#info` block out of the detail page HTML by
    /// delegating to the `douban-book` adapter's `detail` route.
    /// Keeps the old API stable for existing tests / external callers.
    static func parseDoubanDetailHTML(_ html: String) -> DoubanDetail {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "douban-book"),
              let route = adapter.routes["detail"],
              let extracted = try? SiteAdapterRuntime.extractHTML(route: route, html: html) else {
            return DoubanDetail()
        }
        var detail = DoubanDetail()
        detail.isbn = extracted["isbn"]?.swiftlib_nilIfBlank
        detail.publisher = extracted["publisher"]?.swiftlib_nilIfBlank
        detail.pages = extracted["pages"]?.swiftlib_nilIfBlank
        detail.abstract = extracted["abstract"]?.swiftlib_nilIfBlank
        if let yearStr = extracted["year"], let year = Int(yearStr.prefix(4)) {
            detail.year = year
        }
        if let authorRaw = extracted["authorRaw"], !authorRaw.isEmpty {
            detail.authors = parseDoubanAuthors(authorRaw)
        }
        return detail
    }

    private static func searchOpenLibraryByTitle(_ title: String) async throws -> Reference? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://openlibrary.org/search.json?title=\(encoded)&limit=3&fields=key,title,author_name,first_publish_year,isbn,publisher,number_of_pages_median") else { return nil }

        let firstDoc: [String: Any]? = try? await performRequest(url: url) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["docs"] as? [[String: Any]],
                  let firstDoc = docs.first else {
                return nil as [String: Any]?
            }
            return firstDoc
        }

        guard let firstDoc,
              let resultTitle = firstDoc["title"] as? String,
              bookTitleSimilarity(title, resultTitle) >= 0.5 else { return nil }

        if let isbns = firstDoc["isbn"] as? [String],
           let bestISBN = isbns.first(where: { $0.count == 13 }) ?? isbns.first(where: { $0.count == 10 }),
           let ref = try? await fetchFromOpenLibrary(isbn: bestISBN) {
            return ref
        }

        let authors: [AuthorName] = {
            guard let names = firstDoc["author_name"] as? [String] else { return [] }
            return names.map { AuthorName.parse($0) }
        }()
        let year = firstDoc["first_publish_year"] as? Int
        let publisher = (firstDoc["publisher"] as? [String])?.first
        let numberOfPages = (firstDoc["number_of_pages_median"] as? Int).map(String.init)
        return Reference(
            title: resultTitle,
            authors: authors,
            year: year,
            referenceType: .book,
            publisher: publisher,
            numberOfPages: numberOfPages
        )
    }

    private static func searchGoogleBooksByTitle(_ title: String) async throws -> Reference? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=intitle:\(encoded)&maxResults=1") else { return nil }

        return try? await performRequest(url: url) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let first = items.first,
                  let volumeInfo = first["volumeInfo"] as? [String: Any],
                  let resultTitle = volumeInfo["title"] as? String,
                  bookTitleSimilarity(title, resultTitle) >= 0.5 else {
                return nil as Reference?
            }

            let authors: [AuthorName] = {
                guard let authorList = volumeInfo["authors"] as? [String] else { return [] }
                return authorList.map { AuthorName.parse($0) }
            }()
            let year: Int? = {
                guard let publishedDate = volumeInfo["publishedDate"] as? String else { return nil }
                return Int(publishedDate.prefix(4))
            }()
            let numberOfPages: String? = {
                guard let n = volumeInfo["pageCount"] as? Int else { return nil }
                return String(n)
            }()
            let isbn: String? = {
                guard let identifiers = volumeInfo["industryIdentifiers"] as? [[String: Any]] else { return nil }
                let isbn13 = identifiers.first(where: { $0["type"] as? String == "ISBN_13" })?["identifier"] as? String
                let isbn10 = identifiers.first(where: { $0["type"] as? String == "ISBN_10" })?["identifier"] as? String
                return isbn13 ?? isbn10
            }()
            return Reference(
                title: resultTitle,
                authors: authors,
                year: year,
                abstract: volumeInfo["description"] as? String,
                referenceType: .book,
                publisher: volumeInfo["publisher"] as? String,
                isbn: isbn,
                numberOfPages: numberOfPages
            )
        }
    }

    /// Word-overlap Jaccard similarity between two titles (0–1).
    private static func bookTitleSimilarity(_ a: String, _ b: String) -> Double {
        let tokenize: (String) -> Set<String> = { s in
            Set(
                s.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .flatMap { $0.components(separatedBy: .punctuationCharacters) }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.count > 1 }
            )
        }
        let wordsA = tokenize(a)
        let wordsB = tokenize(b)
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let intersection = Double(wordsA.intersection(wordsB).count)
        let union = Double(wordsA.union(wordsB).count)
        return intersection / union
    }

    // MARK: - Unified Fetch

    /// Auto-detect identifier and fetch metadata.
    public static func fetch(from text: String) async throws -> Reference {
        guard let identifier = extractIdentifier(from: text) else {
            throw FetchError.unrecognizedIdentifier
        }

        switch identifier {
        case .doi(let doi):   return try await fetchFromDOI(doi)
        case .pmid(let pmid): return try await fetchFromPMID(pmid)
        case .arxiv(let id):  return try await fetchFromArXiv(id)
        case .isbn(let isbn): return try await fetchFromISBN(isbn)
        }
    }

    // MARK: - CJK Author Name Correction

    /// Detect when CrossRef has swapped given/family for a CJK author name.
    /// CrossRef often returns `{"given":"Wu","family":"Haoyun"}` for Chinese authors
    /// when the correct mapping is `given:"Haoyun", family:"Wu"` (family name is the
    /// shorter, single-character-like segment for Chinese names romanized).
    private static func looksLikeCJKName(given: String, family: String) -> Bool {
        let g = given.trimmingCharacters(in: .whitespaces)
        let f = family.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, !f.isEmpty else { return false }
        let bothAscii = g.allSatisfy { $0.isASCII } && f.allSatisfy { $0.isASCII }
        guard bothAscii else { return false }
        let gWords = g.components(separatedBy: " ").filter { !$0.isEmpty }
        return gWords.count == 1 && g.count <= 3 && f.count > g.count
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

// MARK: - arXiv Atom XML Parser

private class ArXivXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var result: Reference?

    private var currentElement = ""
    private var currentText = ""
    private var title = ""
    private var abstract = ""
    private var authors: [AuthorName] = []
    private var currentAuthor = ""
    private var published = ""
    private var doi: String?
    private var inEntry = false
    private var inAuthor = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> Reference? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "entry" { inEntry = true }
        if elementName == "author" { inAuthor = true; currentAuthor = "" }
        if elementName == "link" && inEntry {
            if attributes["title"] == "doi", let href = attributes["href"] {
                if let range = href.range(of: "doi.org/") {
                    doi = String(href[range.upperBound...])
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inEntry {
            switch elementName {
            case "title":
                title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            case "summary":
                abstract = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            case "name":
                if inAuthor { currentAuthor = text }
            case "author":
                inAuthor = false
                if !currentAuthor.isEmpty { authors.append(AuthorName.parse(currentAuthor)) }
            case "published":
                published = text
            case "entry":
                inEntry = false
                let year = Int(published.prefix(4))
                result = Reference(
                    title: title,
                    authors: authors,
                    year: year,
                    doi: doi,
                    url: nil,
                    abstract: abstract,
                    referenceType: .journalArticle
                )
            default:
                break
            }
        }

        currentElement = ""
    }
}

// MARK: - PubMed efetch Abstract XML Parser

/// Parses the subset of PubMed's efetch XML that we care about: the concatenated
/// `AbstractText` content. Multiple `AbstractText` elements (labelled abstracts)
/// are joined with a space, prefixed by their Label when present.
private final class PubMedAbstractXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var abstractParts: [String] = []

    private var currentText = ""
    private var currentLabel = ""
    private var inAbstractText = false

    init(data: Data) { self.data = data }

    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        guard !abstractParts.isEmpty else { return nil }
        let joined = abstractParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentText = ""
        if elementName == "AbstractText" {
            inAbstractText = true
            currentLabel = attributes["Label"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inAbstractText { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "AbstractText" {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !currentLabel.isEmpty {
                    abstractParts.append("\(currentLabel): \(trimmed)")
                } else {
                    abstractParts.append(trimmed)
                }
            }
            inAbstractText = false
            currentLabel = ""
        }
    }
}
