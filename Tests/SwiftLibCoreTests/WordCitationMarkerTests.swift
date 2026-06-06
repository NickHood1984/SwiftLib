import XCTest
@testable import SwiftLibCore

final class WordCitationMarkerTests: XCTestCase {
    func testExtractBibliographyEntriesCombinesSplitTextRuns() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>[1] Post D M. </w:t></w:r>
              <w:r><w:t>Using stable isotopes to estimate trophic position: models, methods, and assumptions[J]. Ecology, 2002, 83(3): 703-718.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let entries = WordCitationMarker.extractBibliographyEntries(from: xml)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.number, 1)
        XCTAssertTrue(entries.first?.text.contains("Using stable isotopes to estimate trophic position") == true)
    }

    func testBuildReferenceNumberMapMatchesByTitle() {
        let refs = [
            Reference(
                id: 94,
                title: "Using stable isotopes to estimate trophic position: models, methods, and assumptions",
                authors: [AuthorName(given: "D M", family: "Post")],
                year: 2002,
                journal: "Ecology"
            ),
            Reference(
                id: 95,
                title: "Lipids and lipid metabolism in eukaryotic algae",
                authors: [AuthorName(given: "I A", family: "Guschina")],
                year: 2006,
                journal: "Progress in Lipid Research"
            )
        ]
        let entries = [
            WordCitationMarker.BibliographyEntry(
                number: 1,
                text: "Post D M. Using stable isotopes to estimate trophic position: models, methods, and assumptions[J]. Ecology, 2002, 83(3): 703-718."
            ),
            WordCitationMarker.BibliographyEntry(
                number: 2,
                text: "Guschina I A, Harwood J L. Lipids and lipid metabolism in eukaryotic algae[J]. Progress in Lipid Research, 2006, 45(2): 160-186."
            )
        ]

        let mapping = WordCitationMarker.buildReferenceNumberMap(from: entries, references: refs)

        XCTAssertEqual(mapping[1], 94)
        XCTAssertEqual(mapping[2], 95)
    }

    func testBuildReferenceNumberMapMatchesChineseBibliographyVariantsByFuzzyTitle() {
        let refs = [
            Reference(
                id: 687,
                title: "2017—2022年洱海水体营养状态的时空变化趋势及其成因分析",
                authors: [
                    AuthorName(given: "", family: "华兆晖"),
                    AuthorName(given: "", family: "李锐"),
                    AuthorName(given: "", family: "杨智"),
                    AuthorName(given: "", family: "文紫豪"),
                ],
                year: 2024,
                journal: "湖泊科学"
            ),
            Reference(
                id: 688,
                title: "云南九大高原湖泊2013-2022年水质变化趋势及其成因分析",
                authors: [
                    AuthorName(given: "", family: "杨进腊"),
                    AuthorName(given: "", family: "温雯雯"),
                    AuthorName(given: "", family: "胡潇芮"),
                    AuthorName(given: "", family: "黄林培"),
                ],
                year: 2025,
                journal: "环境科学"
            ),
            Reference(
                id: 700,
                title: "洱海北部湖区轮虫群落季节演替特征",
                authors: [
                    AuthorName(given: "", family: "张亚男"),
                    AuthorName(given: "", family: "高登成"),
                    AuthorName(given: "", family: "张晓莉"),
                    AuthorName(given: "", family: "吕兴菊"),
                ],
                year: 2023,
                journal: "湖泊科学"
            ),
            Reference(
                id: 701,
                title: "近百年来枝角类群落响应洱海营养水平､外来鱼类引入以及水生植被变化的特征",
                authors: [
                    AuthorName(given: "", family: "卢慧斌"),
                    AuthorName(given: "", family: "陈光杰"),
                    AuthorName(given: "", family: "蔡燕凤"),
                    AuthorName(given: "", family: "王教元"),
                ],
                year: 2016,
                journal: "湖泊科学"
            ),
        ]
        let entries = [
            WordCitationMarker.BibliographyEntry(
                number: 21,
                text: "华兆晖, 刘晓东, 王晓龙, 等. 洱海营养状态时空变化趋势及成因分析[J]. 湖泊科学, 2024, 36(6): 1639-1649."
            ),
            WordCitationMarker.BibliographyEntry(
                number: 22,
                text: "杨进腊, 刘晓东, 王晓龙, 等. 云南九大高原湖泊水质变化趋势及成因分析[J]. 环境科学研究, 2025, 38(6): 1300-1311."
            ),
            WordCitationMarker.BibliographyEntry(
                number: 34,
                text: "吕兴菊, 李秋华, 高廷进, 等. 洱海北部轮虫群落结构的季节演替特征[J]. 湖泊科学, 2023, 35(1): 289-297."
            ),
            WordCitationMarker.BibliographyEntry(
                number: 35,
                text: "卢慧斌, 李秋华, 高廷进, 等. 洱海枝角类群落对营养水平和外来鱼类引入及水草变化的响应[J]. 湖泊科学, 2016, 28(1): 132-140."
            ),
        ]

        let mapping = WordCitationMarker.buildReferenceNumberMap(from: entries, references: refs)

        XCTAssertEqual(mapping[21], 687)
        XCTAssertEqual(mapping[22], 688)
        XCTAssertEqual(mapping[34], 700)
        XCTAssertEqual(mapping[35], 701)
    }

    func testMarkCitationRunsWrapsOnlyFullyMatchedSuperscriptMarkers() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>Text</w:t></w:r>
              <w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>[1,2]</w:t></w:r>
              <w:r><w:t>more</w:t></w:r>
              <w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>[1,3]</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let result = WordCitationMarker.markCitationRuns(
            in: xml,
            referenceNumberMap: [1: 94, 2: 95],
            style: "nature"
        )

        XCTAssertEqual(result.taggedCitationCount, 1)
        XCTAssertEqual(result.skippedCitationMarkers, ["[1,3]"])
        XCTAssertTrue(result.xml.contains("swiftlib:v3:cite:"))
        XCTAssertTrue(result.xml.contains(":nature:94,95"))
        XCTAssertTrue(result.xml.contains("<w:sdt>"))
    }

    func testDocxAuditFindsMissingUnusedAndDuplicateCitations() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:cite:c1:nature:94,95"/></w:sdtPr><w:sdtContent><w:r><w:t>[1]</w:t></w:r></w:sdtContent></w:sdt>
              <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:cite:c2:nature:94"/></w:sdtPr><w:sdtContent><w:r><w:t>[1]</w:t></w:r></w:sdtContent></w:sdt>
            </w:p>
            <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:bib:b1:nature"/></w:sdtPr><w:sdtContent><w:p><w:r><w:t>1. Post D M. Example.</w:t></w:r></w:p></w:sdtContent></w:sdt>
          </w:body>
        </w:document>
        """
        let refs = [
            Reference(id: 94, title: "Example", authors: [AuthorName(given: "D M", family: "Post")]),
            Reference(id: 96, title: "Unused"),
        ]

        let report = WordCitationDOCXProcessor.auditDocumentXML(xml, references: refs)

        XCTAssertEqual(report.citationControlCount, 2)
        XCTAssertEqual(report.docUniqueIDs, [94, 95])
        XCTAssertEqual(report.missingInLibrary, [95])
        XCTAssertEqual(report.unusedInLibrary, [96])
        XCTAssertEqual(report.duplicateCitationsInParagraphs, [
            WordDOCXDuplicateCitation(paragraphIndex: 1, referenceID: 94, count: 2)
        ])
        XCTAssertEqual(report.bibliographyEntryCount, 1)
        XCTAssertEqual(report.bodyCitationNumbers, [1])
        XCTAssertEqual(report.bibliographyEntryNumbers, [1])
        XCTAssertTrue(report.listedButUncitedBibliographyNumbers.isEmpty)
        XCTAssertTrue(report.citedButUnlistedBodyCitationNumbers.isEmpty)
        XCTAssertFalse(report.bibliographyMatchesBodyUniqueCount)
    }

    func testDocxAuditReportsVisibleBibliographyNumbersMissingFromBody() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:cite:c87:nature:87"/></w:sdtPr><w:sdtContent><w:r><w:t>[87]</w:t></w:r></w:sdtContent></w:sdt>
              <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:cite:c90:nature:90"/></w:sdtPr><w:sdtContent><w:r><w:t>[90]</w:t></w:r></w:sdtContent></w:sdt>
              <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:cite:c92:nature:92,93"/></w:sdtPr><w:sdtContent><w:r><w:t>[92-93]</w:t></w:r></w:sdtContent></w:sdt>
            </w:p>
            <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:bib:b1:nature"/></w:sdtPr><w:sdtContent>
              <w:p><w:r><w:t>[87] Jeppesen E. Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>[88] Wang H. Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>[89] Stibor H. Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>[90] Referenced Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>[91] Liu X. Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>[92] Referenced Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>[93] Referenced Example.</w:t></w:r></w:p>
            </w:sdtContent></w:sdt>
          </w:body>
        </w:document>
        """
        let refs = [
            Reference(id: 87, title: "Jeppesen"),
            Reference(id: 90, title: "Referenced"),
            Reference(id: 92, title: "Referenced 2"),
            Reference(id: 93, title: "Referenced 3"),
        ]

        let report = WordCitationDOCXProcessor.auditDocumentXML(xml, references: refs)

        XCTAssertEqual(report.bodyCitationNumbers, [87, 90, 92, 93])
        XCTAssertEqual(report.bibliographyEntryNumbers, [87, 88, 89, 90, 91, 92, 93])
        XCTAssertEqual(report.listedButUncitedBibliographyNumbers, [88, 89, 91])
        XCTAssertTrue(report.citedButUnlistedBodyCitationNumbers.isEmpty)
        XCTAssertTrue(report.warnings.contains {
            $0.contains("bibliography contains numbered entries not present in visible body citations")
        })
    }

    func testDocxAuditReportsVisibleBodyNumbersMissingFromBibliography() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:cite:c1:nature:1,3"/></w:sdtPr><w:sdtContent><w:r><w:t>[1,3]</w:t></w:r></w:sdtContent></w:sdt>
            </w:p>
            <w:sdt><w:sdtPr><w:tag w:val="swiftlib:v3:bib:b1:nature"/></w:sdtPr><w:sdtContent>
              <w:p><w:r><w:t>1. First Example.</w:t></w:r></w:p>
              <w:p><w:r><w:t>2. Second Example.</w:t></w:r></w:p>
            </w:sdtContent></w:sdt>
          </w:body>
        </w:document>
        """
        let refs = [
            Reference(id: 1, title: "First"),
            Reference(id: 3, title: "Third"),
        ]

        let report = WordCitationDOCXProcessor.auditDocumentXML(xml, references: refs)

        XCTAssertEqual(report.bodyCitationNumbers, [1, 3])
        XCTAssertEqual(report.bibliographyEntryNumbers, [1, 2])
        XCTAssertEqual(report.listedButUncitedBibliographyNumbers, [2])
        XCTAssertEqual(report.citedButUnlistedBodyCitationNumbers, [3])
    }

    func testDocxAuditReadsPlainTextBodyCitationNumbersWhenNoSwiftLibControlsExist() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>正文引用了第一篇</w:t></w:r><w:r><w:t>[1]</w:t></w:r><w:r><w:t>，也引用了第三到第四篇</w:t></w:r><w:r><w:t>[3-4]</w:t></w:r><w:r><w:t>。</w:t></w:r></w:p>
            <w:p><w:r><w:t>参考文献</w:t></w:r></w:p>
            <w:p><w:r><w:t>[1] First Example.</w:t></w:r></w:p>
            <w:p><w:r><w:t>[2] Uncited Example.</w:t></w:r></w:p>
            <w:p><w:r><w:t>[3] Third Example.</w:t></w:r></w:p>
            <w:p><w:r><w:t>[4] Fourth Example.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let refs = [
            Reference(id: 1, title: "First"),
            Reference(id: 2, title: "Second"),
            Reference(id: 3, title: "Third"),
            Reference(id: 4, title: "Fourth"),
        ]

        let report = WordCitationDOCXProcessor.auditDocumentXML(xml, references: refs)

        XCTAssertEqual(report.citationControlCount, 0)
        XCTAssertEqual(report.bodyCitationNumbers, [1, 3, 4])
        XCTAssertEqual(report.bibliographyEntryNumbers, [1, 2, 3, 4])
        XCTAssertEqual(report.listedButUncitedBibliographyNumbers, [2])
        XCTAssertTrue(report.citedButUnlistedBodyCitationNumbers.isEmpty)
        XCTAssertFalse(report.bibliographyMatchesBodyUniqueCount)
    }

    func testDocxAuditReadsShortCitationFallbackPayload() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:sdt><w:sdtPr><w:placeholder><w:docPart w:val="swiftlib:v3:payload:nature:94,95"/></w:placeholder><w:tag w:val="swiftlib:v3:cite:11111111-1111-4111-8111-111111111111"/></w:sdtPr><w:sdtContent><w:r><w:t>[1]</w:t></w:r></w:sdtContent></w:sdt>
            </w:p>
          </w:body>
        </w:document>
        """
        let refs = [
            Reference(id: 94, title: "Example"),
            Reference(id: 95, title: "Example 2"),
        ]

        let report = WordCitationDOCXProcessor.auditDocumentXML(xml, references: refs)

        XCTAssertEqual(report.docUniqueIDs, [94, 95])
        XCTAssertTrue(report.missingInLibrary.isEmpty)
    }
}
