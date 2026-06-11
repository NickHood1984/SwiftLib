import Foundation

extension MetadataResolution {
    public static func buildCNKICandidate(
        title rawTitle: String,
        metaText rawMetaText: String,
        snippet rawSnippet: String?,
        detailURL: String,
        seed: MetadataResolutionSeed,
        cnkiExport: CNKIExportLocator? = nil
    ) -> MetadataCandidate? {
        let title = cleanCandidateTitle(rawTitle)
        guard !title.isEmpty else { return nil }

        var metaText = rawMetaText.replacingOccurrences(of: rawTitle, with: " ")
        metaText = metaText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let authors = extractAuthors(fromMetadataText: metaText)
        let journal = extractJournal(fromMetadataText: metaText)
        let year = extractYear(fromMetadataText: metaText)
        let snippet = rawSnippet?.swiftlib_nilIfBlank

        let titleScore = titleSimilarity(seed.title ?? seed.fileName, title)

        // 权重调整：降低标题权重，提升作者和年份权重，以应对中文截断文件名导致标题相似度系统性偏低的问题
        var score = titleScore * 0.60  // 原 0.72
        let authorMatched = authorMatches(seed.firstAuthor, authors: authors)
        if authorMatched { score += 0.25 }  // 原 0.18
        var yearMatched = false
        var yearDelta = -1
        if let seedYear = seed.year, let year {
            yearDelta = abs(seedYear - year)
            if seedYear == year {
                score += 0.10  // 原 0.07
                yearMatched = true
            } else if yearDelta == 1 {
                score += 0.04  // 原 0.03
            }
        }
        let journalMatched = journalMatches(seed.journal, candidateJournal: journal)
        if journalMatched {
            score += 0.05  // 原 0.03
        }
        if containsHanCharacters(title) == seed.shouldSearchCNKI {
            score += 0.02
        }

        // 🔍 评分日志：记录每个候选的详细分数
        metadataLog.debug("""
            📊 [buildCandidate] 候选: \(title, privacy: .public)
              seed.title=\(seed.title ?? "nil", privacy: .public) seed.author=\(seed.firstAuthor ?? "nil", privacy: .public) seed.year=\(seed.year.map(String.init) ?? "nil", privacy: .public)
              titleScore=\(String(format: "%.3f", titleScore)) authorMatch=\(authorMatched) yearMatch=\(yearMatched) yearDelta=\(yearDelta) journalMatch=\(journalMatched)
              候选作者=\(authors.map(\.displayName).joined(separator: ","), privacy: .public) 候选年份=\(year.map(String.init) ?? "nil", privacy: .public)
              最终得分=\(String(format: "%.3f", min(score, 1))) 阈值=\(cnkiCandidateThreshold)
            """)
        if min(score, 1) >= cnkiCandidateThreshold {
            metadataLog.debug("✅ [buildCandidate] 得分 \(String(format: "%.3f", min(score, 1))) 达阈值，加入候选列表")
        } else {
            metadataLog.debug("❌ [buildCandidate] 得分 \(String(format: "%.3f", min(score, 1))) 未达阈值 \(cnkiCandidateThreshold)，将被过滤")
        }

        return MetadataCandidate(
            source: .cnki,
            title: title,
            authors: authors,
            journal: journal,
            year: year,
            detailURL: detailURL,
            score: min(score, 1),
            snippet: snippet,
            workKind: seed.workKindHint == .unknown ? .journalArticle : seed.workKindHint,
            referenceType: (seed.workKindHint == .unknown ? MetadataWorkKind.journalArticle : seed.workKindHint).referenceType,
            matchedBy: ["title", "author", "year", "journal"],
            cnkiExport: cnkiExport
        )
    }

