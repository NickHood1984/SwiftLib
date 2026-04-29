import Foundation
import OSLog

/// Loads `SiteAdapterDefinition`s from bundled resources, cached by adapter id.
///
/// Default source: `Bundle.module/Resources/adapters/<id>.json`. Tests can
/// inject a custom search path via `registerSearchPath(_:)` to load fixtures
/// from anywhere on disk.
///
/// Thread-safety: the shared instance serializes mutation through an
/// `NSLock`. Reads after initial warm-up are lock-free in the happy path
/// because the cache map is copy-on-write.
public final class SiteAdapterRegistry: @unchecked Sendable {

    public static let shared = SiteAdapterRegistry()

    private let log = Logger(subsystem: "com.swiftlib.fetcher", category: "adapter-registry")

    private let lock = NSLock()
    private var cache: [String: SiteAdapterDefinition] = [:]
    private var extraSearchPaths: [URL] = []

    public init() {}

    // MARK: - Overrides (tests, runtime reloads)

    /// Add a filesystem directory to search before the bundled defaults.
    /// Useful for running canary harnesses with locally-edited adapters.
    public func registerSearchPath(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        extraSearchPaths.insert(url, at: 0)
        cache.removeAll() // invalidate so next lookup re-reads
    }

    /// Explicitly seed a definition. Primarily for unit tests.
    public func seed(_ adapter: SiteAdapterDefinition) {
        lock.lock(); defer { lock.unlock() }
        cache[adapter.id] = adapter
    }

    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    // MARK: - Lookup

    public func adapter(id: String) -> SiteAdapterDefinition? {
        lock.lock()
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        let searchPaths = extraSearchPaths
        lock.unlock()

        // Try extra search paths first (so dev overrides win over bundled defaults).
        for base in searchPaths {
            let candidate = base.appendingPathComponent("\(id).json")
            if let adapter = load(from: candidate) {
                lock.lock()
                cache[id] = adapter
                lock.unlock()
                return adapter
            }
        }

        // Bundled resources: Package.swift copies `Resources` into the module bundle
        // verbatim, so the on-disk layout is mirrored in the bundle.
        let resourceCandidates: [URL?] = [
            Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Resources/adapters"),
            Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "adapters"),
            Bundle.module.url(forResource: id, withExtension: "json")
        ]
        for url in resourceCandidates.compactMap({ $0 }) {
            if let adapter = load(from: url) {
                lock.lock()
                cache[id] = adapter
                lock.unlock()
                return adapter
            }
        }

        log.warning("adapter not found id=\(id, privacy: .public)")
        return nil
    }

    /// Returns the full list of adapter IDs currently discoverable on disk.
    /// Scans both extra search paths and the `Resources/adapters` bundle dir.
    public func allAdapterIDs() -> [String] {
        lock.lock()
        let searchPaths = extraSearchPaths
        lock.unlock()

        var seen = Set<String>()
        var results: [String] = []

        func appendJSONs(in dir: URL) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { return }
            for url in contents where url.pathExtension == "json" {
                let id = url.deletingPathExtension().lastPathComponent
                if seen.insert(id).inserted {
                    results.append(id)
                }
            }
        }

        for dir in searchPaths { appendJSONs(in: dir) }
        if let bundleDir = Bundle.module.url(forResource: "adapters", withExtension: nil, subdirectory: "Resources") {
            appendJSONs(in: bundleDir)
        }
        if let bundleDir = Bundle.module.url(forResource: "adapters", withExtension: nil) {
            appendJSONs(in: bundleDir)
        }
        return results.sorted()
    }

    // MARK: - Raw load

    private func load(from url: URL) -> SiteAdapterDefinition? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SiteAdapterDefinition.self, from: data)
        } catch {
            log.error("adapter decode failed url=\(url.path, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
