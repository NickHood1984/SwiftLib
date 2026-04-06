import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class ReferenceWebContentTests: XCTestCase {
    func testEncodeAndDecodeHTMLWebContent() {
        let stored = Reference.encodeWebContent("<article><p>Hello</p></article>", format: .html)
        let decoded = Reference.decodeWebContent(stored)

        XCTAssertNotNil(stored)
        XCTAssertEqual(decoded?.format, .html)
        XCTAssertEqual(decoded?.body, "<article><p>Hello</p></article>")
    }

    func testPlainMarkdownDefaultsToMarkdownFormat() {
        let stored = Reference.encodeWebContent("# Title\n\nBody text", format: .markdown)
        let decoded = Reference.decodeWebContent(stored)

        XCTAssertEqual(stored, "# Title\n\nBody text")
        XCTAssertEqual(decoded?.format, .markdown)
        XCTAssertEqual(decoded?.body, "# Title\n\nBody text")
    }
}