    /// Multi-field score for a structured Chinese-source candidate (Wanfang/VIP
    /// browser search results arrive with structured title/authors/journal/year,
    /// unlike CNKI's free metaText).
    ///
    /// Uses the same weighting as `buildCNKICandidate` — title 0.60, first
    /// author 0.25, exact year 0.10 (±1 → 0.04), journal 0.05 — so candidates
    /// from all three Chinese channels are ranked on a comparable scale.
    /// Replaces the old `max(titleScore, 0.45)` floor that inflated weakly
    /// related Wanfang/VIP results above honestly-scored CNKI candidates.
    public static func scoreStructuredChineseCandidate(
        seed: MetadataResolutionSeed,
        title: String,
        authors: [AuthorName],
        journal: String?,
        year: Int?
    ) -> Double {
        let titleScore = titleSimilarity(seed.title ?? seed.fileName, title)
        var score = titleScore * 0.60
        if authorMatches(seed.firstAuthor, authors: authors) {
            score += 0.25
        }
        if let seedYear = seed.year, let year {
            if seedYear == year {
                score += 0.10
            } else if abs(seedYear - year) == 1 {
                score += 0.04
            }
        }
        if journalMatches(seed.journal, candidateJournal: journal) {
            score += 0.05
        }
        if containsHanCharacters(title) == seed.shouldSearchCNKI {
            score += 0.02
        }
        return min(score, 1)
    }

    /// Author conversion for structured Chinese-source results: Han names must
    /// become family-only `AuthorName`s (matching the CNKI extraction path).
    /// `AuthorName.parse` is Western-name oriented and splits a spaced Han name
    /// like "张 三" into given="张" family="三", which corrupts CSL output.
    public static func structuredChineseAuthor(from rawName: String) -> AuthorName {
        let normalized = normalizeWhitespaceAndWidth(rawName)
        guard containsHanCharacters(normalized) else {
            return AuthorName.parse(normalized)
        }
        return AuthorName(given: "", family: normalized.replacingOccurrences(of: " ", with: ""))
    }

    public static func preferredAutomaticCandidate(from candidates: [MetadataCandidate]) -> MetadataCandidate? {
        let sorted = candidates.sorted { $0.score > $1.score }
        guard let first = sorted.first, first.score >= candidateThreshold else { return nil }
        guard let second = sorted.dropFirst().first else {
            return first
        }
        guard first.score >= automaticCandidateThreshold else { return nil }
        return (first.score - second.score) >= automaticCandidateMargin ? first : nil
    }

    public static func preferredAutomaticCNKICandidate(from candidates: [MetadataCandidate]) -> MetadataCandidate? {
        // 使用 CNKI 专用阈值，而非通用阈值
        let sorted = candidates.sorted { $0.score > $1.score }

        metadataLog.debug("🎯 [autoSelect] 共 \(candidates.count) 个候选，阈值=\(cnkiCandidateThreshold) 自动阈值=\(automaticCNKIRefreshThreshold)")
        sorted.enumerated().forEach { i, c in
            metadataLog.debug("🎯 [autoSelect] [\(i)] score=\(String(format: "%.3f", c.score)) title=\(c.title, privacy: .public)")
        }

        guard let first = sorted.first, first.score >= cnkiCandidateThreshold else {
            metadataLog.debug("🎯 [autoSelect] 最高分未达基础阈值，返回 nil")
            return nil
        }
        guard let second = sorted.dropFirst().first else {
            metadataLog.debug("🎯 [autoSelect] 唯一候选，直接返回: \(first.title, privacy: .public) score=\(String(format: "%.3f", first.score))")
            return first
        }
        guard first.score >= automaticCNKIRefreshThreshold else {
            metadataLog.debug("🎯 [autoSelect] 最高分 \(String(format: "%.3f", first.score)) 未达自动阈值 \(automaticCNKIRefreshThreshold)，需要手动确认")
            return nil
        }
        let margin = first.score - second.score
        if margin >= automaticCandidateMargin {
            metadataLog.debug("🎯 [autoSelect] 自动选择: \(first.title, privacy: .public) score=\(String(format: "%.3f", first.score)) margin=\(String(format: "%.3f", margin))")
            return first
        } else {
            metadataLog.debug("🎯 [autoSelect] 差距 \(String(format: "%.3f", margin)) < \(automaticCandidateMargin)，候选不够确定，需手动确认")
            return nil
        }
    }


