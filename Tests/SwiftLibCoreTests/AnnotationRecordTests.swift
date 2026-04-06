import XCTest
@testable import SwiftLibCore

final class PDFAnnotationRecordModelTests: XCTestCase {

    // MARK: - Initialization

    func testInitSetsFields() {
        let rects = [CGRect(x: 10, y: 20, width: 100, height: 15)]
        let annotation = PDFAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            selectedText: "Highlighted text",
            color: "#FFDE59",
            pageIndex: 3,
            rects: rects
        )
        XCTAssertEqual(annotation.referenceId, 1)
        XCTAssertEqual(annotation.type, .highlight)
        XCTAssertEqual(annotation.selectedText, "Highlighted text")
        XCTAssertEqual(annotation.color, "#FFDE59")
        XCTAssertEqual(annotation.pageIndex, 3)
        XCTAssertNil(annotation.id)
    }

    func testInitComputesBoundsFromRects() {
        let rects = [
            CGRect(x: 10, y: 20, width: 100, height: 15),
            CGRect(x: 50, y: 40, width: 80, height: 12),
        ]
        let annotation = PDFAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            pageIndex: 0,
            rects: rects
        )
        // Union of rects should encompass both
        XCTAssertLessThanOrEqual(annotation.boundsX, 10)
        XCTAssertLessThanOrEqual(annotation.boundsY, 20)
        XCTAssertGreaterThanOrEqual(annotation.boundsWidth, 100)
    }

    // MARK: - Rects Serialization

    func testRectsRoundTrip() {
        let rects = [
            CGRect(x: 10, y: 20, width: 100, height: 15),
            CGRect(x: 50, y: 40, width: 80, height: 12),
        ]
        let annotation = PDFAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            pageIndex: 0,
            rects: rects
        )
        let decoded = annotation.rects
        XCTAssertEqual(decoded.count, 2, "Should decode back to 2 rects")
    }

    func testEmptyRectsResultsInUnionBounds() {
        let annotation = PDFAnnotationRecord(
            referenceId: 1,
            type: .note,
            noteText: "A note",
            pageIndex: 0,
            rects: []
        )
        // With empty rects, should fallback to unionBounds
        let decoded = annotation.rects
        XCTAssertFalse(decoded.isEmpty, "Should return at least unionBounds")
    }

    // MARK: - Union Bounds

    func testUnionBoundsMatchesBoundsFields() {
        let rects = [CGRect(x: 10, y: 20, width: 100, height: 15)]
        let annotation = PDFAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            pageIndex: 0,
            rects: rects
        )
        let union = annotation.unionBounds
        XCTAssertEqual(union.origin.x, annotation.boundsX, accuracy: 0.01)
        XCTAssertEqual(union.origin.y, annotation.boundsY, accuracy: 0.01)
        XCTAssertEqual(union.size.width, annotation.boundsWidth, accuracy: 0.01)
        XCTAssertEqual(union.size.height, annotation.boundsHeight, accuracy: 0.01)
    }

    // MARK: - Annotation Types

    func testAnnotationTypeIcons() {
        XCTAssertEqual(AnnotationType.highlight.icon, "highlighter")
        XCTAssertEqual(AnnotationType.underline.icon, "underline")
        XCTAssertEqual(AnnotationType.note.icon, "note.text")
    }

    func testAnnotationTypeLabels() {
        XCTAssertEqual(AnnotationType.highlight.label, "高亮")
        XCTAssertEqual(AnnotationType.underline.label, "下划线")
        XCTAssertEqual(AnnotationType.note.label, "笔记")
    }

    func testAnnotationTypeRawValues() {
        XCTAssertEqual(AnnotationType.highlight.rawValue, "highlight")
        XCTAssertEqual(AnnotationType.underline.rawValue, "underline")
        XCTAssertEqual(AnnotationType.note.rawValue, "note")
    }

    // MARK: - Render Hash

    func testRenderHashDiffersForDifferentAnnotations() {
        let a1 = PDFAnnotationRecord(
            id: 1,
            referenceId: 1,
            type: .highlight,
            color: "#FFDE59",
            pageIndex: 0,
            rects: [CGRect(x: 10, y: 20, width: 100, height: 15)]
        )
        let a2 = PDFAnnotationRecord(
            id: 2,
            referenceId: 1,
            type: .underline,
            color: "#FF0000",
            pageIndex: 0,
            rects: [CGRect(x: 10, y: 20, width: 100, height: 15)]
        )
        XCTAssertNotEqual(a1.renderHash, a2.renderHash)
    }
}

final class WebAnnotationRecordModelTests: XCTestCase {

    // MARK: - Initialization

    func testInitSetsFields() {
        let annotation = WebAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            selectedText: "Important text",
            color: "#FFDE59",
            anchorText: "Important",
            prefixText: "This is ",
            suffixText: " in the article"
        )
        XCTAssertEqual(annotation.referenceId, 1)
        XCTAssertEqual(annotation.type, .highlight)
        XCTAssertEqual(annotation.selectedText, "Important text")
        XCTAssertEqual(annotation.color, "#FFDE59")
        XCTAssertEqual(annotation.anchorText, "Important")
        XCTAssertEqual(annotation.prefixText, "This is ")
        XCTAssertEqual(annotation.suffixText, " in the article")
        XCTAssertNil(annotation.id)
    }

    func testInitWithNote() {
        let annotation = WebAnnotationRecord(
            referenceId: 1,
            type: .note,
            selectedText: "Selected",
            noteText: "My note about this",
            anchorText: "Selected"
        )
        XCTAssertEqual(annotation.noteText, "My note about this")
    }

    func testDefaultColor() {
        let annotation = WebAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            selectedText: "Text",
            anchorText: "Text"
        )
        XCTAssertEqual(annotation.color, "#FFDE59")
    }

    func testOptionalFieldsDefaultToNil() {
        let annotation = WebAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            selectedText: "Text",
            anchorText: "Text"
        )
        XCTAssertNil(annotation.noteText)
        XCTAssertNil(annotation.prefixText)
        XCTAssertNil(annotation.suffixText)
    }

    func testDateCreatedIsSet() {
        let before = Date()
        let annotation = WebAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            selectedText: "Text",
            anchorText: "Text"
        )
        XCTAssertGreaterThanOrEqual(annotation.dateCreated, before)
    }
}
