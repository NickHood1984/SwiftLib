import Foundation
import GRDB

public struct WebAnnotationRecord: Identifiable, Codable, Hashable {
    public var id: Int64?
    public var referenceId: Int64
    public var type: AnnotationType
    public var selectedText: String
    public var noteText: String?
    public var color: String
    public var anchorText: String
    public var prefixText: String?
    public var suffixText: String?
    public var dateCreated: Date

    public init(
        id: Int64? = nil,
        referenceId: Int64,
        type: AnnotationType,
        selectedText: String,
        noteText: String? = nil,
        color: String = "#FFDE59",
        anchorText: String,
        prefixText: String? = nil,
        suffixText: String? = nil,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.referenceId = referenceId
        self.type = type
        self.selectedText = selectedText
        self.noteText = noteText
        self.color = color
        self.anchorText = anchorText
        self.prefixText = prefixText
        self.suffixText = suffixText
        self.dateCreated = dateCreated
    }
}

extension WebAnnotationRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "webAnnotation"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, referenceId, type, selectedText, noteText, color
        case anchorText, prefixText, suffixText, dateCreated
    }
}
