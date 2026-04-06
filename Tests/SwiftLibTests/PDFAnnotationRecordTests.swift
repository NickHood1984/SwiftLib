import CoreGraphics
import Foundation
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class PDFAnnotationRecordTests: XCTestCase {
    func testInitializerNormalizesRectsAndComputesUnionBounds() {
        let record = PDFAnnotationRecord(
            referenceId: 1,
            type: .highlight,
            pageIndex: 0,
            rects: [
                CGRect(x: 10, y: 20, width: 30, height: 40),
                CGRect(x: 25, y: 15, width: 10, height: 10),
                CGRect(x: 0, y: 0, width: 0, height: 0),
            ]
        )

        XCTAssertEqual(record.rects.count, 2)
        XCTAssertEqual(record.unionBounds, CGRect(x: 10, y: 15, width: 30, height: 45))
        XCTAssertEqual(record.boundsX, 10)
        XCTAssertEqual(record.boundsY, 15)
        XCTAssertEqual(record.boundsWidth, 30)
        XCTAssertEqual(record.boundsHeight, 45)
    }

    func testRectsFallBackToUnionBoundsWhenStoredJSONIsInvalid() {
        var record = PDFAnnotationRecord(
            referenceId: 1,
            type: .note,
            pageIndex: 1,
            rects: [CGRect(x: 5, y: 6, width: 7, height: 8)]
        )
        record.rectsData = "not json"

        XCTAssertEqual(record.rects, [record.unionBounds])
    }

    func testRenderHashChangesWhenVisibleStateChanges() {
        let base = PDFAnnotationRecord(
            id: 10,
            referenceId: 1,
            type: .highlight,
            noteText: "A",
            pageIndex: 1,
            rects: [CGRect(x: 1, y: 2, width: 3, height: 4)]
        )
        var changed = base
        changed.noteText = "B"

        XCTAssertNotEqual(base.renderHash, changed.renderHash)
    }
}
