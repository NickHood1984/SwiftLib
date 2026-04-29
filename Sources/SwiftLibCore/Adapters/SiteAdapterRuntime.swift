import Foundation

/// Stateless interpreter for `SiteAdapterDefinition.Route`.
///
/// Deliberately tiny API surface so this layer is easy to keep tested and
/// easy for an auto-repair pipeline to reason about:
///
/// - `expandURL(_:context:)` → substitute `{placeholder}` tokens
/// - `extractJSON(route:data:)` → return rows as `[String: String]`
/// - `extractHTML(route:html:)` → return single row as `[String: String]`
public enum SiteAdapterRuntime {

    public enum RuntimeError: Error, Equatable {
        case invalidJSON
        case itemsPathMissing
        case wrongRouteKind(expected: SiteAdapterDefinition.Extract.Kind, got: SiteAdapterDefinition.Extract.Kind)
    }

    // MARK: - URL expansion

    /// Replace every `{key}` in `template` with `context[key]`.
    ///
    /// Encoding convention:
    /// - If `key` ends in "Url" / "URL" (case-insensitive), the value is
    ///   substituted verbatim — used for cases where the placeholder IS a full
    ///   URL (e.g. Douban `detail.url = "{subjectUrl}"`).
    /// - Otherwise the value is percent-encoded for URL query usage.
    ///
    /// Empty values of the form `&key=` are swept from the tail of the URL so
    /// an optional mailto placeholder doesn't leave dangling query noise.
    /// Unknown placeholders are left intact so a caller can detect them.
    public static func expandURL(_ template: String, context: [String: String]) -> String {
        var out = template
        for (key, value) in context {
            let needsEncoding = !key.lowercased().hasSuffix("url")
            let substituted: String
            if needsEncoding {
                substituted = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            } else {
                substituted = value
            }
            out = out.replacingOccurrences(of: "{\(key)}", with: substituted)
        }
        // Clean up empty query params like `&mailto=` at end-of-URL or before
        // another `&`/`#`, so optional placeholders don't pollute the URL.
        out = out.replacingOccurrences(of: #"&[A-Za-z_][A-Za-z0-9_.-]*=(?=&|$|#)"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\?&"#, with: "?", options: .regularExpression)
        return out
    }

    // MARK: - JSON extraction

    public static func extractJSON(
        route: SiteAdapterDefinition.Route,
        data: Data,
        context: [String: String] = [:]
    ) throws -> [[String: String]] {
        guard route.extract.kind == .json else {
            throw RuntimeError.wrongRouteKind(expected: .json, got: route.extract.kind)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw RuntimeError.invalidJSON
        }

        let items: [Any]
        // Allow `{placeholder}` in itemsPath — Open Library's `/api/books`
        // returns an object keyed by `ISBN:<input>` so the path depends on
        // the request context.
        let rawItemsPath = route.extract.itemsPath ?? "$"
        let itemsPath = expandPlaceholders(rawItemsPath, context: context)
        if let resolved = resolvePath(root: root, path: itemsPath) {
            if let array = resolved as? [Any] {
                items = array
            } else {
                items = [resolved]
            }
        } else {
            throw RuntimeError.itemsPathMissing
        }

        var out: [[String: String]] = []
        let filter = route.extract.itemFilter

        for item in items {
            if let filter {
                let value = stringify(resolvePath(root: item, path: filter.field) ?? "")
                if let equals = filter.equals, !equals.isEmpty, !equals.contains(value) {
                    continue
                }
            }
            var row: [String: String] = [:]
            for (name, field) in route.extract.fields {
                if let value = evaluateJSONField(item: item, field: field) {
                    row[name] = value
                }
            }
            out.append(row)
        }
        return out
    }

    // MARK: - JSON field evaluation

    /// Evaluate a single field against a single item. Handles (in order):
    /// template > paths > nil.
    private static func evaluateJSONField(
        item: Any,
        field: SiteAdapterDefinition.Field
    ) -> String? {
        // 1. Template mode.
        if let template = field.template {
            return renderTemplate(template, against: item, elideIfMissing: field.elideIfMissing)
                .flatMap { applyTransform($0, transform: field.transform) }
        }

        // 2. Paths mode (with optional postProcess before stringify).
        guard let paths = field.paths else { return nil }
        for path in paths {
            guard let resolved = resolvePath(root: item, path: path) else { continue }

            // 2a. postProcess takes precedence when configured — it consumes
            // the raw JSON value (e.g. a [String: [Int]] inverted index).
            if let pp = field.postProcess,
               let processed = applyPostProcess(resolved, name: pp) {
                return applyTransform(processed, transform: field.transform)
            }

            // 2b. Scalar or array: stringify, arrays are joined.
            let stringified = stringifyValueOrArray(
                resolved,
                separator: field.separator ?? "|"
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stringified.isEmpty {
                return applyTransform(stringified, transform: field.transform)
            }
        }
        return nil
    }

    /// Render `{json.path}` placeholders from `template` against `item`.
    /// Returns `nil` if any path in `elideIfMissing` is absent, OR if the
    /// rendered string collapses to empty whitespace.
    private static func renderTemplate(
        _ template: String,
        against item: Any,
        elideIfMissing: [String]?
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\{([^}]+)\}"#) else {
            return template
        }
        let ns = NSMutableString(string: template)
        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches.reversed() {
            guard let inner = Range(match.range(at: 1), in: template) else { continue }
            let path = String(template[inner])
            let resolved = resolvePath(root: item, path: path)
            if resolved == nil, elideIfMissing?.contains(path) == true {
                return nil
            }
            let substitution = resolved.map { stringify($0) } ?? ""
            ns.replaceCharacters(in: match.range, with: substitution)
        }
        let out = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private static func stringifyValueOrArray(_ value: Any, separator: String) -> String {
        if let arr = value as? [Any] {
            return arr.map { stringify($0) }.filter { !$0.isEmpty }.joined(separator: separator)
        }
        return stringify(value)
    }

    /// Generic `{key}` → `context[key]` substitution. Used by `itemsPath`
    /// templating (unlike `expandURL`, this one doesn't percent-encode —
    /// paths contain user-supplied IDs as-is).
    private static func expandPlaceholders(_ template: String, context: [String: String]) -> String {
        guard !context.isEmpty, template.contains("{") else { return template }
        var out = template
        for (key, value) in context {
            out = out.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return out
    }

    // MARK: - HTML extraction

    public static func extractHTML(
        route: SiteAdapterDefinition.Route,
        html: String
    ) throws -> [String: String] {
        guard route.extract.kind == .html else {
            throw RuntimeError.wrongRouteKind(expected: .html, got: route.extract.kind)
        }
        var out: [String: String] = [:]
        for (name, field) in route.extract.fields {
            guard let strategies = field.strategies else { continue }
            for strategy in strategies {
                if let v = runStrategy(strategy, html: html) {
                    out[name] = applyTransform(v, transform: field.transform)
                    break
                }
            }
        }
        return out
    }

    // MARK: - Strategy dispatch

    private static func runStrategy(
        _ strategy: SiteAdapterDefinition.HTMLStrategy,
        html: String
    ) -> String? {
        switch strategy.kind {
        case .regex:
            guard let regex = try? NSRegularExpression(
                pattern: strategy.pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ) else { return nil }
            let nsRange = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: nsRange),
                  match.numberOfRanges > strategy.group,
                  let range = Range(match.range(at: strategy.group), in: html) else {
                return nil
            }
            var captured = String(html[range])
            if strategy.stripTags ?? false {
                captured = captured
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            }
            captured = captured.trimmingCharacters(in: .whitespacesAndNewlines)
            return captured.isEmpty ? nil : captured
        }
    }

    // MARK: - Path resolution

    /// Path token kinds used internally by `resolvePath`.
    private enum PathToken: Equatable {
        case key(String)       // `foo`
        case index(Int)        // `[3]`
        case wildcard          // `[*]` — map over the current array
    }

    /// Tokenize `foo.bar[0].baz[*].qux` into a flat token list.
    private static func tokenize(_ path: String) -> [PathToken] {
        var tokens: [PathToken] = []
        var buffer = ""
        let chars = Array(path)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            switch ch {
            case ".":
                if !buffer.isEmpty { tokens.append(.key(buffer)); buffer.removeAll() }
                i += 1
            case "[":
                if !buffer.isEmpty { tokens.append(.key(buffer)); buffer.removeAll() }
                guard let close = chars[i...].firstIndex(of: "]") else { return tokens }
                let inside = String(chars[(i + 1)..<close])
                if inside == "*" {
                    tokens.append(.wildcard)
                } else if let idx = Int(inside) {
                    tokens.append(.index(idx))
                }
                i = close + 1
            default:
                buffer.append(ch)
                i += 1
            }
        }
        if !buffer.isEmpty { tokens.append(.key(buffer)) }
        return tokens
    }

