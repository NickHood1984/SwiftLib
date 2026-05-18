import CoreGraphics

// MARK: - Annotation Tool

enum PDFSidebarTab: String, CaseIterable {
    case outline = "目录"
    case annotations = "标注"
    case info = "信息"
}

enum AnnotationTool: String, CaseIterable {
    case cursor = "cursor"
    case highlight = "highlight"
    case underline = "underline"
    case note = "note"

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .note: return "note.text"
        }
    }

    var label: String {
        switch self {
        case .cursor: return "选择"
        case .highlight: return "高亮"
        case .underline: return "下划线"
        case .note: return "笔记"
        }
    }
}

// MARK: - Selection toolbar (PDF anchor + layout)

struct StagedSelectionPDFAnchor: Equatable {
    var pageIndex: Int
    var lastLineBounds: CGRect
}
