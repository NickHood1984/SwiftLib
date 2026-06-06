import Foundation

extension ReferenceType {
    /// CSL-JSON `type` values (https://docs.citationstyles.org/en/stable/specification.html#type-map)
    public var cslType: String {
        switch self {
        case .journalArticle: return "article-journal"
        case .magazineArticle: return "article-magazine"
        case .newspaperArticle: return "article-newspaper"
        case .preprint: return "article"
        case .book: return "book"
        case .bookSection: return "chapter"
        case .conferencePaper: return "paper-conference"
        case .thesis: return "thesis"
        case .dataset: return "dataset"
        case .software: return "software"
        case .standard: return "standard"
        case .manuscript: return "manuscript"
        case .interview: return "interview"
        case .presentation: return "speech"
        case .blogPost: return "post-weblog"
        case .forumPost: return "post"
        case .legalCase: return "legal_case"
        case .legislation: return "legislation"
        case .webpage: return "webpage"
        case .report: return "report"
        case .patent: return "patent"
        case .other: return "article"
        }
    }
}

extension Reference {
    public static func parseAuthorsField(_ authors: [AuthorName]) -> [[String: String]] {
        AuthorName.normalizedForCitation(authors).map { name in
            var o: [String: String] = ["family": name.family]
            if !name.given.isEmpty { o["given"] = name.given }
            return o
        }
    }

    /// CSL-JSON item for citeproc-js / citeproc-rs (`id` must be string).
    /// Conforms to CSL-JSON schema: https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
    public func cslJSONObject() -> [String: Any] {
        guard id != nil else { return [:] }
        return CSLExportService.cslJSONObject(for: self)
    }

    // MARK: - Typed CSLItem bridge

    /// Convert this reference to a typed `CSLItem` for safe citeproc-js interop.
    ///
    /// Unlike `cslJSONObject()` which returns `[String: Any]`, this method
    /// uses Swift Codable for serialisation, which prevents silent field erasure
    /// and makes the mapping auditable via `CSLItem.CodingKeys`.
    ///
    /// Improvements over `cslJSONObject()`:
    ///   - DOI is stripped of any `https://doi.org/` prefix before being passed
    ///     to citeproc-js (the DOI spec says the identifier is the bare suffix).
    ///   - Author `literal` is used for institutional/corporate names that
    ///     should not be split into given/family parts.
    ///   - `note` field carries secondary identifiers (arXiv, PMID) when no
    ///     dedicated CSL variable exists, following Pandoc / Zotero convention.
    public func toCSLItem() -> CSLItem {
        CSLExportService.cslItem(for: self)
    }

    // MARK: - Language helpers

    /// Best-effort normalization of a user-supplied language string into a BCP-47 tag
    /// that CSL locales understand (e.g. "中文" / "Chinese" / "zh-CN" → "zh-CN").
    static func normalizeCSLLanguageTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        // Already looks like a BCP-47 tag (e.g. "en", "en-US", "zh-CN")
        if let regex = try? NSRegularExpression(pattern: #"^[a-z]{2,3}(-[a-z0-9]{2,8})*$"#),
           regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            // Canonicalize the region part to upper-case (zh-cn → zh-CN)
            let parts = lower.split(separator: "-")
            if parts.count >= 2 {
                return ([parts[0].lowercased()] + parts.dropFirst().map { $0.uppercased() }).joined(separator: "-")
            }
            return lower
        }
        // Common natural-language synonyms
        let chineseAliases: Set<String> = ["chinese", "中文", "汉语", "中文（简体）", "简体中文", "zh_cn", "zh-cn"]
        let englishAliases: Set<String> = ["english", "英文", "英语", "en_us", "en-us"]
        if chineseAliases.contains(lower) { return "zh-CN" }
        if englishAliases.contains(lower) { return "en-US" }
        return nil
    }

    /// Heuristic: detect "en" vs "zh" from title characters.
    /// Returns nil if the title is empty or ambiguous.
    static func autoDetectCSLLanguage(title: String) -> String? {
        let stripped = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        var cjkCount = 0
        var latinCount = 0
        for scalar in stripped.unicodeScalars {
            let v = scalar.value
            // CJK Unified Ideographs + extensions + Hiragana/Katakana/Hangul
            if (0x4E00...0x9FFF).contains(v) ||
               (0x3400...0x4DBF).contains(v) ||
               (0x20000...0x2A6DF).contains(v) ||
               (0x3040...0x30FF).contains(v) ||
               (0xAC00...0xD7AF).contains(v) {
                cjkCount += 1
            } else if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) {
                latinCount += 1
            }
        }
        if cjkCount == 0 && latinCount == 0 { return nil }
        return cjkCount > 0 ? "zh-CN" : "en-US"
    }
}

