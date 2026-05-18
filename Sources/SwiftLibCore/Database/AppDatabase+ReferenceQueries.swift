import Foundation
import Combine
import GRDB

// MARK: - Reference Queries
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
    public var workspaceId: Int64? = nil

    public var isEmpty: Bool {
        keyword.isEmpty && author.isEmpty && yearFrom == nil
            && yearTo == nil && journal.isEmpty && referenceType == nil
            && !titleOnly && hasPDF == nil && collectionId == nil
            && workspaceId == nil
    }

    public init() {}
}

extension AppDatabase {
    /// FTS5 full-text search with prefix matching — "smi" matches "Smith"
    public func searchReferences(query: String, limit: Int = 20) throws -> [Reference] {
        return try dbWriter.read { db in
            var filter = ReferenceFilter()
            filter.keyword = query
            return try fetchReferences(db: db, scope: .all, filter: filter, limit: limit)
        }
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

        if let workspaceId = filter.workspaceId,
           let workspace = try Workspace.fetchOne(db, id: workspaceId),
           workspace.kind != .all {
            request = request.filter(
                sql: "id IN (SELECT referenceId FROM workspaceReference WHERE workspaceId = ?)",
                arguments: [workspaceId]
            )
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

}
