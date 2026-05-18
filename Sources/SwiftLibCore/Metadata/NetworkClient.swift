import Foundation

/// Centralized HTTP client with a dedicated URLSession and sensible defaults.
/// Replaces scattered `URLSession.shared` usage across the codebase.
public enum NetworkClient {
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
}
