import Foundation

enum OCRDocumentTranslationService {
    struct Options: Equatable {
        var targetLanguage: String
        var promptTemplate: String
        var maxBatchCharacters: Int = 2400
        /// 单批最多包含多少段。短段会自动合并到同一批，最多达到这个上限。
        var maxBlocksPerBatch: Int = 3
        /// 每批失败后自动重试的次数（不含首次发送）。
        var retriesPerBatch: Int = 1
        /// 当某批反复失败仍无法解析时，是否跳过该批继续往下翻译（保留原文）。
        var skipFailedBatches: Bool = true
        /// 单批中允许"短块合并"的字符上限。超过该长度的段落总是单独成批。
        var smallBlockCharacterThreshold: Int = 280
    }

    struct Progress: Equatable {
        let completedBatches: Int
        let totalBatches: Int
        let completedBlocks: Int
        let totalBlocks: Int
        let failedBlocks: Int

        init(
            completedBatches: Int,
            totalBatches: Int,
            completedBlocks: Int,
            totalBlocks: Int,
            failedBlocks: Int = 0
        ) {
            self.completedBatches = completedBatches
            self.totalBatches = totalBatches
            self.completedBlocks = completedBlocks
            self.totalBlocks = totalBlocks
            self.failedBlocks = failedBlocks
        }
    }

    /// 流式翻译事件：每批完成 / 失败 / 全部完成时产出一个事件。
    struct StreamEvent {
        public let progress: Progress
        public let partialBilingualMarkdown: String
        public let lastBatchError: String?
    }

    struct MarkdownBlock: Equatable {
        let translationID: String?
        let markdown: String
        let isTranslatable: Bool
    }

    enum ServiceError: LocalizedError {
        case invalidPromptTemplate
        case invalidBatchConfiguration
        case invalidResponse(String)
        case missingTranslation(String)

        var errorDescription: String? {
            switch self {
            case .invalidPromptTemplate:
                return "连续翻译 Prompt 缺少必需占位符 `{{target_language}}` 或 `{{batch_json}}`。"
            case .invalidBatchConfiguration:
                return "连续翻译的批处理配置无效，请检查最大段落数和最大字符数。"
            case .invalidResponse(let detail):
                return "AI 返回的翻译结果无法解析：\(detail)"
            case .missingTranslation(let blockID):
                return "AI 返回结果缺少段落 \(blockID) 的译文。"
            }
        }
    }

    private struct TranslationRequestPayload: Encodable {
        let sourceFormat = "markdown"
        let blocks: [TranslationRequestBlock]
    }

    private struct TranslationRequestBlock: Encodable {
        let id: String
        let text: String
    }

    private struct TranslationBatch {
        let requestBlocks: [TranslationRequestBlock]
    }

