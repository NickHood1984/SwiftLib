import Foundation
import GRDB

extension AppDatabase {
    static func makeMigrator() -> DatabaseMigrator {
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

        // ── v12: Enrichment columns + metadata cache ────────────────────
        migrator.registerMigration("v12-enrichment-and-cache") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("keywords") {
                    t.add(column: "keywords", .text)          // JSON [String]
                }
                if !existingColumns.contains("topics") {
                    t.add(column: "topics", .text)             // JSON [String]
                }
                if !existingColumns.contains("isOpenAccess") {
                    t.add(column: "isOpenAccess", .boolean)
                }
                if !existingColumns.contains("oaUrl") {
                    t.add(column: "oaUrl", .text)
                }
                if !existingColumns.contains("citedByCount") {
                    t.add(column: "citedByCount", .integer)
                }
                if !existingColumns.contains("fundingInfo") {
                    t.add(column: "fundingInfo", .text)        // JSON [String]
                }
                if !existingColumns.contains("confidenceScore") {
                    t.add(column: "confidenceScore", .double)
                }
            }

            // Persistent metadata cache (replaces NSCache for cross-session reuse)
            try db.create(table: "metadataCache", ifNotExists: true) { t in
                t.column("cacheKey", .text).primaryKey()
                t.column("sourceAPI", .text).notNull()
                t.column("responseJSON", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
                t.column("expiresAt", .datetime).notNull()
            }

            try db.create(index: "metadataCache_expiresAt", on: "metadataCache", columns: ["expiresAt"], ifNotExists: true)
        }

        // v13: Refresh tracking
        migrator.registerMigration("v13-refresh-tracking") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("lastRefreshedAt") {
                    t.add(column: "lastRefreshedAt", .datetime)
                }
            }
        }

        migrator.registerMigration("v14-journal-rank") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("journalRankJSON") {
                    t.add(column: "journalRankJSON", .text)
                }
            }
        }

        migrator.registerMigration("v15-abstract-translation") { db in
            let existingColumns = try db.columns(in: "reference").map(\.name)

            try db.alter(table: "reference") { t in
                if !existingColumns.contains("translatedAbstract") {
                    t.add(column: "translatedAbstract", .text)
                }
            }
        }

        migrator.registerMigration("v16-workspaces-layout-snapshots") { db in
            if try !db.tableExists("workspace") {
                try db.create(table: "workspace") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("name", .text).notNull()
                    t.column("icon", .text).notNull().defaults(to: "square.stack.3d.up")
                    t.column("kind", .text).notNull().defaults(to: WorkspaceKind.manual.rawValue)
                    t.column("filterJSON", .text)
                    t.column("layoutSnapshotJSON", .text)
                    t.column("sortIndex", .integer).notNull().defaults(to: 100)
                    t.column("isSystem", .boolean).notNull().defaults(to: false)
                    t.column("dateCreated", .datetime).notNull()
                    t.column("dateModified", .datetime).notNull()
                    t.column("lastOpenedAt", .datetime)
                }
                try db.create(index: "workspace_sortIndex", on: "workspace", columns: ["sortIndex", "name"])
            }

            if try !db.tableExists("workspaceReference") {
                try db.create(table: "workspaceReference") { t in
                    t.column("workspaceId", .integer).notNull().references("workspace", onDelete: .cascade)
                    t.column("referenceId", .integer).notNull().references("reference", onDelete: .cascade)
                    t.column("addedAt", .datetime).notNull()
                    t.column("position", .integer)
                    t.primaryKey(["workspaceId", "referenceId"])
                }
                try db.create(index: "workspaceReference_referenceId", on: "workspaceReference", columns: ["referenceId"])
            }

            let systemWorkspaceCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM workspace WHERE kind = ? AND isSystem = 1",
                arguments: [WorkspaceKind.all.rawValue]
            ) ?? 0

            if systemWorkspaceCount == 0 {
                var workspace = Workspace(
                    name: "全部文献",
                    icon: "books.vertical",
                    kind: .all,
                    sortIndex: 0,
                    isSystem: true
                )
                try workspace.insert(db)
            }
        }

        return migrator
    }

}
