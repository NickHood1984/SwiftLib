import Foundation
import GRDB

public struct Collection: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64?
    public var name: String
    public var icon: String
    public var dateCreated: Date
    public var parentId: Int64?

    public init(
        id: Int64? = nil,
        name: String,
        icon: String = "folder",
        dateCreated: Date = Date(),
        parentId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.dateCreated = dateCreated
        self.parentId = parentId
    }
}

extension Collection: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "collection"

    public static let references = hasMany(Reference.self)
    public var references: QueryInterfaceRequest<Reference> {
        request(for: Collection.references)
    }

    public static let children = hasMany(Collection.self, key: "children", using: ForeignKey(["parentId"]))
    public var children: QueryInterfaceRequest<Collection> {
        request(for: Collection.children)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, name, icon, dateCreated, parentId
    }
}
