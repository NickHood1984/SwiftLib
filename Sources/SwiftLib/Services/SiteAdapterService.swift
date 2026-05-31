import Foundation
import SwiftLibCore

/// Loads, caches, and matches site-specific metadata extraction adapters.
/// Pattern mirrors AIDOMSelectorService: bundled JSON → cached on disk → remote update.
@MainActor
final class SiteAdapterService: ObservableObject {
    static let shared = SiteAdapterService()

    @Published private(set) var config: SiteAdapterConfig
    @Published private(set) var isUpdating = false
    @Published var lastUpdateError: String?

    /// Cached JS runtime template (loaded once from bundle).
    private static var runtimeTemplate: String?

    private init() {
        config = Self.loadConfig()
    }

    // MARK: - Public

    /// Find a matching adapter for the given URL.
    func adapter(for urlString: String) -> SiteAdapter? {
        let lowered = urlString.lowercased()
        return config.adapters.first { adapter in
            adapter.urlPatterns.contains { lowered.contains($0.lowercased()) }
        }
    }

    /// Build a complete injectable JS script for the given adapter.
    /// Returns nil if the runtime template cannot be loaded.
    func buildScript(for adapter: SiteAdapter) -> String? {
        if let customScript = adapter.script?.swiftlib_nilIfBlank {
            if customScript.hasPrefix("@resource:") {
                let resourceName = String(customScript.dropFirst("@resource:".count))
                return Self.loadScriptResource(named: resourceName)
            }
            return customScript
        }

        guard let template = Self.loadRuntime() else { return nil }

        let configJSON: String
        do {
            let adapterPayload = AdapterPayload(
                id: adapter.id,
                referenceType: adapter.referenceType ?? "webpage",
                selectors: adapter.selectors,
                transforms: adapter.transforms ?? [:]
            )
            let data = try JSONEncoder().encode(adapterPayload)
            configJSON = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return nil
        }

        return template.replacingOccurrences(of: "%%ADAPTER_CONFIG%%", with: configJSON)
    }

    // MARK: - Remote Update

    /// Fetch updated config from remote.
    func updateFromRemote() async {
        let remoteURL = SwiftLibPreferences.siteAdaptersRemoteURL
        guard let url = URL(string: remoteURL), !remoteURL.isEmpty else {
            lastUpdateError = "未配置站点适配器远程 URL"
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        do {
            let (data, response) = try await NetworkClient.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastUpdateError = "获取远程站点适配器配置失败"
                return
            }

            let decoded = try JSONDecoder().decode(SiteAdapterConfig.self, from: data)
            if let rejection = validate(candidate: decoded, current: config) {
                lastUpdateError = rejection
                return
            }

            try data.write(to: Self.cachedConfigURL(), options: .atomic)
            config = decoded
            lastUpdateError = nil
            SwiftLibPreferences.siteAdaptersLastUpdate = Date()
        } catch {
            lastUpdateError = error.localizedDescription
        }
    }

    /// Auto-update if >24h since last check.
    func autoUpdateIfNeeded() async {
        let lastUpdate = SwiftLibPreferences.siteAdaptersLastUpdate
        if Date().timeIntervalSince(lastUpdate) > 86400 {
            await updateFromRemote()
            if SwiftLibPreferences.siteAdaptersLastUpdate == lastUpdate {
                SwiftLibPreferences.siteAdaptersLastUpdate = Date()
            }
        }
    }

    // MARK: - File I/O

    private static func cachedConfigURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftLib", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("site-adapters.json")
    }

    private static func loadConfig() -> SiteAdapterConfig {
        // Try cached version first
        let cachedURL = cachedConfigURL()
        if let data = try? Data(contentsOf: cachedURL),
           let config = try? JSONDecoder().decode(SiteAdapterConfig.self, from: data) {
            return config
        }

        // Fall back to bundled
        if let url = Bundle.module.url(forResource: "site-adapters", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(SiteAdapterConfig.self, from: data) {
            return config
        }
        if let url = Bundle.module.url(forResource: "site-adapters", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(SiteAdapterConfig.self, from: data) {
            return config
        }

        return SiteAdapterConfig(version: 0, lastUpdated: "", adapters: [])
    }

    private static func loadRuntime() -> String? {
        if let cached = runtimeTemplate { return cached }
        if let url = Bundle.module.url(forResource: "site-adapter-runtime", withExtension: "js", subdirectory: "Resources"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            runtimeTemplate = s
            return s
        }
        if let url = Bundle.module.url(forResource: "site-adapter-runtime", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            runtimeTemplate = s
            return s
        }
        return nil
    }

    private static func loadScriptResource(named name: String) -> String? {
        let resourceName: String
        let fileExtension: String?

        if let dotIndex = name.lastIndex(of: ".") {
            resourceName = String(name[..<dotIndex])
            fileExtension = String(name[name.index(after: dotIndex)...])
        } else {
            resourceName = name
            fileExtension = "js"
        }

        if let url = Bundle.module.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Resources"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            return script
        }
        if let url = Bundle.module.url(forResource: resourceName, withExtension: fileExtension),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            return script
        }
        return nil
    }

    private func validate(candidate: SiteAdapterConfig, current: SiteAdapterConfig) -> String? {
        guard !candidate.adapters.isEmpty else {
            return "远程站点适配器配置为空，已忽略"
        }
        if candidate.version < current.version {
            return "远程站点适配器版本较旧，已忽略"
        }
        return nil
    }
}

// MARK: - Models

struct SiteAdapterConfig: Codable {
    let version: Int
    let lastUpdated: String
    let adapters: [SiteAdapter]
}

struct SiteAdapter: Codable, Identifiable {
    let id: String
    let name: String
    let urlPatterns: [String]
    let referenceType: String?
    let selectors: [String: String]
    let transforms: [String: String]?

    /// Optional custom JS script (for complex sites that can't be handled with selectors alone).
    let script: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        urlPatterns = try container.decode([String].self, forKey: .urlPatterns)
        referenceType = try container.decodeIfPresent(String.self, forKey: .referenceType)
        selectors = try container.decodeIfPresent([String: String].self, forKey: .selectors) ?? [:]
        transforms = try container.decodeIfPresent([String: String].self, forKey: .transforms)
        script = try container.decodeIfPresent(String.self, forKey: .script)
    }
}

/// Payload sent to the JS runtime (subset of SiteAdapter for injection).
private struct AdapterPayload: Encodable {
    let id: String
    let referenceType: String
    let selectors: [String: String]
    let transforms: [String: String]
}
