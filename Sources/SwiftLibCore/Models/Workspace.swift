import Foundation
import GRDB

public enum WorkspaceKind: String, Codable, DatabaseValueConvertible, Sendable {
    case all
    case manual
    case smart
    case hybrid
}

public enum WorkspaceSidebarSelection: Codable, Hashable, Sendable {
    case allReferences
    case collection(Int64)
    case tag(Int64)
    case titleKeyword(String)
}

public enum WorkspaceColumnVisibility: String, Codable, Sendable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
}

public struct WorkspaceLayoutSnapshot: Codable, Hashable, Sendable {
    public var selectedReferenceId: Int64?
    public var sidebarSelection: WorkspaceSidebarSelection
    public var searchText: String
    public var columnVisibility: WorkspaceColumnVisibility
    public var capturedAt: Date

    public init(
        selectedReferenceId: Int64? = nil,
        sidebarSelection: WorkspaceSidebarSelection = .allReferences,
        searchText: String = "",
        columnVisibility: WorkspaceColumnVisibility = .all,
        capturedAt: Date = Date()
    ) {
        self.selectedReferenceId = selectedReferenceId
        self.sidebarSelection = sidebarSelection
        self.searchText = searchText
        self.columnVisibility = columnVisibility
        self.capturedAt = capturedAt
    }
}

public struct Workspace: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64?
    public var name: String
    public var icon: String
    public var kind: WorkspaceKind
    public var filterJSON: String?
    public var layoutSnapshotJSON: String?
    public var sortIndex: Int
    public var isSystem: Bool
    public var dateCreated: Date
    public var dateModified: Date
    public var lastOpenedAt: Date?

    public init(
        id: Int64? = nil,
        name: String,
        icon: String = "square.stack.3d.up",
        kind: WorkspaceKind = .manual,
        filterJSON: String? = nil,
        layoutSnapshotJSON: String? = nil,
        sortIndex: Int = 100,
        isSystem: Bool = false,
        dateCreated: Date = Date(),
        dateModified: Date = Date(),
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.kind = kind
        self.filterJSON = filterJSON
        self.layoutSnapshotJSON = layoutSnapshotJSON
        self.sortIndex = sortIndex
        self.isSystem = isSystem
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.lastOpenedAt = lastOpenedAt
    }

    public var layoutSnapshot: WorkspaceLayoutSnapshot? {
        guard let layoutSnapshotJSON,
              let data = layoutSnapshotJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspaceLayoutSnapshot.self, from: data)
    }

    public static func encodeLayoutSnapshot(_ snapshot: WorkspaceLayoutSnapshot) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        return String(decoding: data, as: UTF8.self)
    }
}

extension Workspace: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "workspace"

    public static let workspaceReferences = hasMany(WorkspaceReference.self)
    public var workspaceReferences: QueryInterfaceRequest<WorkspaceReference> {
        request(for: Workspace.workspaceReferences)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, name, icon, kind, filterJSON, layoutSnapshotJSON
        case sortIndex, isSystem, dateCreated, dateModified, lastOpenedAt
    }
}

public struct WorkspaceReference: Codable, Hashable, Sendable {
    public var workspaceId: Int64
    public var referenceId: Int64
    public var addedAt: Date
    public var position: Int?

    public init(
        workspaceId: Int64,
        referenceId: Int64,
        addedAt: Date = Date(),
        position: Int? = nil
    ) {
        self.workspaceId = workspaceId
        self.referenceId = referenceId
        self.addedAt = addedAt
        self.position = position
    }
}

extension WorkspaceReference: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workspaceReference"

    public static let workspace = belongsTo(Workspace.self)
    public static let reference = belongsTo(Reference.self)

    public enum Columns: String, ColumnExpression {
        case workspaceId, referenceId, addedAt, position
    }
}