    /// Minimal JSON-path subset. Supported syntax:
    /// - `$`               — the root itself
    /// - `foo`             — child key
    /// - `foo.bar`         — nested key
    /// - `foo[0]`          — array index
    /// - `foo[*]`          — array wildcard (returns the whole array)
    /// - `foo[*].bar`      — map `.bar` over every element
    /// - `foo[*].bar[*].baz` — nested wildcards flatten
    static func resolvePath(root: Any, path: String) -> Any? {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "$" || trimmed.isEmpty { return root }
        if trimmed.hasPrefix("$.") { trimmed.removeFirst(2) }
        else if trimmed.hasPrefix("$") { trimmed.removeFirst(1) }

        // `current` is a list of "live" values. Most of the time it has a
        // single element; after a `[*]` token it may have many. Each
        // subsequent token is applied to every live value and the results
        // flattened back into `current`.
        var current: [Any] = [root]
        var collapseToArray = false

        for token in tokenize(trimmed) {
            var next: [Any] = []
            switch token {
            case .key(let k):
                for item in current {
                    if let dict = item as? [String: Any], let v = dict[k] {
                        next.append(v)
                    }
                }
            case .index(let i):
                for item in current {
                    if let arr = item as? [Any], i >= 0, i < arr.count {
                        next.append(arr[i])
                    }
                }
            case .wildcard:
                for item in current {
                    if let arr = item as? [Any] {
                        next.append(contentsOf: arr)
                    }
                }
                collapseToArray = true
            }
            current = next
            if current.isEmpty { return collapseToArray ? [] : nil }
        }

        if collapseToArray { return current }
        return current.first
    }

