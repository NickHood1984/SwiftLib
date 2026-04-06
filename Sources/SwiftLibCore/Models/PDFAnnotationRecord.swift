import Foundation
import GRDB

public struct PDFAnnotationRect: Codable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public enum AnnotationType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case highlight = "highlight"
    case underline = "underline"
    case note = "note"

    public var icon: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .note: return "note.text"
        }
    }

    public var label: String {
        switch self {
        case .highlight: return "高亮"
        case .underline: return "下划线"
        case .note: return "笔记"
        }
    }
}

public struct PDFAnnotationRecord: Identifiable, Codable, Hashable {
    public var id: Int64?
    public var referenceId: Int64
    public var type: AnnotationType
    public var selectedText: String?
    public var noteText: String?
    public var color: String
    public var pageIndex: Int
    public var boundsX: Double
    public var boundsY: Double
    public var boundsWidth: Double
    public var boundsHeight: Double
    public var rectsData: String
    public var dateCreated: Date

    public init(
        id: Int64? = nil,
        referenceId: Int64,
        type: AnnotationType,
        selectedText: String? = nil,
        noteText: String? = nil,
        color: String = "#FFDE59",
        pageIndex: Int,
        rects: [CGRect],
        dateCreated: Date = Date()
    ) {
        let standardizedRects = rects.map { $0.standardized }
        let normalizedRects = standardizedRects.filter {
            !$0.isNull && !$0.isEmpty && $0.width > 0 && $0.height > 0
        }
        let union = normalizedRects.unionRect ?? .zero

        self.id = id
        self.referenceId = referenceId
        self.type = type
        self.selectedText = selectedText
        self.noteText = noteText
        self.color = color
        self.pageIndex = pageIndex
        self.boundsX = union.origin.x
        self.boundsY = union.origin.y
        self.boundsWidth = union.size.width
        self.boundsHeight = union.size.height
        if let data = try? JSONEncoder().encode(normalizedRects.map(PDFAnnotationRect.init)),
           let json = String(data: data, encoding: .utf8) {
            self.rectsData = json
        } else {
            self.rectsData = "[]"
        }
        self.dateCreated = dateCreated
    }

    public var rects: [CGRect] {
        guard let data = rectsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PDFAnnotationRect].self, from: data)
        else {
            return [unionBounds]
        }

        let rects = decoded.map(\.cgRect).filter { !$0.isNull && !$0.isEmpty }
        return rects.isEmpty ? [unionBounds] : rects
    }

    public var unionBounds: CGRect {
        CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight).standardized
    }

    public var renderHash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(type)
        hasher.combine(color)
        hasher.combine(pageIndex)
        hasher.combine(noteText)
        for rect in rects {
            hasher.combine(rect.origin.x)
            hasher.combine(rect.origin.y)
            hasher.combine(rect.size.width)
            hasher.combine(rect.size.height)
        }
        return hasher.finalize()
    }
}

extension PDFAnnotationRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "pdfAnnotation"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, referenceId, type, selectedText, noteText, color
        case pageIndex, boundsX, boundsY, boundsWidth, boundsHeight, rectsData, dateCreated
    }
}

private extension Array where Element == CGRect {
    var unionRect: CGRect? {
        guard let first else { return nil }
        return dropFirst().reduce(first) { $0.union($1) }
    }
}
