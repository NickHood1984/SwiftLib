import Foundation
import JavaScriptCore

// ---------------------------------------------------------------------------
// CiteprocJSCoreEngine
//
// Embeds citeproc-js inside JavaScriptCore to provide a standards-compliant
// CSL rendering engine on the Swift side. This replaces the custom CSLEngine
// as the server-side fallback renderer, ensuring identical output whether
// rendering happens in the browser (Word Add-in JS) or on the server
// (POST /api/render-document).
//
// Architecture:
//   1. Load the same citeproc-bundle.js that the Word Add-in uses
//   2. Register a "sys" object that provides retrieveItem / retrieveLocale
//   3. Call CSL.Engine to render citations and bibliography
//
// Thread safety: Each engine instance owns its own JSContext. Do NOT share
// instances across threads. Use CiteprocJSCorePool for concurrent access.
// ---------------------------------------------------------------------------

public final class CiteprocJSCoreEngine {

    private let jsContext: JSContext
    private let engineRef: JSValue
    private let defaultCitationFormatting: CitationTextFormatting?
    private var itemStore: [String: [String: Any]] = [:]
    private var currentItemIDs: [String] = []

    public enum EngineError: LocalizedError {
        case contextCreationFailed
        case bundleLoadFailed
        case engineInitFailed(String)
        case renderFailed(String)

        public var errorDescription: String? {
            switch self {
            case .contextCreationFailed: return "Failed to create JavaScriptCore context"
            case .bundleLoadFailed: return "Failed to load citeproc-bundle.js from resources"
            case .engineInitFailed(let msg): return "citeproc-js engine init failed: \(msg)"
            case .renderFailed(let msg): return "citeproc-js render failed: \(msg)"
            }
        }
    }

    /// Initialize with a CSL style XML string and locale XML string.
    /// - Parameters:
    ///   - styleXML: The full CSL style XML content
    ///   - localeXML: The locale XML content (default: en-US)
    public init(styleXML: String, localeXML: String) throws {
        guard let ctx = JSContext() else {
            throw EngineError.contextCreationFailed
        }
        self.jsContext = ctx
        if let parsedStyle = CSLXMLParser().parse(data: Data(styleXML.utf8)) {
            self.defaultCitationFormatting = parsedStyle.citationLayout.citationTextFormatting
        } else {
            self.defaultCitationFormatting = nil
        }

        // Set up exception handler
        ctx.exceptionHandler = { _, exception in
            if SwiftLibCoreDebugLogging.runtimeVerbose, let exc = exception {
                print("[CiteprocJSCore] JS Exception: \(exc)")
            }
        }

        // Load citeproc-bundle.js — the bundle IIFE sets globalThis.CSL
        // (via `globalThis.CSL = CSL` in the entry file) so that
        // `new CSL.Engine(...)` works in JavaScriptCore.
        guard let bundleJS = Self.loadCiteprocBundle() else {
            throw EngineError.bundleLoadFailed
        }
        ctx.evaluateScript(bundleJS)

        // Store locale for retrieval
        let localeEscaped = localeXML
        ctx.setObject(localeEscaped, forKeyedSubscript: "__swiftlib_locale" as NSString)
        ctx.setObject(styleXML, forKeyedSubscript: "__swiftlib_style" as NSString)

        // Create the sys object that citeproc-js requires
        let sysSetup = """
        var __swiftlib_items = {};
        var __swiftlib_sys = {
            retrieveLocale: function(lang) {
                return __swiftlib_locale;
            },
            retrieveItem: function(id) {
                return __swiftlib_items[String(id)] || null;
            }
        };
        """
        ctx.evaluateScript(sysSetup)

        // Initialize citeproc engine
        let initScript = """
        var __swiftlib_engine;
        try {
            __swiftlib_engine = new CSL.Engine(__swiftlib_sys, __swiftlib_style);
            "ok";
        } catch(e) {
            "error:" + e.message;
        }
        """
        let result = ctx.evaluateScript(initScript)
        let resultStr = result?.toString() ?? "unknown error"
        if resultStr.hasPrefix("error:") {
            throw EngineError.engineInitFailed(String(resultStr.dropFirst(6)))
        }

        self.engineRef = ctx.objectForKeyedSubscript("__swiftlib_engine")!
    }

    // MARK: - Item Management

