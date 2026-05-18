import Foundation

extension MetadataResolution {
    public static func parseVolumeIssuePages(from text: String) -> (volume: String?, issue: String?, pages: String?) {
        let normalized = normalizeWhitespaceAndWidth(text)

        let volume = firstMatch(in: normalized, pattern: #"(?:第?\s*([0-9]{1,4})\s*卷|vol\.?\s*([0-9]{1,4}))"#)
        let issue = firstMatch(in: normalized, pattern: #"(?:第?\s*([0-9]{1,4})\s*期|no\.?\s*([0-9]{1,4}))"#)
        let pagePattern = #"(?:页码|页码范围|pages?)\s*[:：]?\s*([0-9]{1,4}\s*[-–—]\s*[0-9]{1,4}|[0-9]{1,4})|([0-9]{1,4}\s*[-–—]\s*[0-9]{1,4})"#
        let pages = firstMatch(in: normalized, pattern: pagePattern)?
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        return (volume?.swiftlib_nilIfBlank, issue?.swiftlib_nilIfBlank, pages?.swiftlib_nilIfBlank)
    }

    public static func cleanPDFSeedFilename(_ fileName: String) -> String {
        var text = fileName
        text = normalizeWhitespaceAndWidth(text)
        text = text.replacingOccurrences(of: #"\.[A-Za-z0-9]+$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[_\s]*(?:CNKI|中国知网|知网下载|CAJViewer|CAJ|pdf|PDF)$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?:\(|（)\d+(?:\)|）)$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*-\s*\d+$"#, with: "", options: .regularExpression)
        // 处理知网文件名截断特征（参考 Jasminum pattern.ts 的处理逻辑）
        text = text.replacingOccurrences(of: "_省略_", with: " ")
        text = text.replacingOccurrences(of: #"\.{3,}$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\.ashx$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        let result = text.trimmingCharacters(in: CharacterSet(charactersIn: " _-—–"))
        if result != fileName {
            metadataLog.debug("📥 [cleanFilename] 原始: \(fileName, privacy: .public) → 清洗后: \(result, privacy: .public)")
        }
        return result
    }

    public static func parsePDFFileNameSeed(_ fileName: String) -> (title: String?, firstAuthor: String?) {
        let separators = ["_", "——", "—", " - ", "-"]
        for separator in separators {
            let parts = fileName.components(separatedBy: separator).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let titleCandidate = parts[0]
            let authorCandidate = parts[1]
            if looksLikeLikelyTitle(titleCandidate), let author = extractLikelyAuthorName(from: authorCandidate) {
                return (titleCandidate, author)
            }
        }
        if looksLikeLikelyTitle(fileName) {
            metadataLog.debug("📝 [parseFilename] 无分隔符降级: title=\(fileName, privacy: .public) author=nil")
            return (fileName, nil)
        }
        metadataLog.debug("📝 [parseFilename] 解析失败，无标题和作者")
        return (nil, nil)
    }

    public static func extractLikelyAuthorName(from text: String) -> String? {
        let normalized = normalizeWhitespaceAndWidth(text)
        let stripped = normalized
            .replacingOccurrences(of: #"作者[:：]?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\d\*\†\‡#]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates = stripped
            .replacingOccurrences(of: #"[，,；;/\s]+"#, with: "|", options: .regularExpression)
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        for candidate in candidates where looksLikePersonalName(candidate) {
            // 处理作者名末尾的"等"字（参考 Jasminum 的处理逻辑，保留长度保护）
            if candidate.hasSuffix("等") && candidate.count > 2 {
                return String(candidate.dropLast())
            }
            return candidate
        }
        return nil
    }

    public static func containsHanCharacters(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    public static func normalizedComparableText(_ text: String) -> String {
        normalizeWhitespaceAndWidth(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^\p{Letter}\p{Number}]+"#, with: "", options: .regularExpression)
    }

    public static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        max(
            comparableTitleSimilarity(normalizedComparableText(lhs), normalizedComparableText(rhs)),
            comparableTitleSimilarity(normalizedTitleMatchingText(lhs), normalizedTitleMatchingText(rhs))
        )
    }

    public static func normalizeWhitespaceAndWidth(_ text: String) -> String {
        let folded = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return folded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractYear(fromMetadataText text: String) -> Int? {
        let pattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let match = firstMatch(in: text, pattern: pattern) else { return nil }
        return Int(match)
    }

    public static func normalizeJournalName(_ text: String?) -> String? {
        guard let text = text?.swiftlib_nilIfBlank else { return nil }
        let normalized = normalizeWhitespaceAndWidth(text)
            .replacingOccurrences(
                of: #"\s*[·•\.\,，;；:：|｜]+\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.swiftlib_nilIfBlank
    }

    public static func isSuspiciousExtractedTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.count > 160 { return true }
        if isLikelyAuthorLine(trimmed) { return true }
        if looksLikeInstitutionOnlyTitle(trimmed) { return true }
        let lowered = trimmed.lowercased()
        let badTokens = ["cnki", "中国知网", "network first", "doi", "journal", "issn", "online first"]
        if badTokens.contains(where: lowered.contains) { return true }
        let exactBadTitles = ["自动登录", "用户登录", "机构用户登录", "安全验证", "访问异常", "异常访问", "验证码"]
        if exactBadTitles.contains(trimmed) { return true }
        if trimmed.count <= 12 && (trimmed.contains("登录") || trimmed.contains("验证")) {
            return true
        }
        if lowered.hasPrefix("author") || lowered.hasPrefix("title") { return true }
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func looksLikeInstitutionOnlyTitle(_ text: String) -> Bool {
        let suffixes = ["实验室", "研究所", "研究院", "研究中心", "工程中心", "监测中心", "管理局",
                        "水文局", "编辑部", "出版社", "有限公司"]
        let hasSuffix = suffixes.contains(where: text.hasSuffix)
        guard hasSuffix else { return false }
        let keywords = ["大学", "学院", "学部", "研究所", "研究院", "实验室", "中心",
                        "医院", "管理局", "水文局", "编辑部", "出版社", "有限公司",
                        "university", "college", "institute", "laboratory", "center", "centre"]
        let lowered = text.lowercased()
        let matchCount = keywords.filter { lowered.contains($0) }.count
        return matchCount >= 2
    }

    public static func isLikelyAuthorLine(_ text: String) -> Bool {
        let normalized = normalizeWhitespaceAndWidth(text)
            .replacingOccurrences(
                of: #"[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]+$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if normalized.contains("摘要") || normalized.contains("关键词") || normalized.contains("基金资助") {
            return false
        }

        if normalized.range(
            of: #"([\p{Han}]{2,4}(?:·[\p{Han}]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let segments = normalized
            .replacingOccurrences(of: #"[，,；;、|\s]+"#, with: "\n", options: .regularExpression)
            .split(separator: "\n")
            .map { String($0) }
            .map {
                $0.replacingOccurrences(
                    of: #"[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]+$"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        if segments.count >= 2,
           segments.allSatisfy({
               $0.range(of: #"^[\p{Han}]{2,4}(?:·[\p{Han}]{1,6})?$"#, options: .regularExpression) != nil
                || $0.range(of: #"^[A-Za-z][A-Za-z .'\-]{1,60}$"#, options: .regularExpression) != nil
           }) {
            return true
        }

        let authorTokens = AuthorName.parseList(normalized)
        return authorTokens.count >= 3 && authorTokens.allSatisfy { !$0.family.isEmpty }
    }


    static func institutionalAuthorRatio(for authors: [AuthorName]) -> Double {
        guard !authors.isEmpty else { return 1 }
        let suspicious = authors.filter { looksLikeInstitutionName($0.displayName) }.count
        return Double(suspicious) / Double(authors.count)
    }

    static func looksLikeInstitutionName(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = [
            "university", "college", "institute", "laboratory", "department", "school", "center", "centre",
            "academy", "hospital", "state key", "research", "研究所", "大学", "学院", "实验室", "中心", "医院", "系", "部"
        ]
        return keywords.contains(where: lowered.contains)
    }


    private static func normalizedTitleMatchingText(_ text: String) -> String {
        normalizeWhitespaceAndWidth(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            // 移除中文书名号，避免影响相似度计算
            .replacingOccurrences(of: #"[《》〈〉「」【】]"#, with: "", options: .regularExpression)
            // 将副标题分隔符统一为空格，使含副标题的标题与不含副标题的文件名能正常匹配
            .replacingOccurrences(of: #"——|——|(?<=[\p{Han}\w])：(?=[\p{Han}\w])|(?<=[\p{Han}\w]):(?=[\p{Han}\w])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"^(?:(?:19|20)\d{2})(?:\s*[-—–~至到]+\s*(?:19|20)?\d{2})?年?"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[的其]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{Letter}\p{Number}]+"#, with: "", options: .regularExpression)
    }

    private static func comparableTitleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        }

        let lhsBigrams = Set(bigrams(in: lhs))
        let rhsBigrams = Set(bigrams(in: rhs))
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else { return 0 }
        let overlap = lhsBigrams.intersection(rhsBigrams).count
        return (2 * Double(overlap)) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func looksLikeLikelyTitle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 120 else { return false }
        if trimmed.range(of: #"^(?:doi|DOI|摘要|Abstract|关键词|Keywords)"#, options: .regularExpression) != nil { return false }
        return true
    }

    static func looksLikePersonalName(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: #"\([^)]*\)|（[^）]*）"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        if looksLikeInstitutionName(cleaned) { return false }
        if containsHanCharacters(cleaned) {
            return looksLikeChinesePersonalName(cleaned)
        }
        if looksLikeNonAuthorLatinToken(cleaned) { return false }
        let parts = cleaned.split(separator: " ")
        return parts.count >= 2 && parts.count <= 4 && cleaned.count <= 40
    }

    private static func looksLikeChinesePersonalName(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "•", with: "·")

        guard normalized.range(of: #"^[\p{Han}]{2,4}(?:·[\p{Han}]{1,6})?$"#, options: .regularExpression) != nil else {
            return false
        }
        if obviousNonAuthorHanToken(normalized) { return false }
        if normalized.contains("·") { return true }
        return hasLikelyChineseSurname(normalized)
    }


    static func obviousNonAuthorHanToken(_ text: String) -> Bool {
        if blockedHanAuthorTokens.contains(text) {
            return true
        }
        return blockedHanAuthorFragments.contains { text.contains($0) }
    }

    static func looksLikeNonAuthorLatinToken(_ text: String) -> Bool {
        let normalized = normalizedComparableText(text)
        guard !normalized.isEmpty else { return true }
        return blockedLatinAuthorTokens.contains(normalized)
    }

    private static func hasLikelyChineseSurname(_ text: String) -> Bool {
        if text.count >= 2 {
            let firstTwo = String(text.prefix(2))
            if compoundChineseSurnames.contains(firstTwo) {
                return true
            }
        }
        guard let first = text.first else { return false }
        return singleCharacterChineseSurnames.contains(first)
    }

    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }

        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { continue }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            for index in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: index), in: text) else { continue }
                let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
            return nil
        }
    }

    private static func bigrams(in text: String) -> [String] {
        let chars = Array(text)
        guard chars.count >= 2 else { return chars.map(String.init) }
        return (0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) }
    }

    private static let blockedHanAuthorTokens: Set<String> = [
        "作者", "期刊", "下载", "全文", "摘要", "关键词", "关键字", "来源", "单位", "机构",
        "基金", "项目", "通信", "通讯", "编辑", "收稿", "修回", "发表", "目录", "栏目",
        "被引", "引文", "篇名", "题名", "主题", "检索", "知网", "中国知网", "文献", "参考文献"
    ]

    private static let blockedHanAuthorFragments: [String] = [
        "下载", "期刊", "摘要", "关键词", "关键字", "全文", "机构", "单位", "作者简介",
        "通信作者", "通讯作者", "收稿日期", "基金项目", "参考文献", "引用格式", "扫码", "二维码"
    ]

    private static let blockedLatinAuthorTokens: Set<String> = [
        "download", "downloads", "journal", "journals", "abstract", "keywords", "keyword",
        "fulltext", "全文", "doi", "pdf", "html", "citation", "citations", "references"
    ]

    private static let compoundChineseSurnames: Set<String> = [
        "欧阳", "太史", "端木", "上官", "司马", "东方", "独孤", "南宫", "万俟", "闻人",
        "夏侯", "诸葛", "尉迟", "公羊", "赫连", "澹台", "皇甫", "宗政", "濮阳", "公冶",
        "太叔", "申屠", "公孙", "慕容", "仲孙", "钟离", "长孙", "宇文", "司徒", "鲜于",
        "司空", "闾丘", "子车", "亓官", "司寇", "巫马", "公西", "颛孙", "壤驷", "公良",
        "漆雕", "乐正", "宰父", "谷梁", "拓跋", "夹谷", "轩辕", "令狐", "段干", "百里",
        "呼延", "东郭", "南门", "羊舌", "微生", "梁丘", "左丘", "东门", "西门", "南荣", "第五"
    ]

    private static let singleCharacterChineseSurnames: Set<Character> = Set(
        "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳酆鲍史唐费廉岑薛雷贺倪汤滕殷罗毕郝邬安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹姚邵湛汪祁毛禹狄米贝明臧计伏成戴谈宋茅庞熊纪舒屈项祝董梁杜阮蓝闵席季麻强贾路娄危江童颜郭梅盛林钟徐邱骆高夏蔡田樊胡凌霍虞万支柯昝管卢莫经房裘缪干解应宗丁宣贲邓郁单杭洪包诸左石崔吉龚程嵇邢滑裴陆荣翁荀羊於惠甄曲家封芮羿储靳汲邴糜松井段富巫乌焦巴弓牧隗山谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘钭厉戎祖武符刘景詹束龙叶幸司韶郜黎蓟薄印宿白怀蒲台从鄂索咸籍赖卓蔺屠蒙池乔阴胥能苍双闻莘党翟谭贡劳逄姬申扶堵冉宰郦雍郤璩桑桂濮牛寿通边扈燕冀郏浦尚农温别庄晏柴瞿阎连习容向古易慎戈廖庾终暨居衡步都耿弘匡文寇广禄阙东欧殳沃利蔚越夔隆师巩厍聂晁勾敖融冷訾辛阚那简饶空曾沙养鞠须丰巢关蒯相查后荆红游竺权逯盖益桓公仉督岳帅缑亢况郈有琴归海晋楚闫法汝鄢涂钦哈墨"
    )
}