// MARK: - CSL Field Diagnostics

public enum CSLFieldSeverity: Sendable {
    /// Absence causes blank or broken output in virtually every citation style.
    case critical
    /// Absence makes output incomplete in notable styles (IEEE, Vancouver, GB/T 7714, etc.).
    case recommended
}

public struct CSLFieldIssue: Sendable {
    public let fieldKey: String
    public let displayName: String
    public let severity: CSLFieldSeverity
}

public enum CSLCompleteness: Sendable {
    case complete       // no issues
    case incomplete     // only recommended fields missing
    case critical       // at least one critical field missing
}

extension Reference {
    /// Field-level issues for CSL rendering, ordered critical-first.
    public var cslFieldIssues: [CSLFieldIssue] {
        var issues: [CSLFieldIssue] = []

        // Title is non-optional but can be blank
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(fieldKey: "title", displayName: "标题", severity: .critical))
        }
        // Year is needed by every style
        if year == nil {
            issues.append(.init(fieldKey: "issued", displayName: "出版年份", severity: .critical))
        }

        switch referenceType {
        case .journalArticle, .magazineArticle, .newspaperArticle:
            if authors.isEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .critical))
            }
            if journal.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "container-title", displayName: "期刊名", severity: .recommended))
            }
            if volume.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "volume", displayName: "卷号", severity: .recommended))
            }
            if pages.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "page", displayName: "页码", severity: .recommended))
            }

        case .book, .bookSection:
            if authors.isEmpty && editors.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "author", displayName: "作者/编者", severity: .critical))
            }
            if publisher.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "publisher", displayName: "出版社", severity: .critical))
            }
            if publisherPlace.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "publisher-place", displayName: "出版地", severity: .recommended))
            }

        case .thesis:
            if authors.isEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .critical))
            }
            if institution.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "publisher", displayName: "授予单位", severity: .critical))
            }
            if genre.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "genre", displayName: "学位类型", severity: .recommended))
            }

        case .conferencePaper:
            if authors.isEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .critical))
            }
            if eventTitle.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "event-title", displayName: "会议名称", severity: .recommended))
            }
            if pages.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "page", displayName: "页码", severity: .recommended))
            }

        case .report:
            if authors.isEmpty && institution.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "author", displayName: "作者/机构", severity: .critical))
            }
            if number.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "number", displayName: "报告编号", severity: .recommended))
            }

        case .patent:
            if authors.isEmpty {
                issues.append(.init(fieldKey: "author", displayName: "发明人", severity: .critical))
            }
            if number.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "number", displayName: "专利号", severity: .recommended))
            }

        case .standard:
            if number.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "number", displayName: "标准编号", severity: .recommended))
            }

        case .webpage, .blogPost, .forumPost:
            if authors.isEmpty && siteName.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "author", displayName: "作者/网站名", severity: .recommended))
            }
            if url.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "URL", displayName: "网址", severity: .recommended))
            }
            if accessedDate.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "accessed", displayName: "访问日期", severity: .recommended))
            }

        case .preprint:
            if authors.isEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .critical))
            }
            if journal.swiftlib_nilIfBlank == nil {
                issues.append(.init(fieldKey: "container-title", displayName: "预印本平台", severity: .recommended))
            }

        default:
            if authors.isEmpty {
                issues.append(.init(fieldKey: "author", displayName: "作者", severity: .recommended))
            }
        }

        return issues.sorted { $0.severity == .critical && $1.severity != .critical }
    }

    public var cslCompleteness: CSLCompleteness {
        let issues = cslFieldIssues
        if issues.isEmpty { return .complete }
        if issues.contains(where: { $0.severity == .critical }) { return .critical }
        return .incomplete
    }
}