    /// Register CSL-JSON items for rendering
    public func setItems(_ items: [[String: Any]]) {
        itemStore.removeAll()
        currentItemIDs.removeAll()
        for item in items {
            guard let id = item["id"] as? String ?? (item["id"] as? Int64).map({ String($0) }) else { continue }
            itemStore[id] = item
            currentItemIDs.append(id)
        }

        // Push items into JS context
        if let jsonData = try? JSONSerialization.data(withJSONObject: items),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            jsContext.evaluateScript("""
                var __items = \(jsonStr);
                __swiftlib_items = {};
                for (var i = 0; i < __items.length; i++) {
                    __swiftlib_items[String(__items[i].id)] = __items[i];
                }
            """)
        }

    }

    // MARK: - Rendering

    /// Render a document with multiple citation clusters.
    /// Returns (citationTexts: [citationID: renderedText], bibliographyHTML: String)
    public func renderDocument(citations: [(id: String, itemIDs: [String], position: Int)]) throws
        -> (
            citationTexts: [String: String],
            bibliographyText: String,
            superscriptIDs: Set<String>,
            citationFormatting: CitationTextFormatting?
        )
    {
        try renderDocument(
            citations: citations.map { citation in
                (
                    id: citation.id,
                    itemIDs: citation.itemIDs,
                    position: citation.position,
                    citationItems: nil
                )
            }
        )
    }

    /// Render a document with multiple citation clusters.
    /// Returns (citationTexts: [citationID: renderedText], bibliographyHTML: String)
    public func renderDocument(citations: [(id: String, itemIDs: [String], position: Int, citationItems: [[String: Any]]?)]) throws
        -> (
            citationTexts: [String: String],
            bibliographyText: String,
            superscriptIDs: Set<String>,
            citationFormatting: CitationTextFormatting?
        )
    {
        var citationTexts: [String: String] = [:]
        var superscriptIDs: Set<String> = []
        var citationFormatting = defaultCitationFormatting

        try resetProcessorState()
        try syncRegisteredItems()

        let referencedIDs = Set(citations.flatMap(\.itemIDs))
        let availableIDs = Set(itemStore.keys)
        let missingIDs = referencedIDs.subtracting(availableIDs).sorted()
        if !missingIDs.isEmpty {
            throw EngineError.renderFailed("文档中的引文引用了当前渲染上下文中不存在的文献 ID：\(missingIDs.joined(separator: ", "))")
        }

        // Use plain-text output for citations — the Word add-in inserts
        // via insertText() and handles superscript separately via
        // cc.font.superscript.  HTML tags like <sup> would be shown
        // literally in the document.
        jsContext.evaluateScript("__swiftlib_engine.setOutputFormat('text');")

        // Process citations in order using processCitationCluster
        for (index, citation) in citations.sorted(by: { $0.position < $1.position }).enumerated() {
            // Build citationItems JSON: use rich options if provided, else plain {"id":"..."}
            let citationItems: String
            if let richItems = citation.citationItems, !richItems.isEmpty {
                // Merge each rich item with its id (itemRef → id mapping)
                let richJSON = richItems.compactMap { item -> String? in
                    var merged = item
                    // itemRef is "lib:<refId>" — extract the numeric id
                    if let itemRef = item["itemRef"] as? String, itemRef.hasPrefix("lib:") {
                        merged["id"] = String(itemRef.dropFirst(4))
                    } else if let refId = item["refId"] {
                        merged["id"] = refId
                    }
                    guard merged["id"] != nil else { return nil }
                    // Remove internal fields not needed by citeproc-js
                    merged.removeValue(forKey: "itemRef")
                    merged.removeValue(forKey: "refId")
                    guard let data = try? JSONSerialization.data(withJSONObject: merged),
                          let str = String(data: data, encoding: .utf8) else { return nil }
                    return str
                }.joined(separator: ",")
                citationItems = richJSON.isEmpty
                    ? citation.itemIDs.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",")
                    : richJSON
            } else {
                citationItems = citation.itemIDs.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",")
            }
            let citationObj = """
                {
                    "citationID": "\(citation.id)",
                    "citationItems": [\(citationItems)],
                    "properties": {"noteIndex": \(index + 1)}
                }
            """
            // citationsPre: all previously processed citations
            let pre = citations.prefix(index).sorted(by: { $0.position < $1.position }).enumerated().map { (i, c) in
                "[\"" + c.id + "\", " + String(i + 1) + "]"
            }.joined(separator: ",")

            let script = """
                try {
                    var result = __swiftlib_engine.processCitationCluster(\(citationObj), [\(pre)], []);
                    JSON.stringify(result);
                } catch(e) {
                    JSON.stringify({"error": e.message});
                }
            """
            guard let resultVal = jsContext.evaluateScript(script),
                  let resultStr = resultVal.toString(),
                  let resultData = resultStr.data(using: .utf8) else {
                continue
            }

            // processCitationCluster returns [bibchange, [[index, string, citationID], ...]]
            if let resultArray = try? JSONSerialization.jsonObject(with: resultData) as? [Any],
               resultArray.count >= 2,
               let updates = resultArray[1] as? [[Any]] {
                for update in updates {
                    if update.count >= 3,
                       let text = update[1] as? String,
                       let cid = update[2] as? String {
                        citationTexts[cid] = text
                    }
                }
            } else if let errorObj = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                      let errorMsg = errorObj["error"] as? String {
                throw EngineError.renderFailed(errorMsg)
            }
        }

        // Switch to HTML for bibliography (richer structure for stripHTML)
        jsContext.evaluateScript("__swiftlib_engine.setOutputFormat('html');")

        // Generate bibliography
        let bibScript = """
            try {
                var bib = __swiftlib_engine.makeBibliography();
                if (bib && bib.length >= 2) {
                    JSON.stringify(bib);
                } else {
                    "null";
                }
            } catch(e) {
                JSON.stringify({"error": e.message});
            }
        """
        var bibliographyText = ""
        if let bibVal = jsContext.evaluateScript(bibScript),
           let bibStr = bibVal.toString(), bibStr != "null",
           let bibData = bibStr.data(using: .utf8),
           let bibArray = try? JSONSerialization.jsonObject(with: bibData) as? [Any],
           bibArray.count >= 2,
           let entries = bibArray[1] as? [String] {
            // Strip HTML tags for plain text output
            bibliographyText = entries.map { Self.stripHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n")
        }

        // Detect whether the CSL style wants superscript citations.
        // citeproc-js stores the layout decoration in
        //   engine.citation.opt.layout_decorations → [["@vertical-align","sup"]]
        // when the CSL has <layout ... vertical-align="sup"> on <citation>.
        let kindScript = """
            (function() {
                try {
                    var decors = (__swiftlib_engine.citation &&
                                  __swiftlib_engine.citation.opt &&
                                  __swiftlib_engine.citation.opt.layout_decorations) || [];
                    for (var i = 0; i < decors.length; i++) {
                        if (decors[i][0] === "@vertical-align" && decors[i][1] === "sup") return "sup";
                    }
                    return "";
                } catch(e) { return ""; }
            })()
        """
        if let kindVal = jsContext.evaluateScript(kindScript),
           let kindStr = kindVal.toString(),
           kindStr == "sup" {
            if citationFormatting == nil {
                citationFormatting = CitationTextFormatting()
            }
            citationFormatting?.superscript = true
            citationFormatting?.subscripted = false
        }
        if citationFormatting?.superscript == true {
            superscriptIDs = Set(citationTexts.keys)
        }

        return (citationTexts, bibliographyText, superscriptIDs, citationFormatting)
    }

    // MARK: - Helpers

    private func resetProcessorState() throws {
        let resetScript = """
        try {
            __swiftlib_engine = new CSL.Engine(__swiftlib_sys, __swiftlib_style);
            "ok";
        } catch(e) {
            "error:" + e.message;
        }
        """
        let result = jsContext.evaluateScript(resetScript)?.toString() ?? "unknown error"
        if result.hasPrefix("error:") {
            throw EngineError.engineInitFailed(String(result.dropFirst(6)))
        }
    }

    private func syncRegisteredItems() throws {
        guard let idsData = try? JSONSerialization.data(withJSONObject: currentItemIDs),
              let idsStr = String(data: idsData, encoding: .utf8) else {
            throw EngineError.renderFailed("无法序列化当前文献条目。")
        }
        let result = jsContext.evaluateScript("""
            try {
                __swiftlib_engine.updateItems(\(idsStr));
                "ok";
            } catch(e) {
                "error:" + e.message;
            }
        """)?.toString() ?? "unknown error"
        if result.hasPrefix("error:") {
            throw EngineError.renderFailed(String(result.dropFirst(6)))
        }
    }

    // MARK: - Comprehensive HTML Entity Decoding

    /// Common named HTML entities → Unicode characters.
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "bull": "\u{2022}", "hellip": "\u{2026}", "trade": "\u{2122}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "deg": "\u{00B0}",
        "times": "\u{00D7}", "divide": "\u{00F7}", "minus": "\u{2212}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "zwj": "\u{200D}", "zwnj": "\u{200C}",
    ]

    /// Decode all HTML entities: named (&amp;), decimal (&#38;), hex (&#x26;).
    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&(#x([0-9a-fA-F]+)|#(\\d+)|([a-zA-Z]+));") else {
            return text
        }
        var result = text
        // Process matches from end to start to preserve indices
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }
            var replacement: String?

            // Hex numeric: &#xHH;
            if let hexRange = Range(match.range(at: 2), in: result) {
                let hexStr = String(result[hexRange])
                if let codePoint = UInt32(hexStr, radix: 16), let scalar = Unicode.Scalar(codePoint) {
                    replacement = String(scalar)
                }
            }
            // Decimal numeric: &#DD;
            else if let decRange = Range(match.range(at: 3), in: result) {
                let decStr = String(result[decRange])
                if let codePoint = UInt32(decStr), let scalar = Unicode.Scalar(codePoint) {
                    replacement = String(scalar)
                }
            }
            // Named: &name;
            else if let nameRange = Range(match.range(at: 4), in: result) {
                let name = String(result[nameRange]).lowercased()
                replacement = namedEntities[name]
            }

            if let replacement = replacement {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }

    /// Two-pass decode to handle double-encoded entities (e.g. &amp;amp; → &amp; → &).
    private static func decodeHTMLEntitiesTwice(_ text: String) -> String {
        decodeHTMLEntities(decodeHTMLEntities(text))
    }

    /// Strip HTML tags from citeproc-js output and decode all entities.
    private static func stripHTML(_ html: String) -> String {
        var result = html
        // Replace tags with a space (preserves word boundaries, e.g.
        // `</div><div>` between "[3]" and "Author" → "[3] Author").
        let tagPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        // Comprehensive HTML entity decoding (two-pass for double-encoded residuals)
        result = decodeHTMLEntitiesTwice(result)
        // Normalize non-breaking spaces to regular spaces
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        // Collapse runs of whitespace into a single space
        if let wsRegex = try? NSRegularExpression(pattern: "\\s+") {
            result = wsRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        return result
    }

    /// Load citeproc-bundle.js from app resources
    private static func loadCiteprocBundle() -> String? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "citeproc-bundle", withExtension: "js", subdirectory: "WordAddin/dist"),
            Bundle.main.url(forResource: "citeproc-bundle", withExtension: "js", subdirectory: "WordAddin/dist"),
            Bundle.module.url(forResource: "citeproc-bundle", withExtension: "js", subdirectory: "dist"),
            Bundle.main.url(forResource: "citeproc-bundle", withExtension: "js", subdirectory: "dist"),
            Bundle.module.url(forResource: "citeproc-bundle", withExtension: "js"),
            Bundle.main.url(forResource: "citeproc-bundle", withExtension: "js"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        // Last resort: search recursively
        if let resourcePath = Bundle.main.resourcePath {
            let fm = FileManager.default
            if let enumerator = fm.enumerator(atPath: resourcePath) {
                for case let path as String in enumerator where path.hasSuffix("citeproc-bundle.js") {
                    let full = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                    if let content = try? String(contentsOf: full, encoding: .utf8) {
                        return content
                    }
                }
            }
        }
        return nil
    }
}

