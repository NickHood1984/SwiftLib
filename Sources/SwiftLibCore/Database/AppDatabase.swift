import Foundation
import GRDB

public final class AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.makeMigrator().migrate(dbWriter)
        // SQLite recommends running PRAGMA optimize on long-lived connections.
        try? dbWriter.write { db in try db.execute(sql: "PRAGMA optimize") }
    }
}
