import Foundation
import GRDB

// ---------------------------------------------------------------------------
// AppDatabase+CitationItemOptions
//
// Persistence for per-document cite-item options (locator, prefix, suffix,
// suppressAuthor) from the Word/WPS add-in.
//
// These options are stored in `citationItemOption` (migration v17). They are
// populated during `WordCitationDOCXProcessor.refreshDOCX` by reading the
// document's CustomXmlPart and back-filling into the database so that
// locator/prefix/suffix survive even if the CustomXmlPart is stripped.
// ---------------------------------------------------------------------------

// MARK: - Model

/// A single cite-item option record for one reference within one citation cluster.
public struct CitationItemOption: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: Int64?
    public var documentURI: String
    public var citationID: String
    public var refID: Int64
    public var locator: String?
    public var label: String?    // "page", "chapter", "section", …
    public var prefix: String?
    public var suffix: String?
    public var suppressAuthor: Bool
    public var updatedAt: Date

    public static let databaseTableName = "citationItemOption"

    public init(
        id: Int64? = nil,
        documentURI: String,
        citationID: String,
        refID: Int64,
        locator: String? = nil,
        label: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        suppressAuthor: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentURI = documentURI
        self.citationID = citationID
        self.refID = refID
        self.locator = locator
        self.label = label
        self.prefix = prefix
        self.suffix = suffix
        self.suppressAuthor = suppressAuthor
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - AppDatabase extension

extension AppDatabase {

    // MARK: - Upsert

    /// Insert or replace cite-item options for a document.
    ///
    /// Existing rows with the same (documentURI, citationID, refID) are replaced.
    public func upsertCitationItemOptions(_ options: [CitationItemOption]) throws {
        try dbWriter.write { db in
            for var option in options {
                // Delete existing row for this (documentURI, citationID, refID) first,
                // then insert fresh — simpler than a true upsert in SQLite 3.x.
                try db.execute(
                    sql: """
                        DELETE FROM citationItemOption
                        WHERE documentURI = ? AND citationID = ? AND refID = ?
                        """,
                    arguments: [option.documentURI, option.citationID, option.refID]
                )
                option.updatedAt = Date()
                try option.insert(db)
            }
        }
    }

    // MARK: - Fetch

    /// Fetch all cite-item options for a specific document.
    public func citationItemOptions(for documentURI: String) throws -> [CitationItemOption] {
        try dbWriter.read { db in
            try CitationItemOption.filter(Column("documentURI") == documentURI)
                .fetchAll(db)
        }
    }

    /// Fetch cite-item options for a specific citation cluster within a document.
    public func citationItemOptions(documentURI: String, citationID: String) throws -> [CitationItemOption] {
        try dbWriter.read { db in
            try CitationItemOption
                .filter(Column("documentURI") == documentURI && Column("citationID") == citationID)
                .fetchAll(db)
        }
    }

    /// Fetch all documents that have any locator/prefix/suffix for a given reference.
    public func citationItemOptions(for refID: Int64) throws -> [CitationItemOption] {
        try dbWriter.read { db in
            try CitationItemOption.filter(Column("refID") == refID)
                .order(Column("documentURI"), Column("citationID"))
                .fetchAll(db)
        }
    }

    // MARK: - Delete

    /// Remove all cite-item options for a document (e.g. when the file is deleted or renamed).
    public func deleteCitationItemOptions(for documentURI: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM citationItemOption WHERE documentURI = ?",
                arguments: [documentURI]
            )
        }
    }

    /// Remove cite-item options whose refID no longer exists in the library.
    public func purgeOrphanedCitationItemOptions() throws {
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    DELETE FROM citationItemOption
                    WHERE refID NOT IN (SELECT id FROM reference WHERE id IS NOT NULL)
                    """
            )
        }
    }
}
