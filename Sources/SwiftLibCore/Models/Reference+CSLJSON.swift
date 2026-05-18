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
