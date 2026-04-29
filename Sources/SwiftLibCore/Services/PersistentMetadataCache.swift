import Foundation
import GRDB

/// Persistent metadata cache backed by the SQLite `metadataCache` table (v12).
///
/// Provides cross-session caching for API responses. Falls back gracefully
/// to in-memory behavior if the database is unavailable.
public enum PersistentMetadataCache {

    /// Default TTL: 24 hours for API responses.
    public static let defaultTTL: TimeInterval = 86400

    /// Short TTL: 5 minutes for volatile data (e.g. citation counts).
    public static let shortTTL: TimeInterval = 300

    // MARK: - Read

    /// Retrieve a cached response by key and source API.
    /// Returns nil if not found or expired.
    public static func get(key: String, sourceAPI: String) -> String? {
        let db = AppDatabase.shared
        return try? db.dbWriter.read { db -> String? in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT responseJSON FROM metadataCache
                    WHERE cacheKey = ? AND sourceAPI = ? AND expiresAt > ?
                    """,
                arguments: [key, sourceAPI, Date()]
            )
            return row?["responseJSON"]
        }
    }

    /// Retrieve and decode a cached Codable value.
    public static func getDecoded<T: Decodable>(_ type: T.Type, key: String, sourceAPI: String) -> T? {
        guard let json = get(key: key, sourceAPI: sourceAPI),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Write

    /// Store a response in the persistent cache.
    public static func set(key: String, sourceAPI: String, responseJSON: String, ttl: TimeInterval = defaultTTL) {
        let db = AppDatabase.shared
        try? db.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO metadataCache (cacheKey, sourceAPI, responseJSON, fetchedAt, expiresAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [key, sourceAPI, responseJSON, Date(), Date().addingTimeInterval(ttl)]
            )
        }
    }

    /// Encode and store a Codable value.
    public static func setEncoded<T: Encodable>(_ value: T, key: String, sourceAPI: String, ttl: TimeInterval = defaultTTL) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        set(key: key, sourceAPI: sourceAPI, responseJSON: json, ttl: ttl)
    }

    // MARK: - Maintenance

    /// Remove all expired entries from the cache.
    public static func purgeExpired() {
        let db = AppDatabase.shared
        try? db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM metadataCache WHERE expiresAt <= ?", arguments: [Date()])
        }
    }

    /// Remove all entries for a specific source API.
    public static func invalidate(sourceAPI: String) {
        let db = AppDatabase.shared
        try? db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM metadataCache WHERE sourceAPI = ?", arguments: [sourceAPI])
        }
    }

    /// Remove a specific cached entry.
    public static func remove(key: String) {
        let db = AppDatabase.shared
        try? db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM metadataCache WHERE cacheKey = ?", arguments: [key])
        }
    }
}