// ---------------------------------------------------------------------------
// CiteprocJSCorePool
//
// Thread-safe pool of CiteprocJSCoreEngine instances, keyed by style ID.
// Used by WordAddinServer to handle concurrent render requests.
// ---------------------------------------------------------------------------

public final class CiteprocJSCorePool {
    public static let shared = CiteprocJSCorePool()

    private final class PooledEngineEntry {
        let engine: CiteprocJSCoreEngine
        let usageLock = NSLock()
        var lastUsed: Date

        init(engine: CiteprocJSCoreEngine) {
            self.engine = engine
            self.lastUsed = Date()
        }
    }

    private var engines: [String: PooledEngineEntry] = [:]
    private let lock = NSLock()
    /// Maximum number of cached engines. LRU eviction when exceeded.
    private let maxEngines = 3

    // MARK: - Last-used style persistence

    private static let lastUsedStyleKey = "CiteprocJSCorePool.lastUsedStyleId"

    /// Persist the style id so we can pre-warm it on next launch.
    private func recordUsage(styleId: String) {
        UserDefaults.standard.set(styleId, forKey: Self.lastUsedStyleKey)
    }

    /// Pre-warm the engine for the style the user used in the previous session.
    /// Call this once from the app delegate after launch (on a background thread).
    public func warmUpLastUsed() {
        guard let styleId = UserDefaults.standard.string(forKey: Self.lastUsedStyleKey),
              !styleId.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.entry(forStyleId: styleId)
        }
    }

    // MARK: - Engine access

    private func entry(forStyleId styleId: String) -> PooledEngineEntry? {
        lock.lock()
        defer { lock.unlock() }

        if let existing = engines[styleId] {
            existing.lastUsed = Date()
            recordUsage(styleId: styleId)
            return existing
        }

        guard let styleXML = loadStyleXML(styleId: styleId),
              let localeXML = loadLocaleXML(lang: "en-US") else {
            return nil
        }

        do {
            let engine = try CiteprocJSCoreEngine(styleXML: styleXML, localeXML: localeXML)
            let entry = PooledEngineEntry(engine: engine)
            // Evict least-recently-used engine if pool is full
            if engines.count >= maxEngines {
                if let lruKey = engines.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
                    engines.removeValue(forKey: lruKey)
                }
            }
            engines[styleId] = entry
            recordUsage(styleId: styleId)
            return entry
        } catch {
            if SwiftLibCoreDebugLogging.runtimeVerbose {
                print("[CiteprocJSCorePool] Failed to create engine for \(styleId): \(error)")
            }
            return nil
        }
    }

    /// Runs the body with exclusive access to a style-specific engine.
    /// JSContext is not thread-safe, so the same engine instance must never be
    /// used concurrently across requests.
    public func withEngine<T>(forStyleId styleId: String, _ body: (CiteprocJSCoreEngine) throws -> T) rethrows -> T? {
        guard let entry = entry(forStyleId: styleId) else { return nil }
        entry.usageLock.lock()
        defer { entry.usageLock.unlock() }
        return try body(entry.engine)
    }

    /// Invalidate cached engine (e.g. when style is updated)
    public func invalidate(styleId: String) {
        lock.lock()
        engines.removeValue(forKey: styleId)
        lock.unlock()
    }

    public func invalidateAll() {
        lock.lock()
        engines.removeAll()
        lock.unlock()
    }

    // MARK: - Resource Loading

    /// Maps well-known style short IDs to their CSL file stem names.
    public static func bundledCSLStem(for styleId: String) -> String? {
        return _bundledCSLStem[styleId]
    }

    private static let _bundledCSLStem: [String: String] = [
        "apa": "apa",
        "mla": "mla",
        "chicago": "chicago",
        "ieee": "ieee",
        "harvard": "harvard",
        "vancouver": "vancouver",
        "nature": "nature",
    ]

    private func loadStyleXML(styleId: String) -> String? {
        let stem = Self._bundledCSLStem[styleId] ?? styleId

        // Try bundled CSL files
        let subdirs = ["WordAddin/CSL", "CSL"]
        for subdir in subdirs {
            for bundle in [Bundle.module, Bundle.main] {
                if let url = bundle.url(forResource: stem, withExtension: "csl", subdirectory: subdir),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    return content
                }
            }
        }

        // Try user-imported CSL via CSLManager
        if let data = CSLManager.shared.cslXmlData(forStyleId: styleId),
           let content = String(data: data, encoding: .utf8) {
            return content
        }

        return nil
    }

    private func loadLocaleXML(lang: String) -> String? {
        let normalized = lang.replacingOccurrences(of: "_", with: "-")
        let stem = "locales-\(normalized)"

        let subdirs = ["WordAddin/locales", "locales"]
        for subdir in subdirs {
            for bundle in [Bundle.module, Bundle.main] {
                if let url = bundle.url(forResource: stem, withExtension: "xml", subdirectory: subdir),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    return content
                }
            }
        }

        // Fallback to en-US
        if normalized.lowercased() != "en-us" {
            return loadLocaleXML(lang: "en-US")
        }

        return nil
    }
}
