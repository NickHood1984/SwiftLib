import CryptoKit
import Foundation
import SwiftLibCore
import WebKit

@MainActor
final class WebSessionBroker {
    static let shared = WebSessionBroker()

    struct Profile: Hashable, Sendable {
        let id: String
        let displayName: String

        init(id: String, displayName: String? = nil) {
            self.id = id
            self.displayName = displayName?.swiftlib_nilIfBlank ?? id
        }
    }

    private var stores: [String: WKWebsiteDataStore] = [:]

    private init() {}

    func scholarlyProfile(for url: URL?) -> Profile {
        guard let url,
              let host = url.host?.lowercased().swiftlib_nilIfBlank else {
            return Profile(id: "scholarly-default", displayName: "Scholarly")
        }

        let segments = host.split(separator: ".")
        let key: String
        if segments.count >= 2 {
            key = segments.suffix(2).joined(separator: ".")
        } else {
            key = host
        }
        return Profile(id: "scholarly-\(key)", displayName: key)
    }

    func configure(_ configuration: WKWebViewConfiguration, profile: Profile) {
        configuration.websiteDataStore = dataStore(for: profile)
    }

    func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        if let existing = stores[profile.id] {
            return existing
        }

        let store = WKWebsiteDataStore(forIdentifier: Self.identifier(for: profile.id))
        stores[profile.id] = store
        return store
    }

    func cookies(for profile: Profile) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore(for: profile).httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func request(
        url: URL,
        profile: Profile,
        headers: [String: String] = [:],
        timeout: TimeInterval = 20
    ) async -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(ReaderExtractionManager.safariLikeUserAgent, forHTTPHeaderField: "User-Agent")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let matchingCookies = await cookies(for: profile).filter { $0.swiftlib_matches(url: url) }
        if !matchingCookies.isEmpty {
            for (key, value) in HTTPCookie.requestHeaderFields(with: matchingCookies) {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }

    private static func identifier(for profileID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(profileID.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return bytes.withUnsafeBufferPointer { buffer in
            let b = buffer.baseAddress!
            return UUID(uuid: (
                b[0], b[1], b[2], b[3],
                b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11],
                b[12], b[13], b[14], b[15]
            ))
        }
    }
}

private extension HTTPCookie {
    func swiftlib_matches(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        let normalizedDomain = domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !normalizedDomain.isEmpty else { return false }
        guard host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)") else {
            return false
        }

        let pathToMatch = path.swiftlib_nilIfBlank ?? "/"
        return url.path.hasPrefix(pathToMatch) || pathToMatch == "/"
    }
}
