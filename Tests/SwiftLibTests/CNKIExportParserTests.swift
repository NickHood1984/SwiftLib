import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class CNKIExportParserTests: XCTestCase {

    // MARK: - Helpers

    private let singleEnglishRecord = """
    {Reference Type}: Journal Article
    {Title}: Deep Learning for Natural Language Processing
    {Author}: Zhang San;Li Si;Wang Wu
    {Source}: Journal of Artificial Intelligence
    {Year}: 2023
    {Volume}: 45
    {Issue}: 3
    {Pages}: 100-112
    {DOI}: 10.xxxx/12345
    {Abstract}: This paper presents a novel deep learning approach.
    {Keywords}: deep learning;natural language processing;neural networks
    {Institution}: Tsinghua University
    {ISSN}: 1234-5678
    """

    private let singleChineseRecord = """
    {Reference Type}: 期刊文章
    {题名}: 深度学习在自然语言处理中的应用
    {作者}: 张三;李四;王五
    {来源}: 计算机学报
    {年}: 2023
    {卷}: 45
    {期}: 3
    {页码}: 100-112
    {DOI}: 10.xxxx/12345
    {摘要}: 本文提出了一种新的深度学习方法。
    {关键词}: 深度学习;自然语言处理;神经网络
    """

    // MARK: - Single record parsing (English keys)

    func testParseSingleEnglishRecord() {
        let refs = CNKIExportParser.parse(singleEnglishRecord)
        XCTAssertEqual(refs.count, 1)
        let ref = refs[0]
        XCTAssertEqual(ref.title, "Deep Learning for Natural Language Processing")
        XCTAssertEqual(ref.year, 2023)
        XCTAssertEqual(ref.journal, "Journal of Artificial Intelligence")
        XCTAssertEqual(ref.volume, "45")
        XCTAssertEqual(ref.issue, "3")
        XCTAssertEqual(ref.pages, "100-112")
        XCTAssertEqual(ref.doi, "10.xxxx/12345")
        XCTAssertEqual(ref.abstract, "This paper presents a novel deep learning approach.")
        XCTAssertEqual(ref.institution, "Tsinghua University")
        XCTAssertEqual(ref.issn, "1234-5678")
        XCTAssertEqual(ref.metadataSource, .cnki)
        XCTAssertEqual(ref.language, "zh-CN")
    }

    func testParseSingleEnglishRecordAuthors() {
        let refs = CNKIExportParser.parse(singleEnglishRecord)
        XCTAssertEqual(refs[0].authors.count, 3)
        XCTAssertEqual(refs[0].authors[0].family, "Zhang San")
        XCTAssertEqual(refs[0].authors[1].family, "Li Si")
        XCTAssertEqual(refs[0].authors[2].family, "Wang Wu")
    }

    func testParseSingleEnglishRecordKeywords() {
        let refs = CNKIExportParser.parse(singleEnglishRecord)
        let keywords = refs[0].keywords
        XCTAssertNotNil(keywords)
        // Keywords stored as JSON array string
        let data = keywords!.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, ["deep learning", "natural language processing", "neural networks"])
    }

    // MARK: - Chinese keys

    func testParseSingleChineseRecord() {
        let refs = CNKIExportParser.parse(singleChineseRecord)
        XCTAssertEqual(refs.count, 1)
        let ref = refs[0]
        XCTAssertEqual(ref.title, "深度学习在自然语言处理中的应用")
        XCTAssertEqual(ref.year, 2023)
        XCTAssertEqual(ref.journal, "计算机学报")
        XCTAssertEqual(ref.volume, "45")
        XCTAssertEqual(ref.issue, "3")
        XCTAssertEqual(ref.pages, "100-112")
        XCTAssertEqual(ref.abstract, "本文提出了一种新的深度学习方法。")
    }

    func testParseChineseRecordAuthors() {
        let refs = CNKIExportParser.parse(singleChineseRecord)
        XCTAssertEqual(refs[0].authors.map(\.family), ["张三", "李四", "王五"])
    }

    // MARK: - Reference type detection

    func testParseJournalArticleType() {
        let text = "{Reference Type}: Journal Article\n{Title}: Test\n{Author}: Author A"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.first?.referenceType, .journalArticle)
    }

    func testParseThesisType() {
        let text = "{Reference Type}: Thesis\n{Title}: Thesis Paper\n{Author}: Grad Student"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.first?.referenceType, .thesis)
    }

    func testParseConferencePaperType() {
        let text = "{Reference Type}: Conference\n{Title}: Conference Contribution\n{Author}: Speaker"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.first?.referenceType, .conferencePaper)
    }

    func testParseBookType() {
        let text = "{Reference Type}: Book\n{Title}: A Great Book\n{Author}: Author"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.first?.referenceType, .book)
    }

    func testParseChineseThesisType() {
        let text = "{文献类型}: 学位论文\n{题名}: 博士学位论文\n{作者}: 博士生"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.first?.referenceType, .thesis)
    }

    func testParseDefaultsToJournalArticleForUnknownType() {
        let text = "{Reference Type}: Unknown Type\n{Title}: Unknown Paper\n{Author}: Author"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.first?.referenceType, .journalArticle)
    }

    // MARK: - Multi-record parsing

    func testParseMultipleRecordsSeparatedByBlankLines() {
        let text = """
        {Title}: First Paper
        {Author}: Author One
        {Year}: 2022

        {Title}: Second Paper
        {Author}: Author Two
        {Year}: 2023
        """
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[0].title, "First Paper")
        XCTAssertEqual(refs[1].title, "Second Paper")
        XCTAssertEqual(refs[0].year, 2022)
        XCTAssertEqual(refs[1].year, 2023)
    }

    func testParseThreeRecordsPreservesOrder() {
        let text = """
        {Title}: Alpha
        {Author}: Author A

        {Title}: Beta
        {Author}: Author B

        {Title}: Gamma
        {Author}: Author C
        """
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 3)
        XCTAssertEqual(refs.map(\.title), ["Alpha", "Beta", "Gamma"])
    }

    // MARK: - Edge cases

    func testParseEmptyInputReturnsEmptyArray() {
        XCTAssertEqual(CNKIExportParser.parse("").count, 0)
    }

    func testParseRecordMissingTitleReturnsNil() {
        let text = "{Author}: Zhang San\n{Year}: 2023"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 0)
    }

    func testParseRecordWithEmptyTitleReturnsNil() {
        let text = "{Title}:\n{Author}: Zhang San"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 0)
    }

    func testParseEmptyAuthorFieldProducesNoAuthors() {
        let text = "{Title}: Solo Paper\n{Author}:"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].authors.count, 0)
    }

    func testParseYearNonIntegerProducesNilYear() {
        let text = "{Title}: Paper\n{Author}: Author\n{Year}: not-a-year"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 1)
        XCTAssertNil(refs[0].year)
    }

    func testParseChineseFullwidthColonDelimiter() {
        // CNKI sometimes uses ：(U+FF1A) instead of :
        let text = "{Title}：Chinese Colon Title\n{Author}：Author Name"
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].title, "Chinese Colon Title")
    }

    func testParseMultiLineAbstract() {
        let text = """
        {Title}: Paper with Long Abstract
        {Author}: Author
        {Abstract}: First line of abstract.
        Second line continues here.
        Third line concludes.
        """
        let refs = CNKIExportParser.parse(text)
        XCTAssertEqual(refs.count, 1)
        XCTAssertTrue(refs[0].abstract?.contains("Second line continues here.") ?? false,
                      "Multi-line abstract should be joined")
    }
}
