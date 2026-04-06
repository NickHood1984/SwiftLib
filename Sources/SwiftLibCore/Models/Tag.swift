import Foundation
import GRDB

public struct Tag: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64?
    public var name: String
    public var color: String

    public init(id: Int64? = nil, name: String, color: String = "#007AFF") {
        self.id = id
        self.name = name
        self.color = color
    }
}

extension Tag: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "tag"

    public static let referenceTagPivot = hasMany(ReferenceTag.self)
    public static let references = hasMany(Reference.self, through: referenceTagPivot, using: ReferenceTag.reference)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, name, color
    }
}

public struct ReferenceTag: Codable, Sendable {
    public var referenceId: Int64
    public var tagId: Int64

    public init(referenceId: Int64, tagId: Int64) {
        self.referenceId = referenceId
        self.tagId = tagId
    }
}

extension ReferenceTag: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "referenceTag"

    public static let reference = belongsTo(Reference.self)
    public static let tag = belongsTo(Tag.self)

    public enum Columns: String, ColumnExpression {
        case referenceId, tagId
    }
}