    private static func authorMatches(_ seedAuthor: String?, authors: [AuthorName]) -> Bool {
        guard let seedAuthor = seedAuthor?.swiftlib_nilIfBlank else { return false }
        let normalizedSeed = normalizedComparableText(seedAuthor)
        return authors.contains { author in
            let display = normalizedComparableText(author.displayName)
            let family = normalizedComparableText(author.family)
            return !display.isEmpty && (display.contains(normalizedSeed) || family.contains(normalizedSeed) || normalizedSeed.contains(family))
        }
    }

    private static func journalMatches(_ seedJournal: String?, candidateJournal: String?) -> Bool {
        guard let seedJournal = seedJournal?.swiftlib_nilIfBlank,
              let candidateJournal = candidateJournal?.swiftlib_nilIfBlank else { return false }
        let lhs = normalizedComparableText(seedJournal)
        let rhs = normalizedComparableText(candidateJournal)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func extractAuthors(fromMetadataText text: String) -> [AuthorName] {
        let cleaned = normalizeWhitespaceAndWidth(text)
            .replacingOccurrences(of: #"作者[:：]?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"第一作者[:：]?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\d\*\†\‡#]+"#, with: " ", options: .regularExpression)

        let lines = cleaned
            .components(separatedBy: "|")
            .flatMap { $0.components(separatedBy: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var names: [String] = []
        for line in lines {
            if looksLikeInstitutionName(line) || line.count > 40 { continue }
            let candidates = line
                .replacingOccurrences(of: #"[，,；;/]+"#, with: "|", options: .regularExpression)
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            let valid = candidates.filter(looksLikePersonalName(_:))
            if valid.count >= 1 {
                names.append(contentsOf: valid)
            }
        }

        if names.isEmpty {
            let fallbackSegments = cleaned
                .replacingOccurrences(of: #"[，,；;/]+"#, with: "|", options: .regularExpression)
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            names = fallbackSegments.filter(looksLikePersonalName(_:))
        }

        var seen = Set<String>()
        return names
            .filter { seen.insert($0).inserted }
            .map { name in
                if containsHanCharacters(name) {
                    return AuthorName(given: "", family: name)
                }
                return AuthorName.parse(name)
            }
    }

    private static func extractJournal(fromMetadataText text: String) -> String? {
        let normalized = normalizeWhitespaceAndWidth(text)
        let journalSuffixPattern = #"(?:学报|杂志|期刊|科学|工程|大学|学院|报|论坛|学刊|研究|进展|通报|通讯|评论)"#
        let patterns = [
            #"来源[:：]?\s*([^\s\d|，,;；]{2,40}?\#(journalSuffixPattern))"#,
            #"([^\s\d|，,;；]{2,40}?\#(journalSuffixPattern))\s*(?:[|｜]\s*)?(?:19\d{2}|20\d{2})"#
        ]

        for pattern in patterns {
            if let match = firstMatch(in: normalized, pattern: pattern)?.swiftlib_nilIfBlank,
               let journal = cleanJournalCandidate(match, suffixPattern: journalSuffixPattern) {
                return journal
            }
        }

        let segments = normalized
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for segment in segments {
            if let journal = cleanJournalCandidate(segment, suffixPattern: journalSuffixPattern) {
                return journal
            }
        }
        return nil
    }

    private static func cleanJournalCandidate(_ text: String, suffixPattern: String) -> String? {
        let normalized = normalizeWhitespaceAndWidth(text)
        let pattern = #"([^\s\d|，,;；]{2,40}?\#(suffixPattern))"#
        let matches = allMatches(in: normalized, pattern: pattern)
        guard let last = matches.last else { return nil }
        return normalizeJournalName(last)
    }

    private static func cleanCandidateTitle(_ title: String) -> String {
        normalizeWhitespaceAndWidth(title)
            .replacingOccurrences(of: #"[①②③④⑤⑥⑦⑧⑨⑩\*\†\‡]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