    @MainActor
    static func translate(
        markdown: String,
        options: Options,
        sender: (String) async throws -> String,
        onProgress: ((Progress) -> Void)? = nil,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        guard options.maxBatchCharacters > 0, options.maxBlocksPerBatch > 0 else {
            throw ServiceError.invalidBatchConfiguration
        }

        let identifiedBlocks = assignTranslationIdentifiers(to: parseMarkdownBlocks(markdown))
        let batches = buildBatches(from: identifiedBlocks, options: options)
        let totalBlocks = identifiedBlocks.filter(\.isTranslatable).count

        var translatedByID: [String: String] = [:]
        translatedByID.reserveCapacity(totalBlocks)
        var failedBlocks = 0
        var lastError: Error?

        if batches.isEmpty {
            return buildBilingualMarkdown(from: identifiedBlocks, translationsByID: translatedByID)
        }

        for (batchIndex, batch) in batches.enumerated() {
            try Task.checkCancellation()

            let expectedIDs = batch.requestBlocks.map(\.id)

            do {
                let parsedTranslations = try await runBatchWithRetries(
                    batch: batch,
                    options: options,
                    sender: sender
                )

                for blockID in expectedIDs {
                    guard let translation = parsedTranslations[blockID] else {
                        throw ServiceError.missingTranslation(blockID)
                    }
                    translatedByID[blockID] = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if options.skipFailedBatches {
                    failedBlocks += expectedIDs.count
                    lastError = error
                } else {
                    throw error
                }
            }

            onProgress?(
                Progress(
                    completedBatches: batchIndex + 1,
                    totalBatches: batches.count,
                    completedBlocks: translatedByID.count,
                    totalBlocks: totalBlocks,
                    failedBlocks: failedBlocks
                )
            )

            // 流式：每批完成后即时推送一次部分双语 markdown
            if let onPartial {
                let partial = buildBilingualMarkdown(
                    from: identifiedBlocks,
                    translationsByID: translatedByID
                )
                onPartial(partial)
            }
        }

        let finalMarkdown = buildBilingualMarkdown(from: identifiedBlocks, translationsByID: translatedByID)

        // 全部都失败才向上抛错；至少有部分成功则放行（降级）
        if translatedByID.isEmpty, let lastError {
            throw lastError
        }

        return finalMarkdown
    }

    /// 流式翻译变体：每批完成后通过 AsyncThrowingStream 推送 StreamEvent。
    @MainActor
    static func translateStream(
        markdown: String,
        options: Options,
        sender: @escaping (String) async throws -> String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    guard options.maxBatchCharacters > 0, options.maxBlocksPerBatch > 0 else {
                        throw ServiceError.invalidBatchConfiguration
                    }

                    let identifiedBlocks = assignTranslationIdentifiers(to: parseMarkdownBlocks(markdown))
                    let batches = buildBatches(from: identifiedBlocks, options: options)
                    let totalBlocks = identifiedBlocks.filter(\.isTranslatable).count

                    var translatedByID: [String: String] = [:]
                    translatedByID.reserveCapacity(totalBlocks)
                    var failedBlocks = 0

                    if batches.isEmpty {
                        continuation.yield(
                            StreamEvent(
                                progress: Progress(
                                    completedBatches: 0,
                                    totalBatches: 0,
                                    completedBlocks: 0,
                                    totalBlocks: 0
                                ),
                                partialBilingualMarkdown: buildBilingualMarkdown(
                                    from: identifiedBlocks,
                                    translationsByID: [:]
                                ),
                                lastBatchError: nil
                            )
                        )
                        continuation.finish()
                        return
                    }

                    for (batchIndex, batch) in batches.enumerated() {
                        try Task.checkCancellation()

                        let expectedIDs = batch.requestBlocks.map(\.id)
                        var batchError: String?

                        do {
                            let parsedTranslations = try await runBatchWithRetries(
                                batch: batch,
                                options: options,
                                sender: sender
                            )

                            for blockID in expectedIDs {
                                guard let translation = parsedTranslations[blockID] else {
                                    throw ServiceError.missingTranslation(blockID)
                                }
                                translatedByID[blockID] = translation
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if options.skipFailedBatches {
                                failedBlocks += expectedIDs.count
                                batchError = error.localizedDescription
                            } else {
                                throw error
                            }
                        }

                        let partial = buildBilingualMarkdown(
                            from: identifiedBlocks,
                            translationsByID: translatedByID
                        )

                        continuation.yield(
                            StreamEvent(
                                progress: Progress(
                                    completedBatches: batchIndex + 1,
                                    totalBatches: batches.count,
                                    completedBlocks: translatedByID.count,
                                    totalBlocks: totalBlocks,
                                    failedBlocks: failedBlocks
                                ),
                                partialBilingualMarkdown: partial,
                                lastBatchError: batchError
                            )
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 单批发送 + 重试 + 多策略解析
    @MainActor
    private static func runBatchWithRetries(
        batch: TranslationBatch,
        options: Options,
        sender: (String) async throws -> String
    ) async throws -> [String: String] {
        let payload = TranslationRequestPayload(blocks: batch.requestBlocks)
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw ServiceError.invalidResponse("无法编码待翻译段落。")
        }

        let prompt = try resolvePrompt(
            template: options.promptTemplate,
            targetLanguage: options.targetLanguage,
            batchJSON: payloadString
        )
        let expectedIDs = batch.requestBlocks.map(\.id)

        let totalAttempts = max(1, 1 + options.retriesPerBatch)
        var lastError: Error = ServiceError.invalidResponse("未知错误。")

        for attempt in 0..<totalAttempts {
            try Task.checkCancellation()
            do {
                let response = try await sender(prompt)
                return try parseTranslations(from: response, expectedIDs: expectedIDs)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                // 最后一次失败前小退避，避免对网页 AI 服务过度重发
                if attempt < totalAttempts - 1 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }

        throw lastError
    }

    static func resolvePrompt(template: String, targetLanguage: String, batchJSON: String) throws -> String {
        guard template.contains("{{target_language}}"), template.contains("{{batch_json}}") else {
            throw ServiceError.invalidPromptTemplate
        }

        return template
            .replacingOccurrences(of: "{{target_language}}", with: targetLanguage)
            .replacingOccurrences(of: "{{batch_json}}", with: batchJSON)
    }

    static func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var index = 0
        var blocks: [MarkdownBlock] = []

        while index < lines.count {
            while index < lines.count && lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
            }
            guard index < lines.count else { break }

            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let fence = parseFence(trimmed) {
                var codeLines: [String] = [line]
                index += 1
                while index < lines.count {
                    codeLines.append(lines[index])
                    let candidate = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    index += 1
                    if isClosingFence(candidate, matching: fence) {
                        break
                    }
                }
                blocks.append(
                    MarkdownBlock(
                        translationID: nil,
                        markdown: trimBlock(codeLines.joined(separator: "\n")),
                        isTranslatable: false
                    )
                )
                continue
            }

            if let htmlTag = parseHTMLBlockOpen(trimmed) {
                var htmlLines: [String] = [line]
                index += 1
                let closingTag = "</\(htmlTag)>"
                if !trimmed.contains(closingTag) {
                    while index < lines.count {
                        htmlLines.append(lines[index])
                        if lines[index].contains(closingTag) {
                            index += 1
                            break
                        }
                        index += 1
                    }
                }
                blocks.append(
                    MarkdownBlock(
                        translationID: nil,
                        markdown: trimBlock(htmlLines.joined(separator: "\n")),
                        isTranslatable: false
                    )
                )
                continue
            }

            var blockLines: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                blockLines.append(candidate)
                index += 1
            }

            let blockMarkdown = trimBlock(blockLines.joined(separator: "\n"))
            guard !blockMarkdown.isEmpty else { continue }

            blocks.append(
                MarkdownBlock(
                    translationID: nil,
                    markdown: blockMarkdown,
                    isTranslatable: isTranslatableBlock(blockMarkdown)
                )
            )
        }

        return blocks
    }

    static func parseTranslations(from response: String, expectedIDs: [String]) throws -> [String: String] {
        // 1) 标签格式：[[block_X]] ... [[/block_X]]，最稳健，没有转义问题
        if let taggedTranslations = try parseTaggedTranslationsIfPresent(
            response,
            expectedIDs: expectedIDs
        ) {
            return taggedTranslations
        }

        // 2) 单段纯文本兜底（仅一个 block 时）
        if expectedIDs.count == 1,
           let blockID = expectedIDs.first,
           let plainTranslation = parsePlainSingleTranslationIfPresent(response) {
            return [blockID: plainTranslation]
        }

        // 3) 标准 JSON 解析路径：先尝试原文，再尝试归一化后的版本
        let normalizedResponse = normalizeForJSONParsing(response)
        let responsesToTry: [String] = (normalizedResponse == response)
            ? [response]
            : [response, normalizedResponse]

        var sawInvalidJSON = false
        var sawTranslationsEnvelope = false
        var sawIncompleteJSON = false
        var lastMissingTranslationID: String?

        for responseVariant in responsesToTry {
            var candidates = StructuredJSONCandidateExtractor.completeCandidates(in: responseVariant)
            if candidates.isEmpty {
                switch StructuredJSONCandidateExtractor.candidateState(in: responseVariant) {
                case .complete(let value):
                    candidates = [value]
                case .incomplete:
                    sawIncompleteJSON = true
                case .none:
                    candidates = [extractJSONCandidate(from: responseVariant)]
                }
            }

            for candidate in candidates.reversed() {
                do {
                    return try parseTranslationsCandidate(candidate, expectedIDs: expectedIDs)
                } catch ServiceError.invalidResponse(let message) {
                    if message == "没有找到合法 JSON。" {
                        sawInvalidJSON = true
                    } else if message == "JSON 中没有找到 `translations`。" {
                        sawTranslationsEnvelope = true
                    }
                } catch ServiceError.missingTranslation(let blockID) {
                    lastMissingTranslationID = blockID
                } catch {
                    continue
                }
            }
        }

        // 4) 最后兜底：宽松正则提取——即使 JSON 有未转义换行 / 多余引号也能提取
        if let lenient = parseLenientTranslations(
            from: response,
            expectedIDs: expectedIDs
        ), !lenient.isEmpty {
            for blockID in expectedIDs where lenient[blockID] == nil {
                throw ServiceError.missingTranslation(blockID)
            }
            return lenient
        }

        if sawIncompleteJSON {
            throw ServiceError.invalidResponse("JSON 还没有完整输出。")
        }
        if let lastMissingTranslationID {
            throw ServiceError.missingTranslation(lastMissingTranslationID)
        }
        if sawTranslationsEnvelope {
            throw ServiceError.invalidResponse("JSON 中没有找到 `translations`。")
        }
        if sawInvalidJSON {
            throw ServiceError.invalidResponse("没有找到合法 JSON。")
        }

        throw ServiceError.invalidResponse("没有找到合法 JSON。")
    }

    /// 把网页 AI 经常返回的非标准 JSON 文本归一化：智能引号 → 直引号，全角冒号/逗号 → 半角，去尾逗号。
    static func normalizeForJSONParsing(_ text: String) -> String {
        var result = text

        // 智能引号 → 直引号（"" → "; '' → '）
        let quoteMap: [(Character, Character)] = [
            ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{2018}", "'"),  ("\u{2019}", "'"),
            ("\u{201E}", "\""), ("\u{201F}", "\""),
            ("\u{2033}", "\""), ("\u{2032}", "'"),
        ]
        result = String(result.map { ch in
            quoteMap.first(where: { $0.0 == ch }).map { $0.1 } ?? ch
        })

        // 全角标点：仅替换 JSON 结构常见的冒号/逗号/方括号/花括号——避免破坏正文
        // 这里只替换出现在结构上下文的：冒号后接空白或引号的情况
        result = result.replacingOccurrences(
            of: #"：(\s*["\[{])"#,
            with: ":$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"，(\s*["\}\]])"#,
            with: ",$1",
            options: .regularExpression
        )

        // 去尾逗号：,] 或 ,}
        result = result.replacingOccurrences(
            of: #",(\s*[}\]])"#,
            with: "$1",
            options: .regularExpression
        )

        return result
    }

    /// 宽松正则提取译文：当 JSON 严重畸形（包含未转义换行 / 引号 等）时使用。
    /// 原理：直接按 schema 找 `"id":"block_X"` 配对的 `"translation":"..."`，
    /// translation 的字符串结尾以 `"\s*[,}]` 启发式判定，允许字符串内有未转义字符。
    static func parseLenientTranslations(
        from response: String,
        expectedIDs: [String]
    ) -> [String: String]? {
        guard !expectedIDs.isEmpty else { return nil }

        var translations: [String: String] = [:]
        let scaledText = response

        for blockID in expectedIDs {
            // 标签格式（与 [[block_X]]…[[/block_X]] 同义的常见变体）
            for (open, close) in [
                ("[[\(blockID)]]", "[[/\(blockID)]]"),
                ("【\(blockID)】", "【/\(blockID)】"),
                ("<<\(blockID)>>", "<</\(blockID)>>"),
            ] {
                if let openRange = scaledText.range(of: open),
                   let closeRange = scaledText.range(of: close, range: openRange.upperBound..<scaledText.endIndex) {
                    let value = scaledText[openRange.upperBound..<closeRange.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        translations[blockID] = value
                        break
                    }
                }
            }

            if translations[blockID] != nil { continue }

            // JSON-ish 格式：找 "id":"block_X"，再找最近的 "translation":"..."
            if let extracted = extractTranslationByIDAnchor(in: scaledText, blockID: blockID) {
                translations[blockID] = extracted
            }
        }

        return translations.isEmpty ? nil : translations
    }

    private static func extractTranslationByIDAnchor(
        in text: String,
        blockID: String
    ) -> String? {
        // 匹配 "id" 字段：兼容直引号、智能引号、全/半角冒号
        let idPattern = #"["“”]id["“”]\s*[:：]\s*["“”]\#(NSRegularExpression.escapedPattern(for: blockID))["“”]"#
        guard let idRegex = try? NSRegularExpression(pattern: idPattern, options: []),
              let idMatch = idRegex.firstMatch(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text)
              ) else {
            return nil
        }

        guard let idRange = Range(idMatch.range, in: text) else { return nil }

        // 在 id 锚点附近（前后 8KB）搜索 translation 字段
        let searchStart = text.index(idRange.lowerBound, offsetBy: -min(8000, text.distance(from: text.startIndex, to: idRange.lowerBound)))
        let searchEnd = text.index(idRange.upperBound, offsetBy: min(16000, text.distance(from: idRange.upperBound, to: text.endIndex)))
        let searchSlice = text[searchStart..<searchEnd]

        let translationPattern = #"["“”](?:translation|translated|text)["“”]\s*[:：]\s*["“”]"#
        guard let trRegex = try? NSRegularExpression(pattern: translationPattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(searchSlice.startIndex..., in: searchSlice)
        let matches = trRegex.matches(in: String(searchSlice), options: [], range: nsRange)
        guard !matches.isEmpty else { return nil }

        // 选择距离 id 锚点最近的 translation 起点
        let idStartInSlice = text.distance(from: searchStart, to: idRange.lowerBound)
        let bestMatch = matches.min(by: { abs($0.range.location - idStartInSlice) < abs($1.range.location - idStartInSlice) })!

        guard let valueStartRange = Range(bestMatch.range, in: searchSlice) else { return nil }
        let valueStart = valueStartRange.upperBound

        // 找结束引号：出现 `"\s*[,}]` 视为结束（容忍未转义内部引号）
        var cursor = valueStart
        var lastQuoteIndex: String.Index?
        while cursor < searchSlice.endIndex {
            let ch = searchSlice[cursor]
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                // 向后看：跳过空白后是 `,` 或 `}` ⇒ 这是字符串结尾
                var look = searchSlice.index(after: cursor)
                while look < searchSlice.endIndex, searchSlice[look].isWhitespace {
                    look = searchSlice.index(after: look)
                }
                if look < searchSlice.endIndex,
                   searchSlice[look] == "," || searchSlice[look] == "}" || searchSlice[look] == "]" {
                    lastQuoteIndex = cursor
                    break
                }
                lastQuoteIndex = cursor // 退而求其次
            }
            cursor = searchSlice.index(after: cursor)
        }

        guard let endQuote = lastQuoteIndex else { return nil }
        let raw = String(searchSlice[valueStart..<endQuote])

        // 还原常见转义
        let unescaped = raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return unescaped.isEmpty ? nil : unescaped
    }

    static func buildBilingualMarkdown(
        from blocks: [MarkdownBlock],
        translationsByID: [String: String]
    ) -> String {
        var renderedBlocks: [String] = []
        renderedBlocks.reserveCapacity(blocks.count * 2)

        for block in blocks {
            renderedBlocks.append(block.markdown)

            guard
                let blockID = block.translationID,
                let translation = translationsByID[blockID]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !translation.isEmpty
            else {
                continue
            }

            let translationHTML = MarkdownHTMLRenderer.render(markdown: translation, baseURL: nil)
            renderedBlocks.append(
                """
                <div class="swiftlib-ocr-translation">
                \(translationHTML)
                </div>
                """
            )
        }

        return renderedBlocks.joined(separator: "\n\n")
    }

    private static func buildBatches(
        from blocks: [MarkdownBlock],
        options: Options
    ) -> [TranslationBatch] {
        let translatableBlocks = blocks.filter(\.isTranslatable)
        guard !translatableBlocks.isEmpty else { return [] }

        var batches: [TranslationBatch] = []
        var currentBlocks: [TranslationRequestBlock] = []
        var currentCharacterCount = 0

        func flushCurrentBatch() {
            guard !currentBlocks.isEmpty else { return }
            batches.append(TranslationBatch(requestBlocks: currentBlocks))
            currentBlocks.removeAll(keepingCapacity: true)
            currentCharacterCount = 0
        }

        for block in translatableBlocks {
            guard let blockID = block.translationID else { continue }
            let blockLength = max(block.markdown.count, 1)
            let isLargeBlock = blockLength > options.smallBlockCharacterThreshold

            // 大段独占一批，避免一次发太多 token、降低 AI 输出 JSON 变形概率
            if isLargeBlock {
                flushCurrentBatch()
                batches.append(
                    TranslationBatch(
                        requestBlocks: [TranslationRequestBlock(id: blockID, text: block.markdown)]
                    )
                )
                continue
            }

            // 小段合批：受 maxBlocksPerBatch + maxBatchCharacters 双重约束
            let wouldOverflowCount = currentBlocks.count >= options.maxBlocksPerBatch
            let wouldOverflowCharacters = !currentBlocks.isEmpty
                && currentCharacterCount + blockLength > options.maxBatchCharacters

            if wouldOverflowCount || wouldOverflowCharacters {
                flushCurrentBatch()
            }

            currentBlocks.append(TranslationRequestBlock(id: blockID, text: block.markdown))
            currentCharacterCount += blockLength
        }

        flushCurrentBatch()
        return batches
    }

    private static func assignTranslationIdentifiers(to blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var translatedIndex = 0
        return blocks.map { block in
            guard block.isTranslatable else { return block }
            translatedIndex += 1
            return MarkdownBlock(
                translationID: "block_\(translatedIndex)",
                markdown: block.markdown,
                isTranslatable: true
            )
        }
    }

    private static func dictionary(from items: [[String: Any]]) -> [String: String] {
        var translations: [String: String] = [:]
        for item in items {
            guard let blockID = item["id"] as? String else { continue }
            let translation = item["translation"] as? String ?? item["translated"] as? String ?? ""
            translations[blockID] = translation
        }
        return translations
    }

    private static func parsePlainSingleTranslationIfPresent(_ response: String) -> String? {
        let trimmed = stripCodeFence(response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let structuredState = StructuredJSONCandidateExtractor.candidateState(
            in: trimmed,
            requireStructuredPrefix: true
        )
        if case .complete = structuredState {
            return nil
        }
        if case .incomplete = structuredState {
            return nil
        }

        return trimmed
    }

    private static func parseTranslationsCandidate(
        _ candidate: String,
        expectedIDs: [String]
    ) throws -> [String: String] {
        guard let data = candidate.data(using: .utf8) else {
            throw ServiceError.invalidResponse("结果不是有效的 UTF-8 文本。")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ServiceError.invalidResponse("没有找到合法 JSON。")
        }

        var translations: [String: String] = [:]

        if let envelope = object as? [String: Any] {
            if let items = envelope["translations"] as? [[String: Any]] {
                translations = dictionary(from: items)
            } else {
                for blockID in expectedIDs {
                    if let value = envelope[blockID] as? String {
                        translations[blockID] = value
                    }
                }
            }
        } else if let items = object as? [[String: Any]] {
            translations = dictionary(from: items)
        }

        guard !translations.isEmpty else {
            throw ServiceError.invalidResponse("JSON 中没有找到 `translations`。")
        }

        for blockID in expectedIDs where translations[blockID] == nil {
            throw ServiceError.missingTranslation(blockID)
        }

        return translations
    }

    private static func parseTaggedTranslationsIfPresent(
        _ response: String,
        expectedIDs: [String]
    ) throws -> [String: String]? {
        var translations: [String: String] = [:]
        var sawTaggedResponse = false

        for blockID in expectedIDs {
            let openTag = "[[\(blockID)]]"
            let closeTag = "[[/\(blockID)]]"

            guard let openRange = response.range(of: openTag) else { continue }
            sawTaggedResponse = true

            let remaining = response[openRange.upperBound...]
            guard let closeRange = remaining.range(of: closeTag) else {
                throw ServiceError.invalidResponse("译文块 \(blockID) 没有结束标记。")
            }

            let translation = response[openRange.upperBound..<closeRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            translations[blockID] = translation
        }

        guard sawTaggedResponse else { return nil }

        for blockID in expectedIDs where translations[blockID] == nil {
            throw ServiceError.missingTranslation(blockID)
        }

        return translations
    }

    private static func extractJSONCandidate(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.hasPrefix("```") {
            return stripCodeFence(trimmed)
        }

        if case .complete(let candidate) = StructuredJSONCandidateExtractor.candidateState(in: trimmed) {
            return candidate
        }

        let firstBrace = trimmed.firstIndex(of: "{")
        let firstBracket = trimmed.firstIndex(of: "[")

        let startIndex: String.Index?
        switch (firstBrace, firstBracket) {
        case let (brace?, bracket?):
            startIndex = min(brace, bracket)
        case let (brace?, nil):
            startIndex = brace
        case let (nil, bracket?):
            startIndex = bracket
        default:
            startIndex = nil
        }

        guard let startIndex else { return trimmed }

        let opening = trimmed[startIndex]
        let closing: Character = opening == "{" ? "}" : "]"
        guard let endIndex = trimmed.lastIndex(of: closing), endIndex >= startIndex else {
            return trimmed
        }

        return String(trimmed[startIndex...endIndex])
    }

    private static func stripCodeFence(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: "\n")
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeFirst()
        }
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTranslatableBlock(_ block: String) -> Bool {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if parseFence(trimmed) != nil { return false }
        if parseHTMLBlockOpen(trimmed) != nil { return false }
        if trimmed.hasPrefix("$$") { return false }
        if isThematicBreak(trimmed) { return false }
        if isMarkdownTableBlock(block) { return false }
        if isImageOnlyBlock(block) { return false }
        return true
    }

    private static func isImageOnlyBlock(_ block: String) -> Bool {
        let lines = block
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { $0.hasPrefix("![") && $0.contains("](") && $0.hasSuffix(")") }
    }

    private static func isMarkdownTableBlock(_ block: String) -> Bool {
        let lines = block
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first, isTableRow(first) else { return false }
        return lines.allSatisfy { isTableRow($0) || isTableSeparator($0) }
    }

    private static func isTableRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1
    }

    private static func isTableSeparator(_ trimmed: String) -> Bool {
        guard isTableRow(trimmed) else { return false }
        let inner = trimmed.dropFirst().dropLast()
        let cells = inner.split(separator: "|", omittingEmptySubsequences: false)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let content = cell.trimmingCharacters(in: .whitespaces)
            return !content.isEmpty && content.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let scalars = trimmed.filter { !$0.isWhitespace }
        guard scalars.count >= 3 else { return false }
        return Set(scalars).count == 1 && ["-", "_", "*"].contains(String(scalars.first!))
    }

    private struct Fence {
        let marker: Character
        let count: Int
    }

    private static let htmlBlockTags: Set<String> = [
        "table", "div", "p", "pre", "blockquote", "ul", "ol", "dl",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "section",
        "article", "aside", "details", "figcaption", "figure",
        "header", "footer", "main", "nav", "summary"
    ]

    private static func parseFence(_ trimmed: String) -> Fence? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        return Fence(marker: marker, count: count)
    }

    private static func isClosingFence(_ trimmed: String, matching fence: Fence) -> Bool {
        guard let marker = trimmed.first, marker == fence.marker else { return false }
        return trimmed.prefix { $0 == marker }.count >= fence.count
    }

    private static func parseHTMLBlockOpen(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("<") else { return nil }
        let tail = trimmed.dropFirst()
        let tag = tail.prefix { $0.isLetter }
        guard !tag.isEmpty else { return nil }
        let lower = String(tag).lowercased()
        return htmlBlockTags.contains(lower) ? lower : nil
    }

    private static func trimBlock(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    }
}
