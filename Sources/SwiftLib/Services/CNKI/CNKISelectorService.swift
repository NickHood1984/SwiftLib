import Foundation
import SwiftLibCore

/// Loads CNKI DOM selector groups with the same bundled/cache/remote pattern as AI DOM selectors.
@MainActor
final class CNKISelectorService: ObservableObject {
    static let shared = CNKISelectorService()

    @Published private(set) var config: CNKISelectorConfig
    @Published private(set) var isUpdating = false
    @Published var lastUpdateError: String?

    private init() {
        config = Self.loadConfig()
    }

    func updateFromRemote() async {
        let remoteURL = SwiftLibPreferences.cnkiSelectorsRemoteURL
        guard let url = URL(string: remoteURL), !remoteURL.isEmpty else {
            lastUpdateError = "未配置知网选择器远程 URL"
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        do {
            let (data, response) = try await NetworkClient.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastUpdateError = "获取远程知网选择器配置失败"
                return
            }

            let decoded = try JSONDecoder().decode(CNKISelectorConfig.self, from: data)
            if let rejection = validate(candidate: decoded, current: config) {
                lastUpdateError = rejection
                return
            }

            try data.write(to: Self.cachedConfigURL(), options: .atomic)
            config = decoded
            lastUpdateError = nil
            SwiftLibPreferences.cnkiSelectorsLastUpdate = Date()
        } catch {
            lastUpdateError = error.localizedDescription
        }
    }

    func autoUpdateIfNeeded() async {
        let lastUpdate = SwiftLibPreferences.cnkiSelectorsLastUpdate
        if Date().timeIntervalSince(lastUpdate) > 86_400 {
            await updateFromRemote()
        }
    }

    private static func cachedConfigURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftLib", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cnki-selectors.json")
    }

    private static func loadConfig() -> CNKISelectorConfig {
        let cachedURL = cachedConfigURL()
        let cachedConfig = loadCachedConfig(from: cachedURL)
        let bundledConfig = loadBundledConfig()

        switch (cachedConfig, bundledConfig) {
        case let (cached?, bundled?):
            if isBundledConfigNewer(bundled, than: cached) {
                try? bundledConfigData()?.write(to: cachedURL, options: .atomic)
                return bundled
            }
            return cached
        case let (cached?, nil):
            return cached
        case let (nil, bundled?):
            try? bundledConfigData()?.write(to: cachedURL, options: .atomic)
            return bundled
        default:
            return CNKISelectorConfig(version: 0, lastUpdated: "", groups: [:])
        }
    }

    private static func loadCachedConfig(from url: URL) -> CNKISelectorConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CNKISelectorConfig.self, from: data)
    }

    private static func loadBundledConfig() -> CNKISelectorConfig? {
        guard let data = bundledConfigData() else { return nil }
        return try? JSONDecoder().decode(CNKISelectorConfig.self, from: data)
    }

    private static func bundledConfigData() -> Data? {
        if let url = Bundle.module.url(forResource: "cnki-selectors", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if let url = Bundle.module.url(forResource: "cnki-selectors", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return nil
    }

    private static func isBundledConfigNewer(_ bundled: CNKISelectorConfig, than cached: CNKISelectorConfig) -> Bool {
        if bundled.version != cached.version {
            return bundled.version > cached.version
        }
        return compareLastUpdated(bundled.lastUpdated, cached.lastUpdated) == .orderedDescending
    }

    private func validate(candidate: CNKISelectorConfig, current: CNKISelectorConfig) -> String? {
        guard !candidate.groups.isEmpty else {
            return "远程知网选择器配置为空，已忽略"
        }

        let requiredGroups = ["searchRows", "detailTitle", "detailAuthors", "detailJournal", "detailAbstract"]
        for group in requiredGroups where candidate.groups[group]?.isEmpty != false {
            return "远程知网选择器缺少 \(group)，已忽略"
        }

        if candidate.version < current.version {
            return "远程知网选择器版本较旧，已忽略"
        }

        if candidate.version == current.version,
           Self.compareLastUpdated(candidate.lastUpdated, current.lastUpdated) == .orderedAscending {
            return "远程知网选择器更新时间较旧，已忽略"
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

struct CNKISelectorConfig: Codable {
    let version: Int
    let lastUpdated: String
    let groups: [String: [String]]
}
