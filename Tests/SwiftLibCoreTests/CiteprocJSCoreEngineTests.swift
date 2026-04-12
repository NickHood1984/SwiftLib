import XCTest
@testable import SwiftLibCore

final class CiteprocJSCoreEngineTests: XCTestCase {
    private let numericStyleXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0">
      <info>
        <title>Numeric Test</title>
        <id>numeric-test</id>
      </info>
      <citation collapse="citation-number">
        <sort>
          <key variable="citation-number"/>
        </sort>
        <layout prefix="[" suffix="]" delimiter=",">
          <text variable="citation-number"/>
        </layout>
      </citation>
      <bibliography>
        <layout suffix=".">
          <text variable="citation-number" prefix="[" suffix="] "/>
          <text variable="title"/>
        </layout>
      </bibliography>
    </style>
    """

    private let localeXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <locale xmlns="http://purl.org/net/xbiblio/csl" xml:lang="en-US">
      <terms />
    </locale>
    """

    func testRenderDocumentMarksSuperscriptCitationsWhenStyleUsesVerticalAlignSup() throws {
        let styleXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0">
          <info>
            <title>Superscript Numeric</title>
            <id>superscript-numeric-test</id>
          </info>
          <citation collapse="citation-number">
            <sort>
              <key variable="citation-number"/>
            </sort>
            <layout vertical-align="sup" prefix="[" suffix="]" delimiter=",">
              <text variable="citation-number"/>
            </layout>
          </citation>
          <bibliography>
            <layout suffix=".">
              <text variable="citation-number" prefix="[" suffix="] "/>
              <text variable="title"/>
            </layout>
          </bibliography>
        </style>
        """

        let engine = try CiteprocJSCoreEngine(styleXML: styleXML, localeXML: localeXML)
        engine.setItems([
            [
                "id": "1",
                "type": "article-journal",
                "title": "Superscript Citation Test"
            ]
        ])

        let rendered = try engine.renderDocument(citations: [
            (id: "citation-1", itemIDs: ["1"], position: 0)
        ])

        XCTAssertEqual(rendered.citationTexts["citation-1"], "[1]")
        XCTAssertEqual(rendered.superscriptIDs, Set(["citation-1"]))
        XCTAssertTrue(rendered.bibliographyText.contains("Superscript Citation Test"))
    }

    func testRenderDocumentResetsProcessorStateBetweenDocuments() throws {
        let engine = try CiteprocJSCoreEngine(styleXML: numericStyleXML, localeXML: localeXML)

        engine.setItems([
            [
                "id": "1",
                "type": "article-journal",
                "title": "First Document Item",
            ]
        ])
        let first = try engine.renderDocument(citations: [
            (id: "citation-1", itemIDs: ["1"], position: 0)
        ])
        XCTAssertEqual(first.citationTexts["citation-1"], "[1]")
        XCTAssertTrue(first.bibliographyText.contains("First Document Item"))

        engine.setItems([
            [
                "id": "2",
                "type": "article-journal",
                "title": "Second Document Item",
            ]
        ])
        let second = try engine.renderDocument(citations: [
            (id: "citation-2", itemIDs: ["2"], position: 0)
        ])

        XCTAssertEqual(second.citationTexts["citation-2"], "[1]")
        XCTAssertTrue(second.bibliographyText.contains("Second Document Item"))
        XCTAssertFalse(second.bibliographyText.contains("First Document Item"))
    }

    func testRenderDocumentFailsClearlyWhenCitationReferencesMissingItem() throws {
        let engine = try CiteprocJSCoreEngine(styleXML: numericStyleXML, localeXML: localeXML)
        engine.setItems([
            [
                "id": "1",
                "type": "article-journal",
                "title": "Only Available Item",
            ]
        ])

        XCTAssertThrowsError(try engine.renderDocument(citations: [
            (id: "citation-1", itemIDs: ["2"], position: 0)
        ])) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "citeproc-js render failed: 文档中的引文引用了当前渲染上下文中不存在的文献 ID：2"
            )
        }
    }

    func testRenderDocumentCanSkipBibliographyGeneration() throws {
        let engine = try CiteprocJSCoreEngine(styleXML: numericStyleXML, localeXML: localeXML)
        engine.setItems([
            [
                "id": "1",
                "type": "article-journal",
                "title": "No Bibliography Needed",
            ]
        ])

        let rendered = try engine.renderDocument(
            citations: [(id: "citation-1", itemIDs: ["1"], position: 0)],
            includeBibliography: false
        )

        XCTAssertEqual(rendered.citationTexts["citation-1"], "[1]")
        XCTAssertEqual(rendered.bibliographyText, "")
    }
}