    // MARK: - Value helpers

    static func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber {
            // Distinguish Bool (CFBoolean) from numeric for clean output.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(d) }
        return ""
    }

    static func applyTransform(_ value: String, transform: String?) -> String {
        guard let transform else { return value }
        switch transform {
        case "prefix4Int":
            // Used for "1999-03" → "1999" style year values.
            return String(value.prefix(4))
        case "upper":
            return value.uppercased()
        case "lower":
            return value.lowercased()
        case "trim":
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "stripDoiOrgPrefix":
            // "https://doi.org/10.1234/xyz" → "10.1234/xyz"; case-normalized to lower.
            if let range = value.range(of: "doi.org/") {
                return String(value[range.upperBound...]).lowercased()
            }
            return value.lowercased()
        case "stripHtmlTags":
            // CrossRef abstracts are JATS XML (e.g. `<jats:p>...</jats:p>`).
            // This removes ALL angle-bracket tags and collapses whitespace.
            return value
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return value
        }
    }

    // MARK: - PostProcess registry

    /// Named post-processors operate on the raw resolved `Any` value from
    /// `resolvePath` before stringification. Useful when the field semantics
    /// depend on the JSON structure itself (not just the stringified content).
    ///
    /// Adding a new post-processor is a two-step change:
    /// 1. Append a case here.
    /// 2. Reference it from an adapter JSON via `"postProcess": "<name>"`.
    private static func applyPostProcess(_ value: Any, name: String) -> String? {
        switch name {
        case "reconstructInvertedIndex":
            // OpenAlex `abstract_inverted_index` → reassembled plain text.
            // Shape: `{ "word": [pos1, pos2, ...], ... }` → "word1 word2 ..."
            guard let inverted = value as? [String: [Int]] else { return nil }
            var positions: [Int: String] = [:]
            for (word, indices) in inverted {
                for idx in indices { positions[idx] = word }
            }
            guard !positions.isEmpty else { return nil }
            let text = positions.keys.sorted().compactMap { positions[$0] }.joined(separator: " ")
            return text.isEmpty ? nil : text
        default:
            return nil
        }
    }
}
