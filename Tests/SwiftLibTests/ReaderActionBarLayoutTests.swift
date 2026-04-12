import XCTest
@testable import SwiftLib

final class ReaderActionBarLayoutTests: XCTestCase {
    func testMetricsBecomeCompactBelowThreshold() {
        let regular = ReaderActionBarMetrics.resolve(for: .pdf, viewportWidth: 900)
        let compact = ReaderActionBarMetrics.resolve(for: .pdf, viewportWidth: 640)

        XCTAssertEqual(regular.toolbarWidth, 340)
        XCTAssertLessThan(compact.toolbarWidth, regular.toolbarWidth)
        XCTAssertLessThan(compact.buttonWidth, regular.buttonWidth)
        XCTAssertLessThan(compact.buttonHeight, regular.buttonHeight)
        XCTAssertLessThan(compact.selectionEditorMaxHeight, regular.selectionEditorMaxHeight)
    }

    func testAnchoredLayoutClampsWithinVisibleBounds() throws {
        let metrics = ReaderActionBarMetrics.resolve(for: .pdf, viewportWidth: 640)
        let layout = try XCTUnwrap(
            SelectionToolbarLayout.anchored(
                to: CGRect(x: 8, y: 40, width: 12, height: 18),
                overlaySize: CGSize(width: 320, height: 220),
                metrics: metrics,
                horizontalAnchor: .trailing
            )
        )

        XCTAssertTrue(layout.visible)
        XCTAssertGreaterThanOrEqual(layout.origin.x, metrics.edgeMargin)
        XCTAssertLessThanOrEqual(layout.origin.x + metrics.toolbarWidth, 320 - metrics.edgeMargin + 0.5)
        XCTAssertGreaterThan(layout.origin.y, 40)
    }

    func testAnchoredLayoutFlipsAboveNearBottomEdge() throws {
        let metrics = ReaderActionBarMetrics.resolve(for: .web, viewportWidth: 640)
        let rect = CGRect(x: 140, y: 188, width: 36, height: 18)
        let layout = try XCTUnwrap(
            SelectionToolbarLayout.anchored(
                to: rect,
                overlaySize: CGSize(width: 360, height: 230),
                metrics: metrics,
                horizontalAnchor: .center
            )
        )

        XCTAssertTrue(layout.visible)
        XCTAssertLessThan(layout.origin.y, rect.minY)
    }

    func testFallbackWithoutRectPinsToolbarToTop() throws {
        let metrics = ReaderActionBarMetrics.resolve(for: .web, viewportWidth: 700)
        let layout = try XCTUnwrap(
            SelectionToolbarLayout.anchored(
                to: nil,
                overlaySize: CGSize(width: 420, height: 300),
                metrics: metrics,
                horizontalAnchor: .center,
                fallbackToTop: true
            )
        )

        XCTAssertTrue(layout.visible)
        XCTAssertEqual(layout.origin.y, metrics.edgeMargin)
        XCTAssertGreaterThanOrEqual(layout.origin.x, metrics.edgeMargin)
    }
}