import XCTest
@testable import SwiftLibCore

final class CSLManagerImportTests: XCTestCase {

    private var tempDir: URL!
    private var manager: CSLManager!

    /// A minimal but valid CSL style whose `<id>` is a URL — the form used by
    /// every style in the Zotero style repository.
    private let urlStyleID = "http://www.zotero.org/styles/swiftlib-test-style"

    private var styleXML: String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <style xmlns="http://purl.org/net/xbiblio/csl" class="in-text" version="1.0" default-locale="en-US">
          <info>
            <title>SwiftLib Test Style</title>
            <id>\(urlStyleID)</id>
          </info>
          <citation>
            <layout prefix="(" suffix=")"><text variable="title"/></layout>
          </citation>
          <bibliography>
            <layout><text variable="title"/></layout>
          </bibliography>
        </style>
        """
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSLManagerImportTests-\(UUID().uuidString)", isDirectory: true)
        manager = CSLManager(storageDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - safeStyleFileName

    func testSafeFileNameFlattensURLStyleIDs() {
        let name = CSLManager.safeStyleFileName(forStyleId: urlStyleID)
        XCTAssertFalse(name.contains("/"), "文件名不得包含路径分隔符")
        XCTAssertFalse(name.contains(":"), "文件名不应包含冒号")
        XCTAssertTrue(name.hasSuffix(".csl"))
    }

    func testSafeFileNameIsStableAndUnique() {
        let a1 = CSLManager.safeStyleFileName(forStyleId: urlStyleID)
        let a2 = CSLManager.safeStyleFileName(forStyleId: urlStyleID)
        XCTAssertEqual(a1, a2, "同一 style id 必须生成稳定文件名（跨启动可覆盖更新）")

        let b = CSLManager.safeStyleFileName(forStyleId: urlStyleID + "-other")
        XCTAssertNotEqual(a1, b, "不同 style id 不得冲突")
    }

    func testSafeFileNameKeepsPlainIDsReadable() {
        XCTAssertEqual(CSLManager.safeStyleFileName(forStyleId: "apa"), "apa.csl")
    }

    // MARK: - Import regression (URL-form <id>)

    /// Regression: importing a style whose `<id>` is a URL used to throw,
    /// because the raw id was used as a filename and `/` created nonexistent
    /// intermediate directories.
    func testImportFromFileWithURLStyleIDSucceeds() throws {
        let sourceURL = tempDir.appendingPathComponent("downloaded-style.csl")
        try styleXML.data(using: .utf8)!.write(to: sourceURL)

        let title = try manager.importCSL(from: sourceURL)
        XCTAssertEqual(title, "SwiftLib Test Style")

        // Style must be retrievable by id afterwards.
        XCTAssertNotNil(manager.cslXmlData(forStyleId: urlStyleID))
        XCTAssertTrue(manager.isKnownStyleID(urlStyleID))

        // And listed as an imported (non-builtin) style.
        let imported = manager.availableStyles().first { $0.id == urlStyleID }
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.isBuiltin, false)
    }

    func testImportWithExplicitIDAndDataSucceeds() throws {
        let title = try manager.importCSL(
            id: "caller-supplied-id",
            title: "Caller Title",
            xmlData: Data(styleXML.utf8)
        )
        XCTAssertEqual(title, "SwiftLib Test Style")
        // The id embedded in the XML wins over the caller-supplied id.
        XCTAssertNotNil(manager.cslXmlData(forStyleId: urlStyleID))
    }

    func testImportXMLWithUnsafeFileNameSucceeds() throws {
        let title = try manager.importCSL(xml: styleXML, fileName: "nested/path/style.csl")
        XCTAssertEqual(title, "SwiftLib Test Style")
        XCTAssertNotNil(manager.cslXmlData(forStyleId: urlStyleID))
    }

    /// Re-importing the same style id must overwrite (update), not accumulate.
    func testReimportUpdatesExistingStyle() throws {
        _ = try manager.importCSL(xml: styleXML, fileName: "style.csl")

        let updatedXML = styleXML.replacingOccurrences(
            of: "SwiftLib Test Style",
            with: "SwiftLib Test Style v2"
        )
        let sourceURL = tempDir.appendingPathComponent("updated.csl")
        try updatedXML.data(using: .utf8)!.write(to: sourceURL)
        let title = try manager.importCSL(from: sourceURL)
        XCTAssertEqual(title, "SwiftLib Test Style v2")

        let xml = manager.cslXmlData(forStyleId: urlStyleID)
            .flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(xml?.contains("SwiftLib Test Style v2") == true, "重新导入后必须返回更新后的样式内容")
    }

    func testDeleteImportedStyleRemovesIt() throws {
        let sourceURL = tempDir.appendingPathComponent("style.csl")
        try styleXML.data(using: .utf8)!.write(to: sourceURL)
        _ = try manager.importCSL(from: sourceURL)
        XCTAssertTrue(manager.isKnownStyleID(urlStyleID))

        manager.deleteStyle(id: urlStyleID)
        XCTAssertNil(manager.availableStyles().first { $0.id == urlStyleID })
    }
}
