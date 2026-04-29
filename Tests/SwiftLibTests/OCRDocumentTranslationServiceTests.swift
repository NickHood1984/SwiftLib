import XCTest
@testable import SwiftLib

@MainActor
final class OCRDocumentTranslationServiceTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SwiftLibPreferences.ocrDocumentTranslationPromptTemplateKey)
        super.tearDown()
    }

    func testParseMarkdownBlocksSeparatesTranslatableAndPassthroughContent() {
        let markdown = """
        # Title

        First paragraph.

        ![Figure](https://example.com/figure.png)

        | A | B |
        | - | - |
        | 1 | 2 |

        ```swift
        let value = 1
        ```

        Final paragraph.
        """

        let blocks = OCRDocumentTranslationService.parseMarkdownBlocks(markdown)

        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks.map(\.isTranslatable), [true, true, false, false, false, true])
        XCTAssertEqual(blocks[0].markdown, "# Title")
        XCTAssertEqual(blocks[5].markdown, "Final paragraph.")
    }

    func testResolvePromptRequiresPlaceholders() {
        XCTAssertThrowsError(
            try OCRDocumentTranslationService.resolvePrompt(
                template: "Translate this please",
                targetLanguage: "中文",
                batchJSON: "{\"blocks\":[]}"
            )
        )
    }

    func testParseTranslationsAcceptsCodeFencedJSON() throws {
        let response = """
        ```json
        {
          "translations": [
            { "id": "block_1", "translation": "第一段" },
            { "id": "block_2", "translation": "第二段" }
          ]
        }
        ```
        """

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1", "block_2"]
        )

        XCTAssertEqual(translations["block_1"], "第一段")
        XCTAssertEqual(translations["block_2"], "第二段")
    }

    func testParseTranslationsAcceptsTaggedTranslationBlocks() throws {
        let response = """
        [[block_1]]
        # 第一段
        [[/block_1]]

        [[block_2]]
        第二段保留 **Markdown**。
        [[/block_2]]
        """

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1", "block_2"]
        )

        XCTAssertEqual(translations["block_1"], "# 第一段")
        XCTAssertEqual(translations["block_2"], "第二段保留 **Markdown**。")
    }

    func testParseTranslationsAcceptsPlainSingleTranslation() throws {
        let response = """
        # 第一段标题

        这里是只包含译文的 Markdown。
        """

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1"]
        )

        XCTAssertEqual(
            translations["block_1"],
            """
            # 第一段标题

            这里是只包含译文的 Markdown。
            """
        )
    }

    func testParseTranslationsReportsIncompleteJSON() {
        // 真正不完整：translation 字段被截断在字符串中间，无法判定结尾
        let response = #"{"translations":[{"id":"block_1","translation":"第一段未"#

        XCTAssertThrowsError(
            try OCRDocumentTranslationService.parseTranslations(
                from: response,
                expectedIDs: ["block_1"]
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "AI 返回的翻译结果无法解析：JSON 还没有完整输出。")
        }
    }

    func testParseTranslationsLenientlyRecoversFromTruncatedEnvelope() throws {
        // translation 字段已闭合，仅缺最外层 `]}`，宽松解析应能拿到
        let response = #"{"translations":[{"id":"block_1","translation":"第一段"}"#

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1"]
        )

        XCTAssertEqual(translations["block_1"], "第一段")
    }

    func testParseTranslationsLenientlyHandlesSmartQuotesAndUnescapedNewlines() throws {
        // 网页 AI 常见劣化：智能引号 + translation 内未转义换行
        let response = """
        {“translations”: [
          {“id”: “block_1”, “translation”: “第一段
        含有原本未转义的换行内容。”}
        ]}
        """

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1"]
        )

        XCTAssertNotNil(translations["block_1"])
        XCTAssertTrue(translations["block_1"]?.contains("第一段") == true)
    }

    func testParseTranslationsAcceptsTrailingCommas() throws {
        let response = """
        {
          "translations": [
            { "id": "block_1", "translation": "第一段", },
            { "id": "block_2", "translation": "第二段", },
          ]
        }
        """

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1", "block_2"]
        )

        XCTAssertEqual(translations["block_1"], "第一段")
        XCTAssertEqual(translations["block_2"], "第二段")
    }

    func testBuildBatchesCoalescesShortBlocks() async throws {
        // 三段都很短，应被合到同一批（默认 maxBlocksPerBatch: 3）
        let markdown = """
        第一段。

        第二段。

        第三段。
        """

        var promptCount = 0

        _ = try await OCRDocumentTranslationService.translate(
            markdown: markdown,
            options: .init(
                targetLanguage: "中文",
                promptTemplate: SwiftLibPreferences.defaultOCRDocumentTranslationPromptTemplate
            ),
            sender: { _ in
                promptCount += 1
                return """
                [[block_1]]
                One.
                [[/block_1]]

                [[block_2]]
                Two.
                [[/block_2]]

                [[block_3]]
                Three.
                [[/block_3]]
                """
            }
        )

        XCTAssertEqual(promptCount, 1, "短段应该被合并到一个批次")
    }

    func testTranslateSkipsFailedBatchByDefault() async throws {
        let markdown = """
        First paragraph.

        Second paragraph.
        """

        var callCount = 0

        let translated = try await OCRDocumentTranslationService.translate(
            markdown: markdown,
            options: .init(
                targetLanguage: "中文",
                promptTemplate: SwiftLibPreferences.defaultOCRDocumentTranslationPromptTemplate,
                maxBatchCharacters: 60,
                maxBlocksPerBatch: 1,
                retriesPerBatch: 0,
                smallBlockCharacterThreshold: 0  // 强制每段独占一批
            ),
            sender: { _ in
                defer { callCount += 1 }
                if callCount == 0 {
                    return "完全无法识别的回复"
                }
                return """
                [[block_2]]
                第二段。
                [[/block_2]]
                """
            }
        )

        // 第一段失败被跳过保留原文，第二段翻译成功
        XCTAssertTrue(translated.contains("First paragraph."))
        XCTAssertTrue(translated.contains("Second paragraph."))
        XCTAssertTrue(translated.contains("第二段。"))
    }

    func testParseTranslationsPrefersLastCompleteTranslationsPayload() throws {
        let response = """
        只返回：
        {"translations":[{"id":"block_1","translation":"译文"}]}

        实际回复：
        {"translations":[
          {"id":"block_1","translation":"第一段"},
          {"id":"block_2","translation":"第二段"}
        ]}
        """

        let translations = try OCRDocumentTranslationService.parseTranslations(
            from: response,
            expectedIDs: ["block_1", "block_2"]
        )

        XCTAssertEqual(translations["block_1"], "第一段")
        XCTAssertEqual(translations["block_2"], "第二段")
    }

    func testStoredLegacyPromptFallsBackToNewDefaultTemplate() {
        for template in SwiftLibPreferences.legacyOCRDocumentTranslationPromptTemplates {
            UserDefaults.standard.set(
                template,
                forKey: SwiftLibPreferences.ocrDocumentTranslationPromptTemplateKey
            )

            XCTAssertEqual(
                SwiftLibPreferences.ocrDocumentTranslationPromptTemplate,
                SwiftLibPreferences.defaultOCRDocumentTranslationPromptTemplate
            )
        }
    }

    func testTranslateBatchesDocumentAndBuildsBilingualMarkdown() async throws {
        let markdown = """
        Alpha paragraph.

        Beta paragraph is a little longer.

        Gamma paragraph.
        """

        var prompts: [String] = []
        var callCount = 0

        let translated = try await OCRDocumentTranslationService.translate(
            markdown: markdown,
            options: .init(
                targetLanguage: "中文",
                promptTemplate: SwiftLibPreferences.defaultOCRDocumentTranslationPromptTemplate,
                maxBatchCharacters: 60,
                maxBlocksPerBatch: 2
            ),
            sender: { prompt in
                prompts.append(prompt)
                defer { callCount += 1 }

                switch callCount {
                case 0:
                    return """
                    [[block_1]]
                    阿尔法段落。
                    [[/block_1]]

                    [[block_2]]
                    贝塔段落稍微长一些。
                    [[/block_2]]
                    """
                default:
                    return """
                    [[block_3]]
                    伽马段落。
                    [[/block_3]]
                    """
                }
            }
        )

        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[0].contains("[[block_1]]"))
        XCTAssertTrue(prompts[1].contains("[[block_1]]"))
        XCTAssertTrue(prompts[0].contains("\"block_1\""))
        XCTAssertTrue(prompts[1].contains("\"block_3\""))
        XCTAssertTrue(translated.contains("Alpha paragraph."))
        XCTAssertTrue(translated.contains("阿尔法段落。"))
        XCTAssertTrue(translated.contains(#"<div class="swiftlib-ocr-translation">"#))
    }
}
