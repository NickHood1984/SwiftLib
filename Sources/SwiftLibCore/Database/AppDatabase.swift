import Foundation
import GRDB
import os.log

private let appDatabaseLog = Logger(subsystem: "SwiftLib", category: "AppDatabase")

public final class AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
        // SQLite recommends running PRAGMA optimize on long-lived connections.
        try? dbWriter.write { db in try db.execute(sql: "PRAGMA optimize") }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Never wipe the user's live library by default. If a local developer
        // explicitly wants schema-change resets while iterating, they can opt in
        // via SWIFTLIB_RESET_DB_ON_SCHEMA_CHANGE=1 for that launch.
        migrator.eraseDatabaseOnSchemaChange =
            ProcessInfo.processInfo.environment["SWIFTLIB_RESET_DB_ON_SCHEMA_CHANGE"] == "1"
        #endif

        migrator.registerMigration("v1") { db in
            // Collections
            try db.create(table: "collection") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("icon", .text).notNull().defaults(to: "folder")
                t.column("dateCreated", .datetime).notNull()
                t.column("parentId", .integer).references("collection", onDelete: .setNull)
            }
            try db.create(index: "collection_parentId", on: "collection", columns: ["parentId"])

            // Tags
            try db.create(table: "tag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("color", .text).notNull().defaults(to: "#007AFF")
            }

            // References
            try db.create(table: "reference") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("authors", .text).notNull().defaults(to: "")
                t.column("authorsNormalized", .text).notNull().defaults(to: "")
                t.column("year", .integer)
                t.column("journal", .text)
                t.column("volume", .text)
                t.column("issue", .text)
                t.column("pages", .text)
                t.column("doi", .text)
                t.column("url", .text)
                t.column("abstract", .text)
                t.column("dateAdded", .datetime).notNull()
                t.column("dateModified", .datetime).notNull()
                t.column("pdfPath", .text)
                t.column("notes", .text)
                t.column("webContent", .text)
                t.column("siteName", .text)
                t.column("favicon", .text)
                t.column("referenceType", .text).notNull().defaults(to: "Journal Article")
                t.column("metadataSource", .text)
                t.column("verificationStatus", .text).notNull().defaults(to: VerificationStatus.legacy.rawValue)
                t.column("acceptedByRuleID", .text)
                t.column("recordKey", .text)
                t.column("verificationSourceURL", .text)
                t.column("evidenceBundleHash", .text)
                t.column("verifiedAt", .datetime)
                t.column("reviewedBy", .text)
                t.column("collectionId", .integer).references("collection", onDelete: .setNull)
            }

            // Indexes for fast queries
            try db.create(index: "reference_year", on: "reference", columns: ["year"])
            try db.create(index: "reference_dateAdded", on: "reference", columns: ["dateAdded"])
            try db.create(index: "reference_collectionId", on: "reference", columns: ["collectionId"])
            try db.create(index: "reference_doi", on: "reference", columns: ["doi"])
            try db.create(index: "reference_referenceType", on: "reference", columns: ["referenceType"])
            try db.create(index: "reference_authorsNormalized", on: "reference", columns: ["authorsNormalized"])
            try db.create(index: "reference_verificationStatus", on: "reference", columns: ["verificationStatus"])

            // FTS5 Full-Text Search virtual table
            try db.create(virtualTable: "referenceFts", using: FTS5()) { t in
                t.synchronize(withTable: "reference")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("authorsNormalized")
                t.column("journal")
                t.column("abstract")
                t.column("notes")
                t.column("webContent")
                t.column("siteName")
                t.column("doi")
            }

            // Reference-Tag pivot table
            try db.create(table: "referenceTag") { t in
                t.column("referenceId", .integer).notNull().references("reference", onDelete: .cascade)
                t.column("tagId", .integer).notNull().references("tag", onDelete: .cascade)
                t.primaryKey(["referenceId", "tagId"])
            }
            try db.create(index: "referenceTag_tagId", on: "referenceTag", columns: ["tagId"])
        }

        migrator.registerMigration("v2-structured-authors") { db in
            // Convert plain-text authors to JSON arrays
            let rows = try Row.fetchAll(db, sql: "SELECT id, authors FROM reference")
            for row in rows {
                let id: Int64 = row["id"]
                let plain: String = row["authors"] ?? ""
                guard !plain.isEmpty else { continue }
                // Skip if already JSON
                if plain.hasPrefix("[") { continue }
                let parsed = AuthorName.parseList(plain)
                if let data = try? JSONEncoder().encode(parsed),
                   let json = String(data: data, encoding: .utf8) {
                    try db.execute(sql: "UPDATE reference SET authors = ? WHERE id = ?", arguments: [json, id])
                }
            }
        }

        migrator.registerMigration("v3-pdf-annotations") { db in
            try db.create(table: "pdfAnnotation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("referenceId", .integer).notNull().references("reference", onDelete: .cascade)
                t.column("type", .text).notNull().defaults(to: "highlight")
                t.column("selectedText", .text)
                t.column("noteText", .text)
                t.column("color", .text).notNull().defaults(to: "#FFDE59")
                t.column("pageIndex", .integer).notNull()
                t.column("boundsX", .double).notNull()
                t.column("boundsY", .double).notNull()
                t.column("boundsWidth", .double).notNull()
                t.column("boundsHeight", .double).notNull()
                t.column("rectsData", .text).notNull().defaults(to: "[]")
                t.column("dateCreated", .datetime).notNull()
            }
            try db.create(index: "pdfAnnotation_referenceId", on: "pdfAnnotation", columns: ["referenceId"])
            try db.create(index: "pdfAnnotation_pageIndex", on: "pdfAnnotation", columns: ["pageIndex"])
        }

        migrator.registerMigration("v4-pdf-annotation-rects") { db in
            let hasRectsDataColumn = try db.columns(in: "pdfAnnotation")
                .contains { $0.name == "rectsData" }

            if !hasRectsDataColumn {
                try db.alter(table: "pdfAnnotation") { t in
                    t.add(column: "rectsData", .text).notNull().defaults(to: "[]")
                }
            }

            struct LegacyRect: Encodable {
                var x: Double
                var y: Double
                var width: Double
                var height: Double
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, boundsX, boundsY, boundsWidth, boundsHeight
                    FROM pdfAnnotation
                    WHERE rectsData = '[]' OR rectsData = ''
                    """
            )

            for row in rows {
                let id: Int64 = row["id"]
                let rect = LegacyRect(
                    x: row["boundsX"],
                    y: row["boundsY"],
                    width: row["boundsWidth"],
                    height: row["boundsHeight"]
                )

                if let data = try? JSONEncoder().encode([rect]),
                   let json = String(data: data, encoding: .utf8) {
                    try db.execute(
                        sql: "UPDATE pdfAnnotation SET rectsData = ? WHERE id = ?",
                        arguments: [json, id]
                    )
                }
            }
        }

        migrator.registerMigration("v5-web-content") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("webContent") {
                    t.add(column: "webContent", .text)
                }
                if !existingColumns.contains("siteName") {
                    t.add(column: "siteName", .text)
                }
                if !existingColumns.contains("favicon") {
                    t.add(column: "favicon", .text)
                }
            }

            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_au")

            if try db.tableExists("referenceFts") {
                try db.drop(table: "referenceFts")
            }

            try db.create(virtualTable: "referenceFts", using: FTS5()) { t in
                t.synchronize(withTable: "reference")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("authors")
                t.column("journal")
                t.column("abstract")
                t.column("notes")
                t.column("webContent")
                t.column("siteName")
                t.column("doi")
            }

            try db.execute(sql: "INSERT INTO referenceFts(referenceFts) VALUES('rebuild')")
        }

        migrator.registerMigration("v6-web-annotations") { db in
            try db.create(table: "webAnnotation", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("referenceId", .integer).notNull().references("reference", onDelete: .cascade)
                t.column("type", .text).notNull().defaults(to: AnnotationType.highlight.rawValue)
                t.column("selectedText", .text).notNull()
                t.column("noteText", .text)
                t.column("color", .text).notNull().defaults(to: "#FFDE59")
                t.column("anchorText", .text).notNull()
                t.column("prefixText", .text)
                t.column("suffixText", .text)
                t.column("dateCreated", .datetime).notNull()
            }
            try db.create(index: "webAnnotation_referenceId", on: "webAnnotation", columns: ["referenceId"], ifNotExists: true)
            try db.create(index: "webAnnotation_dateCreated", on: "webAnnotation", columns: ["dateCreated"], ifNotExists: true)
        }

        migrator.registerMigration("v7-extended-metadata") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                // P0 fields
                if !existingColumns.contains("publisher") {
                    t.add(column: "publisher", .text)
                }
                if !existingColumns.contains("publisherPlace") {
                    t.add(column: "publisherPlace", .text)
                }
                if !existingColumns.contains("edition") {
                    t.add(column: "edition", .text)
                }
                if !existingColumns.contains("editors") {
                    t.add(column: "editors", .text)
                }
                if !existingColumns.contains("isbn") {
                    t.add(column: "isbn", .text)
                }
                if !existingColumns.contains("issn") {
                    t.add(column: "issn", .text)
                }
                if !existingColumns.contains("accessedDate") {
                    t.add(column: "accessedDate", .text)
                }
                if !existingColumns.contains("issuedMonth") {
                    t.add(column: "issuedMonth", .integer)
                }
                if !existingColumns.contains("issuedDay") {
                    t.add(column: "issuedDay", .integer)
                }
                // P1 fields
                if !existingColumns.contains("translators") {
                    t.add(column: "translators", .text)
                }
                if !existingColumns.contains("eventTitle") {
                    t.add(column: "eventTitle", .text)
                }
                if !existingColumns.contains("eventPlace") {
                    t.add(column: "eventPlace", .text)
                }
                if !existingColumns.contains("genre") {
                    t.add(column: "genre", .text)
                }
                if !existingColumns.contains("number") {
                    t.add(column: "number", .text)
                }
                if !existingColumns.contains("collectionTitle") {
                    t.add(column: "collectionTitle", .text)
                }
                if !existingColumns.contains("numberOfPages") {
                    t.add(column: "numberOfPages", .text)
                }
                // P2 fields
                if !existingColumns.contains("language") {
                    t.add(column: "language", .text)
                }
                if !existingColumns.contains("pmid") {
                    t.add(column: "pmid", .text)
                }
                if !existingColumns.contains("pmcid") {
                    t.add(column: "pmcid", .text)
                }
            }

            // Rebuild FTS5 to include new searchable fields
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_au")

            if try db.tableExists("referenceFts") {
                try db.drop(table: "referenceFts")
            }

            try db.create(virtualTable: "referenceFts", using: FTS5()) { t in
                t.synchronize(withTable: "reference")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("authors")
                t.column("journal")
                t.column("abstract")
                t.column("notes")
                t.column("webContent")
                t.column("siteName")
                t.column("doi")
                t.column("publisher")
                t.column("isbn")
                t.column("issn")
            }

            try db.execute(sql: "INSERT INTO referenceFts(referenceFts) VALUES('rebuild')")
        }

        migrator.registerMigration("v8-reference-search-hardening") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("authorsNormalized") {
                    t.add(column: "authorsNormalized", .text).notNull().defaults(to: "")
                }
            }

            try db.create(index: "reference_authorsNormalized", on: "reference", columns: ["authorsNormalized"], ifNotExists: true)
            try db.create(index: "reference_pmid", on: "reference", columns: ["pmid"], ifNotExists: true)
            try db.create(index: "reference_pmcid", on: "reference", columns: ["pmcid"], ifNotExists: true)

            let rows = try Row.fetchAll(db, sql: "SELECT id, authors FROM reference")
            for row in rows {
                let id: Int64 = row["id"]
                let rawAuthors: String = row["authors"] ?? ""

                let normalized: String = {
                    guard !rawAuthors.isEmpty else { return "" }
                    if let data = rawAuthors.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([AuthorName].self, from: data) {
                        return decoded.normalizedSearchString
                    }
                    return AuthorName.parseList(rawAuthors).normalizedSearchString
                }()

                try db.execute(
                    sql: "UPDATE reference SET authorsNormalized = ? WHERE id = ?",
                    arguments: [normalized, id]
                )
            }

            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_au")

            if try db.tableExists("referenceFts") {
                try db.drop(table: "referenceFts")
            }

            try db.create(virtualTable: "referenceFts", using: FTS5()) { t in
                t.synchronize(withTable: "reference")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("authorsNormalized")
                t.column("journal")
                t.column("abstract")
                t.column("notes")
                t.column("webContent")
                t.column("siteName")
                t.column("doi")
                t.column("publisher")
                t.column("isbn")
                t.column("issn")
            }

            try db.execute(sql: "INSERT INTO referenceFts(referenceFts) VALUES('rebuild')")
        }

        migrator.registerMigration("v9-metadata-source-and-institution") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("metadataSource") {
                    t.add(column: "metadataSource", .text)
                }
                if !existingColumns.contains("institution") {
                    t.add(column: "institution", .text)
                }
            }

            try db.create(index: "reference_metadataSource", on: "reference", columns: ["metadataSource"], ifNotExists: true)
            try db.create(index: "reference_isbn", on: "reference", columns: ["isbn"], ifNotExists: true)
            try db.create(index: "reference_issn", on: "reference", columns: ["issn"], ifNotExists: true)

            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __referenceFts_au")

            if try db.tableExists("referenceFts") {
                try db.drop(table: "referenceFts")
            }

            try db.create(virtualTable: "referenceFts", using: FTS5()) { t in
                t.synchronize(withTable: "reference")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("authorsNormalized")
                t.column("journal")
                t.column("abstract")
                t.column("notes")
                t.column("webContent")
                t.column("siteName")
                t.column("doi")
                t.column("publisher")
                t.column("isbn")
                t.column("issn")
                t.column("institution")
            }

            try db.execute(sql: "INSERT INTO referenceFts(referenceFts) VALUES('rebuild')")
        }

        migrator.registerMigration("v10-verification-pipeline") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("verificationStatus") {
                    t.add(column: "verificationStatus", .text).notNull().defaults(to: VerificationStatus.legacy.rawValue)
                }
                if !existingColumns.contains("acceptedByRuleID") {
                    t.add(column: "acceptedByRuleID", .text)
                }
                if !existingColumns.contains("recordKey") {
                    t.add(column: "recordKey", .text)
                }
                if !existingColumns.contains("verificationSourceURL") {
                    t.add(column: "verificationSourceURL", .text)
                }
                if !existingColumns.contains("evidenceBundleHash") {
                    t.add(column: "evidenceBundleHash", .text)
                }
                if !existingColumns.contains("verifiedAt") {
                    t.add(column: "verifiedAt", .datetime)
                }
                if !existingColumns.contains("reviewedBy") {
                    t.add(column: "reviewedBy", .text)
                }
            }

            try db.create(index: "reference_verificationStatus", on: "reference", columns: ["verificationStatus"], ifNotExists: true)
            try db.create(index: "reference_recordKey", on: "reference", columns: ["recordKey"], ifNotExists: true)
            try db.create(index: "reference_evidenceBundleHash", on: "reference", columns: ["evidenceBundleHash"], ifNotExists: true)

            try db.create(table: "metadataIntake", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceKind", .text).notNull()
                t.column("verificationStatus", .text).notNull()
                t.column("title", .text).notNull()
                t.column("originalInput", .text)
                t.column("sourceURL", .text)
                t.column("pdfPath", .text)
                t.column("seedJSON", .text)
                t.column("fallbackReferenceJSON", .text)
                t.column("currentReferenceJSON", .text)
                t.column("candidatesJSON", .text)
                t.column("statusMessage", .text)
                t.column("linkedReferenceId", .integer).references("reference", onDelete: .setNull)
                t.column("evidenceBundleHash", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "metadataIntake_verificationStatus", on: "metadataIntake", columns: ["verificationStatus"], ifNotExists: true)
            try db.create(index: "metadataIntake_linkedReferenceId", on: "metadataIntake", columns: ["linkedReferenceId"], ifNotExists: true)
            try db.create(index: "metadataIntake_updatedAt", on: "metadataIntake", columns: ["updatedAt"], ifNotExists: true)

            try db.create(table: "metadataEvidence", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("intakeId", .integer).references("metadataIntake", onDelete: .cascade)
                t.column("referenceId", .integer).references("reference", onDelete: .cascade)
                t.column("bundleHash", .text).notNull()
                t.column("source", .text).notNull()
                t.column("recordKey", .text)
                t.column("sourceURL", .text)
                t.column("fetchMode", .text).notNull()
                t.column("payloadJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(index: "metadataEvidence_bundleHash", on: "metadataEvidence", columns: ["bundleHash"], ifNotExists: true)
            try db.create(index: "metadataEvidence_intakeId", on: "metadataEvidence", columns: ["intakeId"], ifNotExists: true)
            try db.create(index: "metadataEvidence_referenceId", on: "metadataEvidence", columns: ["referenceId"], ifNotExists: true)

            try db.execute(
                sql: """
                UPDATE reference
                SET verificationStatus = COALESCE(NULLIF(verificationStatus, ''), ?)
                """,
                arguments: [VerificationStatus.legacy.rawValue]
            )
        }

        // ── v11: Normalized dedup columns + PRAGMA optimize ──────────────
        migrator.registerMigration("v11-normalized-dedup-columns") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("doiNormalized") {
                    t.add(column: "doiNormalized", .text)
                }
                if !existingColumns.contains("isbnNormalized") {
                    t.add(column: "isbnNormalized", .text)
                }
                if !existingColumns.contains("issnNormalized") {
                    t.add(column: "issnNormalized", .text)
                }
                if !existingColumns.contains("pmcidNormalized") {
                    t.add(column: "pmcidNormalized", .text)
                }
            }

            // Back-fill normalized values from existing data using the same
            // logic as the Swift-side normalizers (case folding, stripping).
            try db.execute(sql: """
                UPDATE reference SET
                    doiNormalized  = CASE WHEN TRIM(COALESCE(doi,'')) != '' THEN LOWER(TRIM(doi)) ELSE NULL END,
                    isbnNormalized = CASE WHEN TRIM(COALESCE(isbn,'')) != '' THEN REPLACE(REPLACE(UPPER(isbn), '-', ''), ' ', '') ELSE NULL END,
                    issnNormalized = CASE WHEN TRIM(COALESCE(issn,'')) != '' THEN REPLACE(REPLACE(UPPER(issn), '-', ''), ' ', '') ELSE NULL END,
                    pmcidNormalized = CASE WHEN TRIM(COALESCE(pmcid,'')) != '' THEN UPPER(TRIM(pmcid)) ELSE NULL END
            """)

            // Create indexes on the new columns (after back-fill for speed).
            try db.create(index: "reference_doiNormalized", on: "reference", columns: ["doiNormalized"], ifNotExists: true)
            try db.create(index: "reference_isbnNormalized", on: "reference", columns: ["isbnNormalized"], ifNotExists: true)
            try db.create(index: "reference_issnNormalized", on: "reference", columns: ["issnNormalized"], ifNotExists: true)
            try db.create(index: "reference_pmcidNormalized", on: "reference", columns: ["pmcidNormalized"], ifNotExists: true)

            // Run SQLite's built-in optimizer for long-lived connections.
            try db.execute(sql: "PRAGMA optimize")
        }

        return migrator
    }
}

// MARK: - Database Access
extension AppDatabase {
    public enum SharedStorageMode: Sendable {
        case persistent
        case inMemoryFallback
    }

    private struct SharedBootstrap {
        let database: AppDatabase
        let storageMode: SharedStorageMode
        let startupErrorDescription: String?
    }

    private static let sharedBootstrap = makeSharedBootstrap()

    /// Compatibility accessor for callers that only need a usable shared database.
    public static let sharedResult: Result<AppDatabase, Error> = .success(sharedBootstrap.database)

    public static var shared: AppDatabase { sharedBootstrap.database }

    public static var sharedStorageMode: SharedStorageMode { sharedBootstrap.storageMode }

    public static var sharedStartupErrorDescription: String? {
        sharedBootstrap.startupErrorDescription
    }

    private static func preferredStorageRoot(named leaf: String) -> URL {
        let fm = FileManager.default
        let candidates: [URL] = [
            (try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )),
            fm.temporaryDirectory.appendingPathComponent("SwiftLibFallback", isDirectory: true),
        ].compactMap { $0 }

        for base in candidates {
            let dirURL = base.appendingPathComponent(leaf, isDirectory: true)
            do {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                return dirURL
            } catch {
                appDatabaseLog.error("Failed to create directory at \(dirURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return fm.temporaryDirectory.appendingPathComponent(leaf, isDirectory: true)
    }

    private static func makeSharedBootstrap() -> SharedBootstrap {
        let dirURL = preferredStorageRoot(named: "SwiftLib")
        do {
            let dbURL = dirURL.appendingPathComponent("library.sqlite")
            var config = Configuration()
            #if DEBUG
            if SwiftLibCoreDebugLogging.sqlTrace {
                config.prepareDatabase { db in
                    db.trace { print("SQL: \($0)") }
                }
            }
            #endif
            let dbPool = try DatabasePool(path: dbURL.path, configuration: config)

            return SharedBootstrap(
                database: try AppDatabase(dbPool),
                storageMode: .persistent,
                startupErrorDescription: nil
            )
        } catch {
            appDatabaseLog.error("Primary database setup failed at \(dirURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")

            do {
                return SharedBootstrap(
                    database: try AppDatabase(DatabaseQueue(path: ":memory:")),
                    storageMode: .inMemoryFallback,
                    startupErrorDescription: error.localizedDescription
                )
            } catch {
                preconditionFailure("Unable to initialize in-memory database fallback: \(error.localizedDescription)")
            }
        }
    }

    /// PDF storage directory
    public static var pdfStorageURL: URL {
        preferredStorageRoot(named: "SwiftLib/PDFs")
    }

    public static var metadataArtifactsURL: URL {
        preferredStorageRoot(named: "SwiftLib/MetadataArtifacts")
    }
}

// MARK: - Reference CRUD
extension AppDatabase {
    public func saveReference(_ reference: inout Reference) throws {
        try dbWriter.write { db in
            try normalizeForDirectLibrarySave(&reference)

            if reference.id == nil {
                try ensureLibraryReady(reference)
            }

            if reference.id == nil,
               let duplicateId = try findDuplicateReferenceID(for: reference, db: db),
               var existing = try Reference.fetchOne(db, id: duplicateId) {
                existing = mergedReference(existing: existing, incoming: reference)
                try existing.save(db)
                reference = existing
            } else {
                try reference.save(db)
            }
        }
    }

    public func updateReferenceWebContent(id: Int64, webContent: String?) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE reference SET webContent = ?, dateModified = ? WHERE id = ?",
                arguments: [webContent, Date(), id]
            )
        }
    }

    public func deleteReferences(ids: [Int64]) throws {
        try dbWriter.write { db in
            _ = try Reference.deleteAll(db, ids: ids)
        }
    }

    /// Collect associated PDF paths inside the same transaction so callers can
    /// safely delete files only after the database delete succeeds.
    public func deleteReferencesReturningPDFPaths(ids: [Int64]) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        return try dbWriter.write { db in
            let references = try Reference
                .filter(ids.contains(Reference.Columns.id))
                .fetchAll(db)
            let pdfPaths = references.compactMap(\.pdfPath)
            _ = try Reference.deleteAll(db, ids: ids)
            return pdfPaths
        }
    }

    /// Batch-move references to a collection (or nil to remove from collection).
    /// Uses a single SQL UPDATE for optimal performance.
    public func moveReferences(ids: [Int64], toCollectionId: Int64?) throws {
        guard !ids.isEmpty else { return }
        _ = try dbWriter.write { db in
            try Reference
                .filter(ids.contains(Reference.Columns.id))
                .updateAll(db, Reference.Columns.collectionId.set(to: toCollectionId))
        }
    }

    public func fetchAllReferences(limit: Int = 0, offset: Int = 0) throws -> [Reference] {
        try dbWriter.read { db in
            var query = Reference.order(Reference.Columns.dateAdded.desc)
            if limit > 0 {
                query = query.limit(limit, offset: offset > 0 ? offset : nil)
            } else if offset > 0 {
                query = query.limit(-1, offset: offset)
            }
            return try query.fetchAll(db)
        }
    }

    /// Fetch a single reference by primary key, or nil if not found.
    public func fetchReference(id: Int64) throws -> Reference? {
        try dbWriter.read { db in
            try Reference.fetchOne(db, id: id)
        }
    }

    public func fetchReferences(collectionId: Int64) throws -> [Reference] {
        try dbWriter.read { db in
            try Reference
                .filter(Reference.Columns.collectionId == collectionId)
                .order(Reference.Columns.dateAdded.desc)
                .fetchAll(db)
        }
    }

    public func fetchReferences(ids: [Int64]) throws -> [Reference] {
        guard !ids.isEmpty else { return [] }
        return try dbWriter.read { db in
            try Reference
                .filter(ids.contains(Reference.Columns.id))
                .fetchAll(db)
        }
    }

    public func fetchWebContent(id: Int64) throws -> String? {
        try dbWriter.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT webContent FROM reference WHERE id = ?",
                arguments: [id]
            )
            let webContent: String? = row?["webContent"]
            return webContent
        }
    }

    public func hasWebContent(id: Int64) throws -> Bool {
        try dbWriter.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT webContent
                    FROM reference
                    WHERE id = ?
                    LIMIT 1
                    """,
                arguments: [id]
            )
            let value: String? = row?["webContent"]
            return !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    public func fetchReferences(tagId: Int64) throws -> [Reference] {
        try dbWriter.read { db in
            let request = Reference
                .joining(required: Reference.referenceTagPivot
                    .filter(ReferenceTag.Columns.tagId == tagId))
                .order(Reference.Columns.dateAdded.desc)
            return try request.fetchAll(db)
        }
    }

    /// FTS5 full-text search with prefix matching — "smi" matches "Smith"
    public func searchReferences(query: String, limit: Int = 20) throws -> [Reference] {
        return try dbWriter.read { db in
            var filter = ReferenceFilter()
            filter.keyword = query
            return try fetchReferences(db: db, scope: .all, filter: filter, limit: limit)
        }
    }

    /// Batch import — uses single transaction for maximum speed
    /// 10,000 records in ~200ms on Apple Silicon
    public func batchImportReferences(_ references: [Reference]) throws -> Int {
        guard !references.isEmpty else { return 0 }
        return try dbWriter.write { db in
            var count = 0
            for var ref in references {
                try normalizeForDirectLibrarySave(&ref)
                try ensureLibraryReady(ref)
                if let duplicateId = try findDuplicateReferenceID(for: ref, db: db),
                   var existing = try Reference.fetchOne(db, id: duplicateId) {
                    existing = mergedReference(existing: existing, incoming: ref)
                    try existing.save(db)
                } else {
                    try ref.insert(db)
                }
                count += 1
            }
            return count
        }
    }

    public func saveMetadataIntake(_ intake: inout MetadataIntake) throws {
        try dbWriter.write { db in
            intake.updatedAt = Date()
            if intake.createdAt > intake.updatedAt {
                intake.createdAt = intake.updatedAt
            }
            try intake.save(db)
        }
    }

    public func deleteMetadataIntake(id: Int64) throws {
        try dbWriter.write { db in
            _ = try MetadataIntake.deleteOne(db, id: id)
        }
    }

    public func fetchPendingMetadataIntakes() throws -> [MetadataIntake] {
        try dbWriter.read { db in
            try MetadataIntake
                .filter(
                    [VerificationStatus.seedOnly.rawValue,
                     VerificationStatus.candidate.rawValue,
                     VerificationStatus.blocked.rawValue,
                     VerificationStatus.rejectedAmbiguous.rawValue]
                        .contains(MetadataIntake.Columns.verificationStatus)
                )
                .order(MetadataIntake.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    public func saveMetadataEvidence(_ evidence: inout MetadataEvidence) throws {
        try dbWriter.write { db in
            try evidence.save(db)
        }
    }

    public func persistMetadataResolution(
        _ result: MetadataResolutionResult,
        options: MetadataPersistenceOptions
    ) throws -> MetadataPersistenceResult {
        try dbWriter.write { db in
            switch result {
            case .verified(var envelope):
                if let preferredPDFPath = options.preferredPDFPath?.swiftlib_nilIfBlank,
                   envelope.reference.pdfPath == nil {
                    envelope.reference.pdfPath = preferredPDFPath
                }
                try ensureLibraryReady(envelope.reference)
                try saveResolvedReference(
                    &envelope.reference,
                    linkedReferenceId: options.linkedReferenceId,
                    db: db
                )

                if let existingIntakeId = options.existingIntakeId,
                   var existingIntake = try MetadataIntake.fetchOne(db, id: existingIntakeId) {
                    existingIntake.verificationStatus = envelope.reference.verificationStatus
                    existingIntake.linkedReferenceId = envelope.reference.id
                    existingIntake.currentReferenceJSON = MetadataVerificationCodec.encodeToJSONString(envelope.reference)
                    existingIntake.evidenceBundleHash = envelope.reference.evidenceBundleHash
                    existingIntake.statusMessage = envelope.reference.verificationStatus.displayName
                    existingIntake.updatedAt = Date()
                    try existingIntake.save(db)
                }

                try upsertEvidence(bundle: envelope.evidence, intakeId: options.existingIntakeId, referenceId: envelope.reference.id, db: db)
                return .verified(envelope.reference)

            case .candidate(let envelope):
                var intake = buildMetadataIntake(
                    status: .candidate,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: envelope.candidates,
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                return .intake(intake)

            case .blocked(let envelope):
                var intake = buildMetadataIntake(
                    status: .blocked,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: envelope.candidates,
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                return .intake(intake)

            case .seedOnly(let envelope):
                var intake = buildMetadataIntake(
                    status: .seedOnly,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: [],
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                return .intake(intake)

            case .rejected(let envelope):
                var intake = buildMetadataIntake(
                    status: .rejectedAmbiguous,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: [],
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                return .intake(intake)
            }
        }
    }

    public func confirmMetadataIntake(
        _ intake: MetadataIntake,
        reviewedBy: String?
    ) throws -> Reference {
        guard var reference = intake.bestAvailableReference else {
            throw NSError(
                domain: "SwiftLib.MetadataIntake",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "当前待验证条目缺少可确认的元数据快照。"]
            )
        }

        reference = MetadataVerifier.manuallyVerified(reference, reviewedBy: reviewedBy)
        if let pdfPath = intake.pdfPath?.swiftlib_nilIfBlank, reference.pdfPath == nil {
            reference.pdfPath = pdfPath
        }

        try dbWriter.write { db in
            try normalizeForDirectLibrarySave(&reference)
            try ensureLibraryReady(reference)
            try saveResolvedReference(
                &reference,
                linkedReferenceId: intake.linkedReferenceId,
                db: db
            )

            if var storedIntake = try MetadataIntake.fetchOne(db, id: intake.id) {
                storedIntake.verificationStatus = .verifiedManual
                storedIntake.linkedReferenceId = reference.id
                storedIntake.currentReferenceJSON = MetadataVerificationCodec.encodeToJSONString(reference)
                storedIntake.updatedAt = Date()
                storedIntake.statusMessage = "人工确认入库"
                try storedIntake.save(db)
            }
        }

        return reference
    }

    public func fetchReferences(
        scope: ReferenceScope,
        filter: ReferenceFilter,
        limit: Int = 0,
        offset: Int = 0
    ) throws -> [Reference] {
        try dbWriter.read { db in
            try fetchReferences(db: db, scope: scope, filter: filter, limit: limit, offset: offset)
        }
    }

    public func referenceCount() throws -> Int {
        try dbWriter.read { db in
            try Reference.fetchCount(db)
        }
    }

    public func referenceCount(collectionId: Int64) throws -> Int {
        try dbWriter.read { db in
            try Reference.filter(Reference.Columns.collectionId == collectionId).fetchCount(db)
        }
    }

    private func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    private func normalizedDOI(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    private func normalizedPMID(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    private func normalizedPMCID(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.uppercased()
    }

    private func normalizedISBN(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        guard normalized.count == 10 || normalized.count == 13 else { return nil }
        return normalized
    }

    private func normalizedISSN(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #"[^0-9Xx]"#, with: "", options: .regularExpression).uppercased()
        guard normalized.count == 8 else { return nil }
        return normalized
    }

    private func normalizeForDedup(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let folded = (raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return folded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTitleKey(_ value: String?) -> String? {
        guard let normalized = normalizeForDedup(value) else { return nil }
        return normalized
            .replacingOccurrences(of: #"[[:punct:]\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForDirectLibrarySave(_ reference: inout Reference) throws {
        guard reference.id == nil,
              !reference.verificationStatus.isLibraryReady,
              reference.metadataSource == nil else {
            return
        }

        reference = MetadataVerifier.manuallyVerified(reference, reviewedBy: "direct-save")
    }

    private func ensureLibraryReady(_ reference: Reference) throws {
        guard reference.verificationStatus.isLibraryReady else {
            throw NSError(
                domain: "SwiftLib.AppDatabase",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "只有 verifiedAuto 或 verifiedManual 条目可写入正式资料库。"]
            )
        }
    }

    private func buildMetadataIntake(
        status: VerificationStatus,
        message: String,
        seed: MetadataResolutionSeed?,
        fallbackReference: Reference?,
        currentReference: Reference?,
        candidates: [MetadataCandidate],
        evidence: EvidenceBundle?,
        options: MetadataPersistenceOptions
    ) -> MetadataIntake {
        let title = currentReference?.title.swiftlib_nilIfBlank
            ?? fallbackReference?.title.swiftlib_nilIfBlank
            ?? seed?.title.swiftlib_nilIfBlank
            ?? options.originalInput?.swiftlib_nilIfBlank
            ?? "待验证元数据"

        return MetadataIntake(
            id: options.existingIntakeId,
            sourceKind: options.sourceKind,
            verificationStatus: status,
            title: title,
            originalInput: options.originalInput,
            sourceURL: currentReference?.verificationSourceURL
                ?? currentReference?.url
                ?? fallbackReference?.url
                ?? seed?.sourceURL,
            pdfPath: options.preferredPDFPath?.swiftlib_nilIfBlank ?? fallbackReference?.pdfPath ?? currentReference?.pdfPath,
            seedJSON: MetadataVerificationCodec.encodeToJSONString(seed),
            fallbackReferenceJSON: MetadataVerificationCodec.encodeToJSONString(fallbackReference),
            currentReferenceJSON: MetadataVerificationCodec.encodeToJSONString(currentReference),
            candidatesJSON: MetadataVerificationCodec.encodeToJSONString(candidates),
            statusMessage: message,
            linkedReferenceId: options.linkedReferenceId,
            evidenceBundleHash: evidence?.bundleHash
        )
    }

    private func saveResolvedReference(
        _ reference: inout Reference,
        linkedReferenceId: Int64?,
        db: Database
    ) throws {
        if let linkedReferenceId,
           var linkedReference = try Reference.fetchOne(db, id: linkedReferenceId) {
            linkedReference = mergedReference(existing: linkedReference, incoming: reference)
            try linkedReference.save(db)
            reference = linkedReference
            return
        }

        if reference.id == nil,
           let duplicateId = try findDuplicateReferenceID(for: reference, db: db),
           var existing = try Reference.fetchOne(db, id: duplicateId) {
            existing = mergedReference(existing: existing, incoming: reference)
            try existing.save(db)
            reference = existing
            return
        }

        try reference.save(db)
    }

    private func upsertEvidence(
        bundle: EvidenceBundle?,
        intakeId: Int64?,
        referenceId: Int64?,
        db: Database
    ) throws {
        guard let bundle,
              let bundleHash = bundle.bundleHash,
              let payloadJSON = MetadataVerificationCodec.encodeToJSONString(bundle) else {
            return
        }

        if var existing = try MetadataEvidence
            .filter(MetadataEvidence.Columns.bundleHash == bundleHash)
            .fetchOne(db) {
            existing.intakeId = intakeId ?? existing.intakeId
            existing.referenceId = referenceId ?? existing.referenceId
            existing.payloadJSON = payloadJSON
            try existing.save(db)
            return
        }

        var evidence = MetadataEvidence(
            intakeId: intakeId,
            referenceId: referenceId,
            bundleHash: bundleHash,
            source: bundle.source,
            recordKey: bundle.recordKey,
            sourceURL: bundle.sourceURL,
            fetchMode: bundle.fetchMode,
            payloadJSON: payloadJSON
        )
        try evidence.save(db)
    }

    private func findDuplicateReferenceID(for reference: Reference, db: Database) throws -> Int64? {
        if let doi = normalizedDOI(reference.doi),
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE doiNormalized = ? LIMIT 1", arguments: [doi]) {
            return id
        }

        if let pmid = normalizedPMID(reference.pmid),
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE pmid = ? LIMIT 1", arguments: [pmid]) {
            return id
        }

        if let pmcid = normalizedPMCID(reference.pmcid),
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE pmcidNormalized = ? LIMIT 1", arguments: [pmcid]) {
            return id
        }

        if let isbn = normalizedISBN(reference.isbn),
           let id = try Int64.fetchOne(
            db,
            sql: "SELECT id FROM reference WHERE isbnNormalized = ? LIMIT 1",
            arguments: [isbn]
           ) {
            return id
        }

        if let url = reference.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
           let id = try Int64.fetchOne(db, sql: "SELECT id FROM reference WHERE url = ? LIMIT 1", arguments: [url]) {
            return id
        }

        if let issn = normalizedISSN(reference.issn),
           let normalizedTitle = normalizedTitleKey(reference.title), !normalizedTitle.isEmpty,
           let year = reference.year {
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title
                    FROM reference
                    WHERE issnNormalized = ?
                      AND year = ?
                    LIMIT 20
                    """,
                arguments: [issn, year]
            )
            if let match = rows.first(where: { normalizedTitleKey(($0["title"] as String?)) == normalizedTitle }) {
                return match["id"]
            }
        }

        if let normalizedTitle = normalizedTitleKey(reference.title), !normalizedTitle.isEmpty,
           let year = reference.year,
           let normalizedAuthors = normalizeForDedup(reference.authorsNormalized), !normalizedAuthors.isEmpty {
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title
                    FROM reference
                    WHERE year = ?
                      AND authorsNormalized = ?
                    LIMIT 50
                    """,
                arguments: [year, normalizedAuthors]
            )
            if let match = rows.first(where: { normalizedTitleKey(($0["title"] as String?)) == normalizedTitle }) {
                return match["id"]
            }
        }

        return nil
    }

    private func mergedReference(existing: Reference, incoming: Reference) -> Reference {
        func preferred(_ incoming: String?, over existing: String?) -> String? {
            let candidate = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let candidate, !candidate.isEmpty { return candidate }
            return existing
        }

        func preferredLongest(_ incoming: String?, over existing: String?) -> String? {
            let lhs = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (lhs?.isEmpty == false ? lhs : nil, rhs?.isEmpty == false ? rhs : nil) {
            case let (l?, r?): return l.count >= r.count ? l : r
            case let (l?, nil): return l
            case let (nil, r?): return r
            default: return nil
            }
        }

        var merged = existing
        merged.title = preferred(incoming.title, over: existing.title) ?? existing.title
        merged.authors = incoming.authors.isEmpty ? existing.authors : incoming.authors
        merged.year = incoming.year ?? existing.year
        merged.journal = preferred(incoming.journal, over: existing.journal)
        merged.volume = preferred(incoming.volume, over: existing.volume)
        merged.issue = preferred(incoming.issue, over: existing.issue)
        merged.pages = preferred(incoming.pages, over: existing.pages)
        merged.doi = preferred(incoming.doi, over: existing.doi)
        merged.url = preferred(incoming.url, over: existing.url)
        merged.abstract = preferredLongest(incoming.abstract, over: existing.abstract)
        merged.pdfPath = preferred(incoming.pdfPath, over: existing.pdfPath)
        merged.notes = preferredLongest(incoming.notes, over: existing.notes)
        merged.webContent = preferredLongest(incoming.webContent, over: existing.webContent)
        merged.siteName = preferred(incoming.siteName, over: existing.siteName)
        merged.favicon = preferred(incoming.favicon, over: existing.favicon)
        if existing.referenceType == .other || existing.referenceType == .webpage {
            merged.referenceType = incoming.referenceType
        }
        merged.metadataSource = incoming.metadataSource ?? existing.metadataSource
        merged.verificationStatus = incoming.verificationStatus.isLibraryReady ? incoming.verificationStatus : existing.verificationStatus
        merged.acceptedByRuleID = preferred(incoming.acceptedByRuleID, over: existing.acceptedByRuleID)
        merged.recordKey = preferred(incoming.recordKey, over: existing.recordKey)
        merged.verificationSourceURL = preferred(incoming.verificationSourceURL, over: existing.verificationSourceURL)
        merged.evidenceBundleHash = preferred(incoming.evidenceBundleHash, over: existing.evidenceBundleHash)
        merged.verifiedAt = incoming.verifiedAt ?? existing.verifiedAt
        merged.reviewedBy = preferred(incoming.reviewedBy, over: existing.reviewedBy)
        merged.collectionId = incoming.collectionId ?? existing.collectionId
        merged.publisher = preferred(incoming.publisher, over: existing.publisher)
        merged.publisherPlace = preferred(incoming.publisherPlace, over: existing.publisherPlace)
        merged.edition = preferred(incoming.edition, over: existing.edition)
        merged.editors = preferred(incoming.editors, over: existing.editors)
        merged.isbn = preferred(incoming.isbn, over: existing.isbn)
        merged.issn = preferred(incoming.issn, over: existing.issn)
        merged.accessedDate = preferred(incoming.accessedDate, over: existing.accessedDate)
        merged.issuedMonth = incoming.issuedMonth ?? existing.issuedMonth
        merged.issuedDay = incoming.issuedDay ?? existing.issuedDay
        merged.translators = preferred(incoming.translators, over: existing.translators)
        merged.eventTitle = preferred(incoming.eventTitle, over: existing.eventTitle)
        merged.eventPlace = preferred(incoming.eventPlace, over: existing.eventPlace)
        merged.genre = preferred(incoming.genre, over: existing.genre)
        merged.institution = preferred(incoming.institution, over: existing.institution)
        merged.number = preferred(incoming.number, over: existing.number)
        merged.collectionTitle = preferred(incoming.collectionTitle, over: existing.collectionTitle)
        merged.numberOfPages = preferred(incoming.numberOfPages, over: existing.numberOfPages)
        merged.language = preferred(incoming.language, over: existing.language)
        merged.pmid = preferred(incoming.pmid, over: existing.pmid)
        merged.pmcid = preferred(incoming.pmcid, over: existing.pmcid)
        merged.dateAdded = existing.dateAdded
        merged.dateModified = Date()
        return merged
    }
}

// MARK: - Collection CRUD
extension AppDatabase {
    public func saveCollection(_ collection: inout Collection) throws {
        try dbWriter.write { db in
            try collection.save(db)
        }
    }

    public func deleteCollection(id: Int64) throws {
        try dbWriter.write { db in
            _ = try Collection.deleteOne(db, id: id)
        }
    }

    public func fetchAllCollections() throws -> [Collection] {
        try dbWriter.read { db in
            try Collection.order(Collection.Columns.name).fetchAll(db)
        }
    }
}

// MARK: - Tag CRUD
extension AppDatabase {
    public func saveTag(_ tag: inout Tag) throws {
        try dbWriter.write { db in
            try tag.save(db)
        }
    }

    public func deleteTag(id: Int64) throws {
        try dbWriter.write { db in
            _ = try Tag.deleteOne(db, id: id)
        }
    }

    public func fetchAllTags() throws -> [Tag] {
        try dbWriter.read { db in
            try Tag.order(Tag.Columns.name).fetchAll(db)
        }
    }

    public func fetchTags(forReference refId: Int64) throws -> [Tag] {
        try dbWriter.read { db in
            let request = Tag
                .joining(required: Tag.referenceTagPivot
                    .filter(ReferenceTag.Columns.referenceId == refId))
            return try request.fetchAll(db)
        }
    }

    public func setTags(forReference refId: Int64, tagIds: [Int64]) throws {
        try dbWriter.write { db in
            try ReferenceTag.filter(ReferenceTag.Columns.referenceId == refId).deleteAll(db)
            for tagId in tagIds {
                let pivot = ReferenceTag(referenceId: refId, tagId: tagId)
                try pivot.insert(db)
            }
        }
    }
}

// MARK: - PDF Annotation CRUD
extension AppDatabase {
    public func saveAnnotation(_ annotation: inout PDFAnnotationRecord) throws {
        try dbWriter.write { db in
            try annotation.save(db)
        }
    }

    public func saveAnnotations(_ annotations: inout [PDFAnnotationRecord]) throws {
        guard !annotations.isEmpty else { return }
        try dbWriter.write { db in
            for index in annotations.indices {
                try annotations[index].save(db)
            }
        }
    }

    public func deleteAnnotation(id: Int64) throws {
        try dbWriter.write { db in
            _ = try PDFAnnotationRecord.deleteOne(db, id: id)
        }
    }

    public func fetchAnnotations(referenceId: Int64) throws -> [PDFAnnotationRecord] {
        try dbWriter.read { db in
            try PDFAnnotationRecord
                .filter(PDFAnnotationRecord.Columns.referenceId == referenceId)
                .order(PDFAnnotationRecord.Columns.pageIndex)
                .order(PDFAnnotationRecord.Columns.dateCreated)
                .fetchAll(db)
        }
    }

    public func observeAnnotations(referenceId: Int64) -> AnyPublisher<[PDFAnnotationRecord], Error> {
        ValueObservation
            .tracking { db in
                try PDFAnnotationRecord
                    .filter(PDFAnnotationRecord.Columns.referenceId == referenceId)
                    .order(PDFAnnotationRecord.Columns.pageIndex)
                    .order(PDFAnnotationRecord.Columns.dateCreated)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func annotationCount(referenceId: Int64) throws -> Int {
        try dbWriter.read { db in
            try PDFAnnotationRecord
                .filter(PDFAnnotationRecord.Columns.referenceId == referenceId)
                .fetchCount(db)
        }
    }
}

// MARK: - Web Annotation CRUD
extension AppDatabase {
    public func saveWebAnnotation(_ annotation: inout WebAnnotationRecord) throws {
        try dbWriter.write { db in
            try annotation.save(db)
        }
    }

    public func deleteWebAnnotation(id: Int64) throws {
        try dbWriter.write { db in
            _ = try WebAnnotationRecord.deleteOne(db, id: id)
        }
    }

    public func fetchWebAnnotations(referenceId: Int64) throws -> [WebAnnotationRecord] {
        try dbWriter.read { db in
            try WebAnnotationRecord
                .filter(WebAnnotationRecord.Columns.referenceId == referenceId)
                .order(WebAnnotationRecord.Columns.dateCreated)
                .fetchAll(db)
        }
    }

    public func observeWebAnnotations(referenceId: Int64) -> AnyPublisher<[WebAnnotationRecord], Error> {
        ValueObservation
            .tracking { db in
                try WebAnnotationRecord
                    .filter(WebAnnotationRecord.Columns.referenceId == referenceId)
                    .order(WebAnnotationRecord.Columns.dateCreated)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func webAnnotationCount(referenceId: Int64) throws -> Int {
        try dbWriter.read { db in
            try WebAnnotationRecord
                .filter(WebAnnotationRecord.Columns.referenceId == referenceId)
                .fetchCount(db)
        }
    }
}

// MARK: - Observation with GRDBQuery
import Combine

/// Describes the active sidebar filter so the database layer can build
/// the correct query without loading every row into memory first.
public enum ReferenceScope: Sendable {
    case all
    case collection(Int64)
    case tag(Int64)
}

/// Structured search predicates that can be pushed down to SQL.
public struct ReferenceFilter: Sendable {
    public var keyword: String = ""
    public var author: String = ""
    public var yearFrom: Int? = nil
    public var yearTo: Int? = nil
    public var journal: String = ""
    public var referenceType: ReferenceType? = nil
    public var titleOnly: Bool = false
    public var hasPDF: Bool? = nil
    public var collectionId: Int64? = nil

    public var isEmpty: Bool {
        keyword.isEmpty && author.isEmpty && yearFrom == nil
            && yearTo == nil && journal.isEmpty && referenceType == nil
            && !titleOnly && hasPDF == nil && collectionId == nil
    }

    public init() {}
}

extension AppDatabase {
    public func observeReferenceTitles() -> AnyPublisher<[String], Error> {
        ValueObservation
            .tracking { db in
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT title
                        FROM reference
                        ORDER BY dateAdded DESC
                        """
                )
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func observeReferences() -> AnyPublisher<[Reference], Error> {
        ValueObservation
            .tracking { db in
                try Reference.order(Reference.Columns.dateAdded.desc).fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    /// Observe references with scope + filter pushed down to SQLite.
    /// - Parameters:
    ///   - scope:  Sidebar selection (all / collection / tag).
    ///   - filter: Structured predicates (keyword FTS, author, year, journal, type).
    ///   - limit:  Maximum rows to return (0 = unlimited).
    public func observeReferences(
        scope: ReferenceScope,
        filter: ReferenceFilter,
        limit: Int = 200
    ) -> AnyPublisher<[Reference], Error> {
        ValueObservation
            .tracking { [self] db in
                try self.fetchReferences(
                    db: db,
                    scope: scope,
                    filter: filter,
                    limit: limit,
                    selectedColumns: Reference.lightColumns
                )
            }
            .publisher(in: dbWriter, scheduling: .async(onQueue: .main))
            .eraseToAnyPublisher()
    }

    /// Lightweight list-row observation: only loads the columns needed for
    /// rendering rows, dramatically reducing decode + memory + diff cost.
    public func observeReferenceListRows(
        scope: ReferenceScope,
        filter: ReferenceFilter,
        limit: Int = 200
    ) -> AnyPublisher<[ReferenceListRow], Error> {
        ValueObservation
            .tracking { [self] db in
                let request = try self.buildReferenceQuery(
                    db: db, scope: scope, filter: filter, limit: limit
                )
                return try request
                    .select(ReferenceListRow.listColumns)
                    .asRequest(of: ReferenceListRow.self)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .async(onQueue: .main))
            .eraseToAnyPublisher()
    }

    /// Observe the total reference count for the given scope + filter (for UI display).
    public func observeReferenceCount(
        scope: ReferenceScope,
        filter: ReferenceFilter
    ) -> AnyPublisher<Int, Error> {
        ValueObservation
            .tracking { [self] db in
                let request = try self.buildReferenceQuery(
                    db: db, scope: scope, filter: filter, limit: 0
                )
                return try request.fetchCount(db)
            }
            .publisher(in: dbWriter, scheduling: .async(onQueue: .main))
            .eraseToAnyPublisher()
    }

    /// Direct (non-observed) fetch of lightweight list rows — used for pagination.
    public func fetchReferenceListRows(
        scope: ReferenceScope,
        filter: ReferenceFilter,
        limit: Int,
        offset: Int = 0
    ) throws -> [ReferenceListRow] {
        try dbWriter.read { db in
            let request = try self.buildReferenceQuery(
                db: db, scope: scope, filter: filter, limit: limit, offset: offset
            )
            return try request
                .select(ReferenceListRow.listColumns)
                .asRequest(of: ReferenceListRow.self)
                .fetchAll(db)
        }
    }

    // Shared query builder used by both Reference and ReferenceListRow paths.
    private func buildReferenceQuery(
        db: Database,
        scope: ReferenceScope,
        filter: ReferenceFilter,
        limit: Int,
        offset: Int = 0
    ) throws -> QueryInterfaceRequest<Reference> {
        let sanitizedKeywordTokens = filter.keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { token in
                token
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
            }
            .filter { !$0.isEmpty }

        // ── 1. Build base request from scope ──────────────────────────────
        var request: QueryInterfaceRequest<Reference>
        switch scope {
        case .all:
            request = Reference.all()
        case .collection(let cid):
            request = Reference.filter(Reference.Columns.collectionId == cid)
        case .tag(let tid):
            request = Reference
                .joining(required: Reference.referenceTagPivot
                    .filter(ReferenceTag.Columns.tagId == tid))
        }

        // ── 2. Apply SQL-level predicates ─────────────────────────────────
        if !sanitizedKeywordTokens.isEmpty {
            if filter.titleOnly {
                let ftsQuery = sanitizedKeywordTokens.map { "title:\"\($0)\" *" }.joined(separator: " AND ")
                request = request.filter(
                    sql: "id IN (SELECT rowid FROM referenceFts WHERE referenceFts MATCH ?)",
                    arguments: [ftsQuery]
                )
            } else {
                let ftsQuery = sanitizedKeywordTokens.map { "\"\($0)\" *" }.joined(separator: " AND ")
                request = request.filter(
                    sql: "id IN (SELECT rowid FROM referenceFts WHERE referenceFts MATCH ?)",
                    arguments: [ftsQuery]
                )
            }
        }
        if !filter.author.isEmpty {
            let sanitizedAuthor = filter.author.lowercased()
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            if !sanitizedAuthor.isEmpty {
                let ftsQuery = "authorsNormalized:\"\(sanitizedAuthor)\" *"
                request = request.filter(
                    sql: "id IN (SELECT rowid FROM referenceFts WHERE referenceFts MATCH ?)",
                    arguments: [ftsQuery]
                )
            }
        }
        if let yf = filter.yearFrom {
            request = request.filter(Reference.Columns.year >= yf)
        }
        if let yt = filter.yearTo {
            request = request.filter(Reference.Columns.year <= yt)
        }
        if !filter.journal.isEmpty {
            let sanitizedJournal = filter.journal
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            if !sanitizedJournal.isEmpty {
                let ftsQuery = "journal:\"\(sanitizedJournal)\" *"
                request = request.filter(
                    sql: "id IN (SELECT rowid FROM referenceFts WHERE referenceFts MATCH ?)",
                    arguments: [ftsQuery]
                )
            }
        }
        if let type = filter.referenceType {
            request = request.filter(Reference.Columns.referenceType == type.rawValue)
        }
        if let collectionId = filter.collectionId {
            request = request.filter(Reference.Columns.collectionId == collectionId)
        }
        if let hasPDF = filter.hasPDF {
            request = hasPDF
                ? request.filter(Reference.Columns.pdfPath != nil)
                : request.filter(Reference.Columns.pdfPath == nil)
        }

        // ── 3. Order + limit ──────────────────────────────────────────────
        request = request.order(Reference.Columns.dateAdded.desc)
        if limit > 0 {
            request = request.limit(limit, offset: offset > 0 ? offset : nil)
        } else if offset > 0 {
            request = request.limit(-1, offset: offset)
        }

        return request
    }

    // Internal helper used by both the publisher and direct fetch paths.
    private func fetchReferences(
        db: Database,
        scope: ReferenceScope,
        filter: ReferenceFilter,
        limit: Int,
        offset: Int = 0,
        selectedColumns: [any SQLSelectable]? = nil
    ) throws -> [Reference] {
        var request = try buildReferenceQuery(
            db: db, scope: scope, filter: filter, limit: limit, offset: offset
        )

        if let selectedColumns {
            request = request.select(selectedColumns)
        }

        return try request.fetchAll(db)
    }

    public func observeCollections() -> AnyPublisher<[Collection], Error> {
        ValueObservation
            .tracking { db in
                try Collection.order(Collection.Columns.name).fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func observePendingMetadataIntakes() -> AnyPublisher<[MetadataIntake], Error> {
        ValueObservation
            .tracking { db in
                try MetadataIntake
                    .filter(
                        [VerificationStatus.seedOnly.rawValue,
                         VerificationStatus.candidate.rawValue,
                         VerificationStatus.blocked.rawValue,
                         VerificationStatus.rejectedAmbiguous.rawValue]
                            .contains(MetadataIntake.Columns.verificationStatus)
                    )
                    .order(MetadataIntake.Columns.updatedAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func observeTags() -> AnyPublisher<[Tag], Error> {
        ValueObservation
            .tracking { db in
                try Tag.order(Tag.Columns.name).fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
