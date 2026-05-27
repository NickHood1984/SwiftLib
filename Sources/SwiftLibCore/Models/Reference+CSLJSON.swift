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
        authors.map { name in
            var o: [String: String] = ["family": name.family]
            if !name.given.isEmpty { o["given"] = name.given }
            return o
        }
    }

    /// CSL-JSON item for citeproc-js / citeproc-rs (`id` must be string).
    /// Conforms to CSL-JSON schema: https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
    public func cslJSONObject() -> [String: Any] {
        guard let nid = id else {
            return [:]
        }
        var obj: [String: Any] = [
            "id": String(nid),
            "type": referenceType.cslType,
            "title": title,
        ]

        // --- Name variables ---
        let creators = Self.parseAuthorsField(authors)
        if !creators.isEmpty {
            obj["author"] = creators
        }

        let editorNames = parsedEditors
        if !editorNames.isEmpty {
            obj["editor"] = Self.parseAuthorsField(editorNames)
        }

        let translatorNames = parsedTranslators
        if !translatorNames.isEmpty {
            obj["translator"] = Self.parseAuthorsField(translatorNames)
        }

        // --- Date variables ---
        if let y = year {
            var dateParts: [Any] = [y]
            if let m = issuedMonth, (1...12).contains(m) {
                dateParts.append(m)
                if let d = issuedDay, (1...31).contains(d) {
                    dateParts.append(d)
                }
            }
            obj["issued"] = ["date-parts": [dateParts]]
        }

        if let ad = accessedDate, !ad.isEmpty {
            // Try to parse ISO 8601 date string → CSL date-parts
            if let parsed = Self.parseDateString(ad) {
                obj["accessed"] = parsed
            } else {
                obj["accessed"] = ["raw": ad]
            }
        }

        // --- Standard variables ---
        if let j = journal, !j.isEmpty {
            obj["container-title"] = j
        }
        if let v = volume, !v.isEmpty {
            obj["volume"] = v
        }
        if let i = issue, !i.isEmpty {
            obj["issue"] = i
        }
        if let p = pages, !p.isEmpty {
            obj["page"] = p
        }
        if let d = doi, !d.isEmpty {
            obj["DOI"] = d
        }
        if let u = cslExportURL {
            obj["URL"] = u
        }

        // P0 fields
        if let pub = publisher, !pub.isEmpty {
            obj["publisher"] = pub
        } else if referenceType == .thesis, let institution, !institution.isEmpty {
            obj["publisher"] = institution
        }
        if let place = publisherPlace, !place.isEmpty {
            obj["publisher-place"] = place
        }
        if let ed = edition, !ed.isEmpty {
            obj["edition"] = ed
        }
        if let isbnVal = isbn, !isbnVal.isEmpty {
            obj["ISBN"] = isbnVal
        }
        if let issnVal = issn, !issnVal.isEmpty {
            obj["ISSN"] = issnVal
        }

        // P1 fields
        if let et = eventTitle, !et.isEmpty {
            obj["event-title"] = et
        }
        if let ep = eventPlace, !ep.isEmpty {
            obj["event-place"] = ep
        }
        if let g = genre, !g.isEmpty {
            obj["genre"] = g
        }
        if referenceType == .thesis, let institution, !institution.isEmpty {
            obj["archive"] = institution
        }
        if let n = number, !n.isEmpty {
            obj["number"] = n
        }
        if let ct = collectionTitle, !ct.isEmpty {
            obj["collection-title"] = ct
        }
        if let np = numberOfPages, !np.isEmpty {
            obj["number-of-pages"] = np
        }

        // P2 fields
        // If the user supplied a language, normalize it to a CSL-recognized tag.
        // Otherwise auto-detect from title (CJK → zh, mostly Latin → en) so that
        // multilingual styles (e.g. GB/T 7714) can switch "等" / "et al." correctly.
        if let lang = language, !lang.isEmpty {
            obj["language"] = Self.normalizeCSLLanguageTag(lang) ?? lang
        } else if let auto = Self.autoDetectCSLLanguage(title: title) {
            obj["language"] = auto
        }
        if let pm = pmid, !pm.isEmpty {
            obj["PMID"] = pm
        }
        if let pmc = pmcid, !pmc.isEmpty {
            obj["PMCID"] = pmc
        }

        // Webpage-specific: siteName → container-title (if journal not set)
        if referenceType == .webpage, obj["container-title"] == nil,
           let sn = siteName, !sn.isEmpty {
            obj["container-title"] = sn
        }

        return obj
    }

    private var cslExportURL: String? {
        guard referenceType == .webpage else { return nil }
        return url?.swiftlib_nilIfBlank
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
        guard let nid = id else { return CSLItem(id: "unsaved", type: referenceType.cslType) }

        // --- Authors / editors / translators ---
        let cslAuthors: [CSLName]? = authors.isEmpty ? nil : authors.map { CSLName.person(given: $0.given, family: $0.family) }
        let cslEditors: [CSLName]? = {
            let eds = parsedEditors
            return eds.isEmpty ? nil : eds.map { CSLName.person(given: $0.given, family: $0.family) }
        }()
        let cslTranslators: [CSLName]? = {
            let trans = parsedTranslators
            return trans.isEmpty ? nil : trans.map { CSLName.person(given: $0.given, family: $0.family) }
        }()

        // --- Dates ---
        let issuedDate: CSLDate? = {
            guard let y = year else { return nil }
            if let m = issuedMonth, (1...12).contains(m) {
                if let d = issuedDay, (1...31).contains(d) { return .full(y, m, d) }
                return .yearMonth(y, m)
            }
            return .year(y)
        }()

        let accessedCSLDate: CSLDate? = accessedDate.flatMap { CSLDate.from(isoString: $0) }

        // --- DOI: strip https://doi.org/ prefix so citeproc-js gets a bare DOI ---
        let cleanDOI: String? = doi.flatMap { DOIIdentifier($0)?.cslString } ?? doi?.swiftlib_nilIfBlank

        // --- URL: only for webpage type ---
        let cslURL: String? = referenceType == .webpage ? url?.swiftlib_nilIfBlank : nil

        // --- Language: normalise or auto-detect ---
        let lang: String? = {
            if let userLang = language?.swiftlib_nilIfBlank {
                return Self.normalizeCSLLanguageTag(userLang) ?? userLang
            }
            return Self.autoDetectCSLLanguage(title: title)
        }()

        // --- Note: carry secondary identifiers ---
        var noteParts: [String] = []
        if let arXivURL = url, arXivURL.lowercased().contains("arxiv.org"),
           let arxivID = ArxivIDIdentifier(arXivURL) {
            noteParts.append(arxivID.cslNote)
        }
        if let pm = pmid?.swiftlib_nilIfBlank, cleanDOI == nil {
            noteParts.append("PMID:\(pm)")
        }
        if let pmc = pmcid?.swiftlib_nilIfBlank {
            noteParts.append("PMCID:\(pmc)")
        }
        let note: String? = noteParts.isEmpty ? nil : noteParts.joined(separator: "; ")

        // --- publisher: thesis uses institution ---
        let pub: String? = publisher?.swiftlib_nilIfBlank ?? (
            referenceType == .thesis ? institution?.swiftlib_nilIfBlank : nil
        )

        // --- Webpage container-title uses siteName ---
        let containerTitle: String? = journal?.swiftlib_nilIfBlank ?? (
            referenceType == .webpage ? siteName?.swiftlib_nilIfBlank : nil
        )

        return CSLItem(
            id: String(nid),
            type: referenceType.cslType,
            title: title.swiftlib_nilIfBlank,
            containerTitle: containerTitle,
            collectionTitle: collectionTitle?.swiftlib_nilIfBlank,
            author: cslAuthors,
            editor: cslEditors,
            translator: cslTranslators,
            issued: issuedDate,
            accessed: accessedCSLDate,
            volume: volume?.swiftlib_nilIfBlank,
            issue: issue?.swiftlib_nilIfBlank,
            page: pages?.swiftlib_nilIfBlank,
            edition: edition?.swiftlib_nilIfBlank,
            number: number?.swiftlib_nilIfBlank,
            numberOfPages: numberOfPages?.swiftlib_nilIfBlank,
            publisher: pub,
            publisherPlace: publisherPlace?.swiftlib_nilIfBlank,
            eventTitle: eventTitle?.swiftlib_nilIfBlank,
            eventPlace: eventPlace?.swiftlib_nilIfBlank,
            genre: genre?.swiftlib_nilIfBlank,
            abstract: abstract?.swiftlib_nilIfBlank,
            language: lang,
            DOI: cleanDOI,
            URL: cslURL,
            ISBN: isbn?.swiftlib_nilIfBlank,
            ISSN: issn?.swiftlib_nilIfBlank,
            PMID: pmid?.swiftlib_nilIfBlank,
            PMCID: pmcid?.swiftlib_nilIfBlank,
            note: note
        )
    }

    // MARK: - Date parsing helper

    /// Parse an ISO 8601 date string (e.g. "2024-03-15") into CSL date-parts format
    private static func parseDateString(_ dateStr: String) -> [String: Any]? {
        let parts = dateStr.split(separator: "-").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return ["date-parts": [parts]]
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
