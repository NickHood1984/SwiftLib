import Foundation
import SwiftLibCore

/// Loads and caches AI service DOM selector configurations.
/// Bundled default → cached on disk → remote update from GitHub.
@MainActor
final class AIDOMSelectorService: ObservableObject {
    static let shared = AIDOMSelectorService()

    @Published private(set) var config: AIDOMConfig
    @Published private(set) var isUpdating = false
    @Published var lastUpdateError: String?

    private init() {
        config = Self.loadConfig()
    }

    // MARK: - Public

    /// Find the service config matching the given URL.
    func selectors(for urlString: String) -> AIDOMServiceConfig? {
        let lowered = urlString.lowercased()
        return config.services.first { lowered.contains($0.urlPattern.lowercased()) }
    }

    /// Fetch updated config from remote URL.
    func updateFromRemote() async {
        let remoteURL = SwiftLibPreferences.aiDOMSelectorsRemoteURL
        guard let url = URL(string: remoteURL), !remoteURL.isEmpty else {
            lastUpdateError = "未配置远程更新 URL"
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        do {
            let (data, response) = try await NetworkClient.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastUpdateError = "获取远程配置失败"
                return
            }

            let decoded = try JSONDecoder().decode(AIDOMConfig.self, from: data)
            if let rejectionReason = validate(candidate: decoded, current: config) {
                lastUpdateError = rejectionReason
                return
            }

            try data.write(to: Self.cachedConfigURL(), options: .atomic)
            config = decoded
            lastUpdateError = nil
            SwiftLibPreferences.aiDOMSelectorsLastUpdate = Date()
        } catch {
            lastUpdateError = error.localizedDescription
        }
    }

    /// Auto-update if >24h since last check.
    func autoUpdateIfNeeded() async {
        let lastUpdate = SwiftLibPreferences.aiDOMSelectorsLastUpdate
        if Date().timeIntervalSince(lastUpdate) > 86400 {
            await updateFromRemote()
        }
    }

    // MARK: - File I/O

    private static func cachedConfigURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftLib", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai-dom-selectors.json")
    }

    private static func loadConfig() -> AIDOMConfig {
        // Try cached version first
        let cachedURL = cachedConfigURL()
        if let data = try? Data(contentsOf: cachedURL),
           let config = try? JSONDecoder().decode(AIDOMConfig.self, from: data) {
            return config
        }

        // Fall back to bundled
        if let url = Bundle.module.url(forResource: "ai-dom-selectors", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AIDOMConfig.self, from: data) {
            return config
        }
        if let url = Bundle.module.url(forResource: "ai-dom-selectors", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AIDOMConfig.self, from: data) {
            return config
        }

        return AIDOMConfig(version: 0, lastUpdated: "", services: [])
    }

    private func validate(candidate: AIDOMConfig, current: AIDOMConfig) -> String? {
        guard !candidate.services.isEmpty else {
            return "远程配置为空，已忽略"
        }

        if candidate.version < current.version {
            return "远程配置版本较旧，已忽略"
        }

        if candidate.version == current.version,
           Self.compareLastUpdated(candidate.lastUpdated, current.lastUpdated) == .orderedAscending {
            return "远程配置更新时间较旧，已忽略"
        }

        return nil
    }

    private static func compareLastUpdated(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsDate = parseDate(lhs)
        let rhsDate = parseDate(rhs)

        switch (lhsDate, rhsDate) {
        case let (left?, right?):
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        default:
            return lhs.compare(rhs, options: [.numeric])
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Models

struct AIDOMConfig: Codable {
    let version: Int
    let lastUpdated: String
    let services: [AIDOMServiceConfig]
}

struct AIDOMServiceConfig: Codable {
    let id: String
    let name: String
    let urlPattern: String
    let inputSelector: String
    let sendSelector: String
    let responseSelector: String
    let contentSelector: String
    let streamingSelector: String
    let notes: String?
}
