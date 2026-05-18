import Foundation
import Combine
import GRDB

// MARK: - Workspace CRUD
extension AppDatabase {
    @discardableResult
    public func ensureSystemWorkspace() throws -> Workspace {
        try dbWriter.write { db in
            if let existing = try Workspace
                .filter(Workspace.Columns.kind == WorkspaceKind.all.rawValue)
                .filter(Workspace.Columns.isSystem == true)
                .order(Workspace.Columns.sortIndex, Workspace.Columns.name)
                .fetchOne(db) {
                return existing
            }

            var workspace = Workspace(
                name: "全部文献",
                icon: "books.vertical",
                kind: .all,
                sortIndex: 0,
                isSystem: true
            )
            try workspace.insert(db)
            return workspace
        }
    }

    public func saveWorkspace(_ workspace: inout Workspace) throws {
        workspace.dateModified = Date()
        try dbWriter.write { db in
            try workspace.save(db)
        }
    }

    public func deleteWorkspace(id: Int64) throws {
        try dbWriter.write { db in
            guard let workspace = try Workspace.fetchOne(db, id: id), !workspace.isSystem else {
                return
            }
            _ = try Workspace.deleteOne(db, id: id)
        }
    }

    public func fetchWorkspace(id: Int64) throws -> Workspace? {
        try dbWriter.read { db in
            try Workspace.fetchOne(db, id: id)
        }
    }

    public func fetchAllWorkspaces() throws -> [Workspace] {
        try dbWriter.read { db in
            try Workspace
                .order(Workspace.Columns.sortIndex, Workspace.Columns.name)
                .fetchAll(db)
        }
    }

    public func saveWorkspaceLayoutSnapshot(_ snapshot: WorkspaceLayoutSnapshot, forWorkspaceId workspaceId: Int64) throws {
        let encoded = try Workspace.encodeLayoutSnapshot(snapshot)
        try dbWriter.write { db in
            try Workspace
                .filter(Workspace.Columns.id == workspaceId)
                .updateAll(
                    db,
                    Workspace.Columns.layoutSnapshotJSON.set(to: encoded),
                    Workspace.Columns.dateModified.set(to: Date())
                )
        }
    }

    public func fetchWorkspaceLayoutSnapshot(workspaceId: Int64) throws -> WorkspaceLayoutSnapshot? {
        try dbWriter.read { db in
            try Workspace.fetchOne(db, id: workspaceId)?.layoutSnapshot
        }
    }

    public func touchWorkspaceOpened(id: Int64) throws {
        try dbWriter.write { db in
            try Workspace
                .filter(Workspace.Columns.id == id)
                .updateAll(db, Workspace.Columns.lastOpenedAt.set(to: Date()))
        }
    }

    public func addReferences(ids: [Int64], toWorkspaceId workspaceId: Int64) throws {
        guard !ids.isEmpty else { return }
        try dbWriter.write { db in
            guard let workspace = try Workspace.fetchOne(db, id: workspaceId),
                  workspace.kind != .all else {
                return
            }

            for id in ids {
                let link = WorkspaceReference(workspaceId: workspaceId, referenceId: id)
                try link.insert(db, onConflict: .ignore)
            }
        }
    }

    public func removeReferences(ids: [Int64], fromWorkspaceId workspaceId: Int64) throws {
        guard !ids.isEmpty else { return }
        try dbWriter.write { db in
            try WorkspaceReference
                .filter(WorkspaceReference.Columns.workspaceId == workspaceId)
                .filter(ids.contains(WorkspaceReference.Columns.referenceId))
                .deleteAll(db)
        }
    }

    public func observeWorkspaces() -> AnyPublisher<[Workspace], Error> {
        ValueObservation
            .tracking { db in
                try Workspace
                    .order(Workspace.Columns.sortIndex, Workspace.Columns.name)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
