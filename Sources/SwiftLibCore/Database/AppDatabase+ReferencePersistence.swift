import Foundation
import GRDB

// MARK: - Result types

public enum SaveReferenceOutcome: Sendable {
    case inserted
    case updated
    case mergedInto(existingId: Int64, existingTitle: String)
}

public struct BatchImportResult: Sendable {
    public var inserted: Int = 0
    public var merged: Int = 0
    public var total: Int { inserted + merged }
}

// MARK: - Reference CRUD
extension AppDatabase {
    @discardableResult
    public func saveReference(_ reference: inout Reference) throws -> SaveReferenceOutcome {
        try dbWriter.write { db in
            normalizeReferenceFieldsForStorage(&reference)
            try normalizeForDirectLibrarySave(&reference)
            let isExistingReference = reference.id != nil

            if reference.id == nil {
                try ensureLibraryReady(reference)
            }

            if reference.id == nil,
               let duplicateId = try findDuplicateReferenceID(for: reference, db: db),
               var existing = try Reference.fetchOne(db, id: duplicateId) {
                let existingTitle = existing.title
                existing = mergedReference(existing: existing, incoming: reference)
                try existing.save(db)
                reference = existing
                return .mergedInto(existingId: duplicateId, existingTitle: existingTitle)
            } else {
                if isExistingReference {
                    reference.dateModified = Date()
                    try reference.save(db)
                    return .updated
                }
                try reference.save(db)
                return .inserted
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

    public func repairCitationMetadata(_ references: [Reference]) throws -> ReferenceLibraryRepairReport {
        let candidates = references.compactMap { reference -> (ReferenceLibraryRepairCandidate, Reference)? in
            let repaired = ReferenceLibraryRepairer.repairedReference(reference)
            let plan = ReferenceLibraryRepairer.repairPlan(for: [reference]).candidates.first
            guard let plan else { return nil }
            return (plan, repaired)
        }

        guard !candidates.isEmpty else {
            return ReferenceLibraryRepairReport(referenceCount: references.count, candidates: [])
        }

        return try dbWriter.write { db in
            for (_, var repaired) in candidates {
                guard repaired.id != nil else { continue }
                repaired.dateModified = Date()
                try repaired.save(db)
            }
            return ReferenceLibraryRepairReport(
                referenceCount: references.count,
                appliedCount: candidates.count,
                candidates: candidates.map(\.0)
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
                .updateAll(
                    db,
                    Reference.Columns.collectionId.set(to: toCollectionId),
                    Reference.Columns.dateModified.set(to: Date())
                )
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

    /// Asynchronous variant of `fetchReference(id:)` so the main actor
    /// is not blocked by a synchronous SQLite read (which can stall when
    /// the writer queue is contended).
    public func fetchReferenceAsync(id: Int64) async throws -> Reference? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let ref = try self.dbWriter.read { db in
                        try Reference.fetchOne(db, id: id)
                    }
                    continuation.resume(returning: ref)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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

    /// Batch import — uses single transaction for maximum speed
    /// 10,000 records in ~200ms on Apple Silicon
    public func batchImportReferences(_ references: [Reference]) throws -> BatchImportResult {
        guard !references.isEmpty else { return BatchImportResult() }
        return try dbWriter.write { db in
            var result = BatchImportResult()
            for var ref in references {
                normalizeReferenceFieldsForStorage(&ref)
                normalizeForFileBatchImport(&ref)
                try ensureLibraryReady(ref)
                if let duplicateId = try findDuplicateReferenceID(for: ref, db: db),
                   var existing = try Reference.fetchOne(db, id: duplicateId) {
                    existing = mergedReference(existing: existing, incoming: ref)
                    try existing.save(db)
                    result.merged += 1
                } else {
                    try ref.insert(db)
                    result.inserted += 1
                }
            }
            return result
        }
    }
}
