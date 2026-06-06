import Foundation

// ---------------------------------------------------------------------------
// CitationRenderer
//
// The SINGLE public entry point for all citation and bibliography rendering
// within the SwiftLib app (list preview, detail view, settings preview, CLI).
//
// ALL rendering uses citeproc-js via CiteprocJSCorePool so that the output
// is byte-for-byte identical to what the Word/WPS add-in produces.
// The native CSLEngine is intentionally NOT used here; it is reserved for
// field-completeness diagnostics (CSLFieldIssue / CSLCompleteness) only.
//
// Thread safety:
//   CitationRenderer is stateless. CiteprocJSCorePool manages per-engine
//   locking internally. The LRU cache uses a NSLock for thread safety.
// ---------------------------------------------------------------------------

public enum CitationRenderer {

    // MARK: - Inline citation

    /// Render an in-text citation string for one or more references.
    ///
    /// Examples:
    ///   APA author-date → "(Smith et al., 2024; Jones, 2023)"
    ///   IEEE numeric    → "[1,3]"
    ///   Vancouver       → "(1,3)"
    ///
    /// Silently falls back to a plain-text approximation when the citeproc-js
    /// engine cannot be initialised for the requested style.
    public static func renderInlineCitation(
        _ refs: [Reference],
        styleID: String
    ) -> String {
        guard !refs.isEmpty else { return "" }
        let ids = refs.compactMap(\.id).map(String.init).joined(separator: ",")
        guard !ids.isEmpty else { return fallbackInline(refs) }
        let cacheKey = "\(styleID)|inline|\(ids)"
        if let hit = renderCache.get(cacheKey) { return hit }

        let result = renderPreviewDocument(refs: refs, styleID: styleID, includeBibliography: false)
        let text = result?.inlineCitation ?? fallbackInline(refs)
        renderCache.set(cacheKey, value: text)
        return text
    }

    // MARK: - Bibliography entry

    /// Render a full bibliography entry for a single reference.
    ///
    /// Examples:
    ///   APA → "Smith, J. A. (2024). Title. Journal, 1(2), 3–4. https://doi.org/…"
    ///   IEEE → "[1] J. A. Smith, "Title," Journal, vol. 1, no. 2, pp. 3–4, 2024."
    ///
    /// Silently falls back when the engine is unavailable.
    public static func renderBibliographyEntry(
        _ ref: Reference,
        styleID: String
    ) -> String {
        guard let refID = ref.id else {
            let result = renderPreviewDocument(refs: [ref], styleID: styleID, includeBibliography: true)
            return result?.bibliographyEntry ?? fallbackBib(ref)
        }

        let idStr = String(refID)
        let cacheKey = "\(styleID)|bib|\(idStr)"
        if let hit = renderCache.get(cacheKey) { return hit }

        let result = renderPreviewDocument(refs: [ref], styleID: styleID, includeBibliography: true)
        let text = result?.bibliographyEntry ?? fallbackBib(ref)
        renderCache.set(cacheKey, value: text)
        return text
    }

    // MARK: - Cache invalidation

    /// Invalidate all cached entries for a specific style (e.g. after import/delete).
    public static func invalidate(styleID: String) {
        CiteprocJSCorePool.shared.invalidate(styleId: styleID)
        renderCache.invalidatePrefix(styleID)
    }

    /// Invalidate cached entries for a specific reference (e.g. after save).
    public static func invalidate(referenceID: Int64) {
        renderCache.invalidateContaining(String(referenceID))
    }

    /// Clear the entire render cache (e.g. after bulk library update).
    public static func invalidateAll() {
        renderCache.clear()
    }

    // MARK: - Internal document render

    private struct PreviewResult {
        var inlineCitation: String
        var bibliographyEntry: String
    }

    private static func renderPreviewDocument(
        refs: [Reference],
        styleID: String,
        includeBibliography: Bool
    ) -> PreviewResult? {
        // Build CSL-JSON items for all refs that have a database ID.
        let cslItems = CSLExportService.cslJSONObjects(for: refs)
        guard !cslItems.isEmpty else { return nil }

        let citationID = "swiftlib-preview"
        let itemIDs = refs.compactMap(\.id).map(String.init)
        let citations: [(id: String, itemIDs: [String], position: Int)] = [
            (id: citationID, itemIDs: itemIDs, position: 0)
        ]

        guard let rendered = try? CiteprocJSCorePool.shared.withEngine(forStyleId: styleID, { engine in
            engine.setItems(cslItems)
            return try engine.renderDocument(citations: citations, includeBibliography: includeBibliography)
        }) else { return nil }

        let inline = rendered.citationTexts[citationID] ?? fallbackInline(refs)
        let bibRaw = rendered.bibliographyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let bib = bibRaw.isEmpty ? fallbackBib(refs.first ?? Reference(title: "")) : bibRaw
        return PreviewResult(inlineCitation: inline, bibliographyEntry: bib)
    }

    // MARK: - Graceful fallbacks
    //
    // Used ONLY when citeproc-js cannot be initialised or the style XML is
    // missing. The output is not style-compliant but always informative.

    private static func fallbackInline(_ refs: [Reference]) -> String {
        let parts = refs.map { ref -> String in
            let family = ref.authors.first?.family.swiftlib_nilIfBlank ?? "?"
            let year = ref.year.map(String.init) ?? "n.d."
            return "\(family), \(year)"
        }
        return "(\(parts.joined(separator: "; ")))"
    }

    private static func fallbackBib(_ ref: Reference) -> String {
        let authStr: String
        if ref.authors.isEmpty {
            authStr = "?"
        } else {
            authStr = ref.authors.map { a in
                a.given.isEmpty ? a.family : "\(a.family), \(a.given.prefix(1))."
            }.joined(separator: "; ")
        }
        let year = ref.year.map { "(\($0)). " } ?? "(n.d.). "
        let journal = ref.journal.swiftlib_nilIfBlank.map { " \($0)." } ?? ""
        let doi = ref.doi.swiftlib_nilIfBlank.map { raw in
            let bare = DOIIdentifier(raw)?.cslString ?? raw
            return " https://doi.org/\(bare)"
        } ?? ""
        return "\(authStr) \(year)\(ref.title).\(journal)\(doi)"
    }

    // MARK: - Shared LRU cache (capacity: 500 entries, ~50–100 KB)

    private static let renderCache = RenderCache(capacity: 500)
}

// MARK: - Simple LRU render cache

/// A thread-safe LRU cache keyed by String.
/// Uses a monotonically increasing access counter for eviction.
private final class RenderCache {
    private let capacity: Int
    private var store: [String: (value: String, order: Int)] = [:]
    private var counter: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = store[key] else { return nil }
        counter &+= 1
        store[key] = (entry.value, counter)
        return entry.value
    }

    func set(_ key: String, value: String) {
        lock.lock(); defer { lock.unlock() }
        if store[key] == nil, store.count >= capacity {
            if let lru = store.min(by: { $0.value.order < $1.value.order }) {
                store.removeValue(forKey: lru.key)
            }
        }
        counter &+= 1
        store[key] = (value, counter)
    }

    func invalidatePrefix(_ prefix: String) {
        lock.lock(); defer { lock.unlock() }
        store = store.filter { !$0.key.hasPrefix(prefix) }
    }

    func invalidateContaining(_ substring: String) {
        lock.lock(); defer { lock.unlock() }
        store = store.filter { !$0.key.contains(substring) }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
    }
}
