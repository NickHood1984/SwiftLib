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
}
