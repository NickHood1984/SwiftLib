import Foundation

/// Manages CSL styles — import, store, list, render
/// Stores .csl files in Application Support for persistence
public final class CSLManager {
    public static let shared = CSLManager()

    public struct StyleDescriptor: Identifiable {
        public let id: String
        public let title: String
        public let isBuiltin: Bool
        public let citationKind: CitationKind

        public init(id: String, title: String, isBuiltin: Bool, citationKind: CitationKind) {
            self.id = id
            self.title = title
            self.isBuiltin = isBuiltin
            self.citationKind = citationKind
        }
    }

    private var cachedEngines: [String: CSLEngine] = [:]
    private var cachedDescriptors: [StyleDescriptor]?
    private var cachedStylesSignature: [String] = []
    /// In-memory cache: styleId → raw CSL XML bytes for user-imported styles.
    private var cachedXmlData: [String: Data] = [:]
    private let cacheLock = NSLock()
    private let storageDir: URL

    private func withCacheLock<T>(_ body: () throws -> T) rethrows -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return try body()
    }

    private static func defaultStorageDir() -> URL {
        let fm = FileManager.default
        let bases: [URL] = [
            (try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )),
            fm.temporaryDirectory.appendingPathComponent("SwiftLibFallback", isDirectory: true),
        ].compactMap { $0 }

        for base in bases {
            let dir = base.appendingPathComponent("SwiftLib/CSLStyles", isDirectory: true)
            if (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
                return dir
            }
        }

        return fm.temporaryDirectory.appendingPathComponent("SwiftLib/CSLStyles", isDirectory: true)
    }

    public init() {
        storageDir = Self.defaultStorageDir()
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    // MARK: - Import

    /// Import a .csl file, returns the style title
    @discardableResult
    public func importCSL(from url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let parser = CSLXMLParser()
        guard let style = parser.parse(data: data) else {
            throw CSLError.parseError
        }
        if style.id.isEmpty {
            throw CSLError.invalidStructure("missing style ID")
        }
        if style.title.isEmpty {
            throw CSLError.invalidStructure("missing style title")
        }

        // Save to storage
        let fileName = url.lastPathComponent
        let dest = storageDir.appendingPathComponent(fileName)
        try data.write(to: dest)

        // Cache engine and raw XML
        withCacheLock {
            cachedEngines[style.id] = CSLEngine(style: style)
            cachedXmlData[style.id] = data
            invalidateStyleDescriptorCacheLocked()
        }

        return style.title
    }

    /// Import from raw CSL XML string
    @discardableResult
    public func importCSL(xml: String, fileName: String) throws -> String {
        guard let data = xml.data(using: .utf8) else { throw CSLError.parseError }
        let parser = CSLXMLParser()
        guard let style = parser.parse(data: data) else {
            throw CSLError.parseError
        }
        if style.id.isEmpty {
            throw CSLError.invalidStructure("missing style ID")
        }
        if style.title.isEmpty {
            throw CSLError.invalidStructure("missing style title")
        }

        let dest = storageDir.appendingPathComponent(fileName)
        try data.write(to: dest)
        withCacheLock {
            cachedEngines[style.id] = CSLEngine(style: style)
            cachedXmlData[style.id] = data
            invalidateStyleDescriptorCacheLocked()
        }

        return style.title
    }

    /// Import a style from raw XML data with an explicit id and title.
    /// Used by the Word Add-in server when receiving CSL XML over HTTP.
    /// The file is saved as `<id>.csl` in the storage directory.
    @discardableResult
    public func importCSL(id: String, title: String, xmlData: Data) throws -> String {
        let parser = CSLXMLParser()
        guard let style = parser.parse(data: xmlData) else {
            throw CSLError.parseError
        }
        // Prefer the id embedded in the CSL XML; fall back to the caller-supplied id
        let resolvedId = style.id.isEmpty ? id : style.id
        let dest = storageDir.appendingPathComponent("\(resolvedId).csl")
        try xmlData.write(to: dest)
        withCacheLock {
            cachedEngines[resolvedId] = CSLEngine(style: style)
            cachedXmlData[resolvedId] = xmlData
            invalidateStyleDescriptorCacheLocked()
        }
        return style.title.isEmpty ? title : style.title
    }

    /// Delete an imported style by its style id.
    /// Throws `CSLError.builtinStyleCannotBeDeleted` if the id belongs to a built-in style.
    public func deleteImportedCSL(id: String) throws {
        let builtinIds: Set<String> = Set(availableStyles().filter(\.isBuiltin).map(\.id))
        guard !builtinIds.contains(id) else {
            throw CSLError.builtinStyleCannotBeDeleted
        }
        deleteStyle(id: id)
    }

    // MARK: - List Styles

    /// List all available styles (built-in + imported)
    public func availableStyles() -> [StyleDescriptor] {
        let signature = styleDirectorySignature()
        if let cached = withCacheLock({ cachedDescriptors }),
           withCacheLock({ cachedStylesSignature == signature }) {
            return cached
        }

        var xmlCacheUpdates: [String: Data] = [:]
        var styles: [StyleDescriptor] = [
            .init(id: "apa", title: "APA 7th Edition", isBuiltin: true, citationKind: .authorDate),
            .init(id: "mla", title: "MLA 9th Edition", isBuiltin: true, citationKind: .authorDate),
            .init(id: "chicago", title: "Chicago 17th", isBuiltin: true, citationKind: .authorDate),
            .init(id: "ieee", title: "IEEE", isBuiltin: true, citationKind: .numeric),
            .init(id: "harvard", title: "Harvard", isBuiltin: true, citationKind: .authorDate),
            .init(id: "vancouver", title: "Vancouver", isBuiltin: true, citationKind: .numeric),
            .init(id: "nature", title: "Nature", isBuiltin: true, citationKind: .numeric),
        ]
        let builtinIDs = Set(styles.map(\.id))
        if let builtinDir = Bundle.module.url(forResource: "BuiltinCSL", withExtension: nil) {
            let builtinFiles = (try? FileManager.default.contentsOfDirectory(at: builtinDir, includingPropertiesForKeys: nil)) ?? []
            for file in builtinFiles where file.pathExtension == "csl" {
                guard let data = try? Data(contentsOf: file),
                      let style = CSLXMLParser().parse(data: data),
                      !builtinIDs.contains(style.id) else { continue }
                styles.append(.init(id: style.id, title: style.title, isBuiltin: true, citationKind: style.citationKind))
                xmlCacheUpdates[style.id] = data
            }
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "csl" {
                if let data = try? Data(contentsOf: file),
                   let style = CSLXMLParser().parse(data: data),
                   !styles.contains(where: { $0.id == style.id }) {
                    styles.append(.init(id: style.id, title: style.title, isBuiltin: false, citationKind: style.citationKind))
                    xmlCacheUpdates[style.id] = data
                }
            }
        }
        withCacheLock {
            cachedXmlData.merge(xmlCacheUpdates) { _, new in new }
            cachedDescriptors = styles
            cachedStylesSignature = signature
        }
        return styles
    }


    // MARK: - Render

    /// Get engine for a style (cached)
    public func engine(for styleId: String) -> CSLEngine? {
        if let cached = withCacheLock({ cachedEngines[styleId] }) {
            return cached
        }

        // Try to load from storage
        if let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "csl" {
                if let data = try? Data(contentsOf: file),
                   let style = CSLXMLParser().parse(data: data),
                   style.id == styleId {
                    let engine = CSLEngine(style: style)
                    withCacheLock {
                        cachedEngines[styleId] = engine
                    }
                    return engine
                }
            }
        }

        return nil
    }

    /// Raw CSL XML bytes for an imported style.
    /// Checks the in-memory cache first; falls back to a disk scan and
    /// populates the cache on a miss so subsequent calls are O(1).
    public func cslXmlData(forStyleId styleId: String) -> Data? {
        if let cached = withCacheLock({ cachedXmlData[styleId] }) { return cached }
        // 1. Search user-imported styles directory
        if let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "csl" {
                guard let data = try? Data(contentsOf: file),
                      let style = CSLXMLParser().parse(data: data),
                      style.id == styleId else { continue }
                withCacheLock {
                    cachedXmlData[styleId] = data
                }
                return data
            }
        }
        // 2. Fall back to bundled built-in CSL styles
        if let builtinDir = Bundle.module.url(forResource: "BuiltinCSL", withExtension: nil),
           let files = try? FileManager.default.contentsOfDirectory(at: builtinDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "csl" {
                guard let data = try? Data(contentsOf: file),
                      let style = CSLXMLParser().parse(data: data),
                      style.id == styleId else { continue }
                withCacheLock {
                    cachedXmlData[styleId] = data
                }
                return data
            }
        }
        return nil
    }


    /// Format inline citation — tries CSL engine first, falls back to built-in
    public func formatCitation(_ refs: [Reference], style: String) -> String {
        if let engine = engine(for: style) {
            return engine.renderInlineCitation(refs)
        }
        // Fallback to built-in formatter
        return CitationFormatter.formatInlineCitation(refs, style: style)
    }

    /// Format bibliography entry — tries CSL engine first, falls back to built-in
    public func formatBibliography(_ ref: Reference, style: String) -> String {
        if let engine = engine(for: style) {
            return engine.renderBibliographyEntry(ref)
        }
        return CitationFormatter.formatBibliography(ref, style: style)
    }

    public func citationKind(for styleId: String) -> CitationKind {
        if let style = availableStyles().first(where: { $0.id == styleId }) {
            return style.citationKind
        }
        if let engine = engine(for: styleId) {
            return engine.style.citationKind
        }
        return .authorDate
    }

    public func citationFormatting(for styleID: String) -> CitationTextFormatting? {
        if let engine = engine(for: styleID) {
            return engine.style.citationLayout.citationTextFormatting
        }
        if let data = cslXmlData(forStyleId: styleID),
           let style = CSLXMLParser().parse(data: data) {
            return style.citationLayout.citationTextFormatting
        }
        return nil
    }

    public func shouldSuperscriptNumericCitation(styleID: String, citationText _: String) -> Bool {
        citationFormatting(for: styleID)?.superscript == true
    }

    // MARK: - Delete

    public func deleteStyle(id: String) {
        withCacheLock {
            cachedEngines.removeValue(forKey: id)
            cachedXmlData.removeValue(forKey: id)
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "csl" {
                if let data = try? Data(contentsOf: file),
                   let style = CSLXMLParser().parse(data: data),
                   style.id == id {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        invalidateStyleDescriptorCache()
    }

    private func invalidateStyleDescriptorCache() {
        withCacheLock {
            invalidateStyleDescriptorCacheLocked()
        }
    }

    private func invalidateStyleDescriptorCacheLocked() {
        cachedDescriptors = nil
        cachedStylesSignature = []
    }

    private func styleDirectorySignature() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "csl" }
            .map { file in
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                return "\(file.lastPathComponent)#\(stamp)"
            }
            .sorted()
    }

    public enum CSLError: LocalizedError {
        case parseError
        case invalidStructure(String)
        case builtinStyleCannotBeDeleted
        public var errorDescription: String? {
            switch self {
            case .parseError: return "Failed to parse CSL file"
            case .invalidStructure(let detail): return "Invalid CSL structure: \(detail)"
            case .builtinStyleCannotBeDeleted: return "Built-in styles cannot be deleted"
            }
        }
    }
}
