import Foundation

/// Declarative description of how to call and parse a specific metadata source.
///
/// The idea: extraction rules (URL templates, JSON paths, HTML regexes, filters)
/// that used to live as hard-coded strings inside Swift functions become **data**
/// loaded from a JSON file under `Resources/adapters/`.
///
/// When a source changes its schema (see: Douban's `/j/subject_suggest`
/// switching `"type": "book"` → `"type": "b"`), we can fix it by editing the
/// JSON — no Swift rebuild, no App Store release, no hotfix regex scramble —
/// and optionally by having an AI agent regenerate the JSON after visiting
/// the live URL with a headless browser.
///
/// The runtime is intentionally minimal: JSON-path–lite + regex, enough for
/// 95% of bibliographic scraping needs. See `SiteAdapterRuntime`.
public struct SiteAdapterDefinition: Codable, Hashable, Sendable {

    // MARK: - Metadata

    public let id: String
    public let schemaVersion: Int
    public let displayName: String?
    public let description: String?

    // MARK: - Routes

    public let routes: [String: Route]

    // MARK: - Canary probes (for monitoring)

    public let canary: [CanaryCase]?

    public struct Route: Codable, Hashable, Sendable {
        /// URL template. `{placeholder}` substrings are replaced at runtime from
        /// the caller's context (`query`, `subjectUrl`, etc.).
        public let url: String
        public let headers: [String: String]?
        public let timeoutSeconds: Double?
        /// Which transport executor to use. Defaults to `.http` — plain
        /// `URLSession` + `SiteAdapterRuntime`. `.webView` is reserved for
        /// subscription-gated sources that need a cookie-authenticated
        /// `WKWebView` session (see Docs/ADAPTERS.md § 5); the concrete
        /// executor is provided by the host app target.
        public let kind: RouteKind?
        /// When true, the UI should prompt the user to SSO-authenticate before
        /// the first request. Only meaningful for `kind == .webView`.
        public let requiresAuthenticatedSession: Bool?
        public let extract: Extract
    }

    public enum RouteKind: String, Codable, Hashable, Sendable {
        case http
        case webView
    }

    /// Extraction pipeline for a single response. A route produces either:
    /// - multiple rows (kind = `json`), suitable for search-result lists, or
    /// - a single row (kind = `html`), suitable for detail pages.
    public struct Extract: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case json
            case html
        }

        public let kind: Kind

        // --- JSON mode ---

        /// Dot-path to the array of items to iterate. `"$"` means the root
        /// itself is already an array. Omit in HTML mode.
        public let itemsPath: String?

        /// Optional per-item predicate to skip rows that don't match (e.g.
        /// `type ∈ {"b", "book"}` for Douban).
        public let itemFilter: ItemFilter?

        // --- Shared field map ---

        public let fields: [String: Field]
    }

    public struct ItemFilter: Codable, Hashable, Sendable {
        public let field: String
        public let equals: [String]?
    }

    /// A named output field. At least one of `paths`, `strategies`, or `template`
    /// is populated.
    ///
    /// Evaluation order:
    /// 1. If `template` is set → render `{path}` placeholders against the item
    ///    and return (elided to `nil` if any `elideIfMissing` path is missing).
    /// 2. Otherwise, for JSON: iterate `paths`, first non-empty resolved value
    ///    wins. Arrays are joined using `separator` (default `"|"`). Raw
    ///    resolved value is first fed to `postProcess` (if any), then
    ///    stringified, then fed to `transform`.
    /// 3. For HTML: iterate `strategies`, first non-empty match wins.
    public struct Field: Codable, Hashable, Sendable {
        /// JSON-mode: list of candidate dot-paths, first non-empty wins.
        /// Supports `foo.bar`, `foo[0]`, and the array wildcard `foo[*].bar`.
        public let paths: [String]?
        /// HTML-mode: list of extraction strategies, first non-empty wins.
        public let strategies: [HTMLStrategy]?
        /// Computed-mode: template string with `{json.path}` placeholders
        /// resolved against the same item. Example: `"{biblio.first_page}-{biblio.last_page}"`.
        public let template: String?
        /// When in `template` mode, if any of these paths are missing from the
        /// item, the whole field is elided (returns `nil`). Useful to avoid
        /// producing incomplete strings like "101-" when `last_page` is absent.
        public let elideIfMissing: [String]?
        /// Join separator when a resolved JSON value is itself an array
        /// (e.g. from a `[*]` wildcard path). Default `"|"`.
        public let separator: String?
        /// Named string-level post-processing:
        /// `prefix4Int` | `upper` | `lower` | `trim` | `stripDoiOrgPrefix`.
        public let transform: String?
        /// Named raw-value post-processing that operates on the Any value
        /// BEFORE stringification. Currently: `reconstructInvertedIndex`
        /// (for OpenAlex `abstract_inverted_index` → plain text).
        public let postProcess: String?
    }

    public struct HTMLStrategy: Codable, Hashable, Sendable {
        public let kind: Kind
        public let pattern: String
        public let group: Int
        public let stripTags: Bool?

        public enum Kind: String, Codable, Sendable {
            case regex
        }
    }

    /// A known-good extraction fixture used by the canary test harness.
    public struct CanaryCase: Codable, Hashable, Sendable {
        public let name: String
        /// Explicit route name (e.g. "byDoi", "byTitle", "search").
        /// When nil, the harness falls back to a priority list.
        /// Required when the adapter defines multiple candidate routes.
        public let route: String?
        /// Shorthand: value is passed to the chosen route as `{query}`.
        /// Kept for back-compat; prefer `context` for new adapters.
        public let searchQuery: String?
        /// Input for the `detail` route (bypasses search).
        public let subjectUrl: String?
        /// Explicit placeholder → value map for the route's URL template.
        /// Example: `{"doi": "10.1038/nature14539"}` — works even when the
        /// adapter URL uses a non-`{query}` placeholder.
        public let context: [String: String]?
        /// Expected subset of the route output for the top match.
        public let expectSearch: [String: String]?
        /// Expected subset of the `detail` route output.
        public let expectDetail: [String: String]?
    }
}
