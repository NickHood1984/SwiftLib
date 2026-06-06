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

    private let authorDateStyleXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0">
      <info>
        <title>Author Date Test</title>
        <id>author-date-test</id>
      </info>
      <citation>
        <layout prefix="(" suffix=")" delimiter="; ">
          <group delimiter=", ">
            <date variable="issued">
              <date-part name="year"/>
            </date>
            <group delimiter=" ">
              <label variable="locator" form="short"/>
              <text variable="locator"/>
            </group>
          </group>
        </layout>
      </citation>
      <bibliography>
        <layout suffix=".">
          <names variable="author"/>
          <date variable="issued" prefix=" (" suffix=")">
            <date-part name="year"/>
          </date>
          <text variable="title" prefix=". "/>
        </layout>
      </bibliography>
    </style>
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

    func testRenderDocumentBibliographyOnlyIncludesCitedItems() throws {
        let engine = try CiteprocJSCoreEngine(styleXML: numericStyleXML, localeXML: localeXML)
        engine.setItems([
            [
                "id": "87",
                "type": "article-journal",
                "title": "Cited Item",
            ],
            [
                "id": "88",
                "type": "article-journal",
                "title": "Uncited Item",
            ],
        ])

        let rendered = try engine.renderDocument(citations: [
            (id: "citation-87", itemIDs: ["87"], position: 0)
        ])

        XCTAssertTrue(rendered.bibliographyText.contains("Cited Item"))
        XCTAssertFalse(rendered.bibliographyText.contains("Uncited Item"))
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

    func testRenderDocumentNormalizesRichCitationItemOptions() throws {
        let engine = try CiteprocJSCoreEngine(styleXML: authorDateStyleXML, localeXML: localeXML)
        engine.setItems([
            [
                "id": "1",
                "type": "article-journal",
                "title": "Rich Options",
                "author": [["family": "Smith", "given": "Jane"]],
                "issued": ["date-parts": [[2024]]],
            ]
        ])

        let rendered = try engine.renderDocument(citationClusters: [
            CitationDocumentCluster(
                id: "citation-1",
                itemIDs: ["1"],
                position: 0,
                citationItems: [
                    CitationDocumentItemOption(
                        itemRef: "lib:1",
                        locator: "42",
                        label: "page",
                        prefix: "see",
                        suffix: "for details",
                        suppressAuthor: true
                    ),
                ]
            )
        ], includeBibliography: false)

        let text = rendered.citationTexts["citation-1"] ?? ""
        XCTAssertTrue(text.contains("2024"))
        XCTAssertTrue(text.contains("42"))
        XCTAssertTrue(text.contains("see"))
        XCTAssertTrue(text.contains("for details"))
    }

    func testCitationDocumentItemOptionNormalizesCSLAndCamelCaseFields() throws {
        let raw: [[String: Any]] = [
            [
                "itemRef": "lib:42",
                "locator": "15",
                "label": "page",
                "prefix": "see",
                "suffix": "note",
                "suppressAuthor": true,
            ]
        ]

        let decoded = try XCTUnwrap(CitationDocumentItemOption.decodeArray(fromJSONObject: raw)?.first)
        let citeproc = decoded.citeprocJSONObject()

        XCTAssertEqual(decoded.resolvedItemID, "42")
        XCTAssertEqual(citeproc["id"] as? String, "42")
        XCTAssertEqual(citeproc["locator"] as? String, "15")
        XCTAssertEqual(citeproc["label"] as? String, "page")
        XCTAssertEqual(citeproc["prefix"] as? String, "see")
        XCTAssertEqual(citeproc["suffix"] as? String, "note")
        XCTAssertEqual(citeproc["suppress-author"] as? Bool, true)
        XCTAssertNil(citeproc["suppressAuthor"])
    }
}
