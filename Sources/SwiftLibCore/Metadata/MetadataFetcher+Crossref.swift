import Foundation

extension MetadataFetcher {
    // MARK: - DOI → Crossref API (adapter-driven)

    /// Fetch metadata from DOI via Crossref REST API.
    /// URL template, field paths, JATS abstract cleanup, and date-part
    /// extraction all live in `Resources/adapters/crossref-work.json`.
    public static func fetchFromDOI(_ doi: String, forceRefresh: Bool = false) async throws -> Reference {
        let normalized = normalizedDOI(doi)
        let cacheKey = "doi:\(normalized)"
        // Under forceRefresh the user explicitly asked for a fresh scrape
        // (e.g. the "Refresh Metadata" UI action); skip BOTH cache tiers.
        // storeInBothCaches at the end still writes the new value, so the
        // cache ends up updated, not invalidated.
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            guard let adapter = SiteAdapterRegistry.shared.adapter(id: "crossref-work"),
                  let route = adapter.routes["byDoi"] else {
                throw FetchError.unsupported("crossref-work adapter missing")
            }
            let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["doi": normalized])
            guard let url = URL(string: urlString) else {
                throw FetchError.invalidURL
            }

            var ref = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                try parseCrossrefResponse(data, doi: normalized)
            }

            // Crossref often lacks abstract (Nature, etc.) — fetch from S2 and OpenAlex in parallel, take first success.
            if ref.abstract == nil || ref.abstract?.isEmpty == true {
                async let s2Abstract = try? fetchAbstractFromSemanticScholar(doi: normalized)
                async let oaAbstract = try? fetchAbstractFromOpenAlex(doi: normalized)

                let (s2, oa) = await (s2Abstract, oaAbstract)
                // Prefer Semantic Scholar (tends to be higher quality for STEM).
                ref.abstract = (s2 ?? nil) ?? (oa ?? nil)
            }

            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    /// Fetch DOI metadata through doi.org content negotiation as a fallback to
    /// Crossref's `/works/{doi}` API. The response is CSL JSON.
    public static func fetchFromDOIContentNegotiation(_ doi: String, forceRefresh: Bool = false) async throws -> Reference {
        let normalized = normalizedDOI(doi)
        let cacheKey = "doi-json:\(normalized)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let allowed = CharacterSet.urlPathAllowed
            let encodedDOI = normalized.addingPercentEncoding(withAllowedCharacters: allowed) ?? normalized
            guard let url = URL(string: "https://doi.org/\(encodedDOI)") else {
                throw FetchError.invalidURL
            }

            let ref = try await performRequest(
                url: url,
                timeout: 15,
                extraHeaders: [
                    "Accept": "application/vnd.citationstyles.csl+json"
                ]
            ) { data in
                try parseCSLJSONResponse(data, doi: normalized)
            }

            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    // MARK: - CrossRef Parser (adapter-driven)

    /// Parses a CrossRef `/works/{doi}` JSON body into a `Reference`.
    /// All schema knowledge lives in `crossref-work.byDoi` adapter;
    /// this function is a thin dispatcher + domain mapper.
    /// Kept as a named function so `fetchFromDOI` and existing unit tests
    /// (fixture-fed) can keep calling it.
    static func parseCrossrefResponse(_ data: Data, doi: String) throws -> Reference {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "crossref-work"),
              let route = adapter.routes["byDoi"] else {
            throw FetchError.parseError
        }
        let rows = (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
        guard let row = rows.first else { throw FetchError.parseError }
        return referenceFromCrossRefRow(row, doi: doi)
    }

    static func parseCSLJSONResponse(_ data: Data, doi: String) throws -> Reference {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.parseError
        }

        func stringValue(_ key: String) -> String? {
            if let value = json[key] as? String {
                return value.swiftlib_nilIfBlank
            }
            if let values = json[key] as? [String] {
                return values.first?.swiftlib_nilIfBlank
            }
            return nil
        }

        let authors: [AuthorName] = {
            guard let rawAuthors = json["author"] as? [[String: Any]] else { return [] }
            return rawAuthors.compactMap { raw -> AuthorName? in
                if let literal = (raw["literal"] as? String)?.swiftlib_nilIfBlank
                    ?? (raw["name"] as? String)?.swiftlib_nilIfBlank {
                    return AuthorName.parse(literal)
                }
                let given = (raw["given"] as? String)?.swiftlib_nilIfBlank ?? ""
                let family = (raw["family"] as? String)?.swiftlib_nilIfBlank ?? ""
                guard !given.isEmpty || !family.isEmpty else { return nil }
                return AuthorName(given: given, family: family)
            }
        }()

        let year: Int? = {
            let dateFields = ["issued", "published-print", "published-online", "created"]
            for field in dateFields {
                guard let date = json[field] as? [String: Any],
                      let parts = date["date-parts"] as? [[Any]],
                      let firstPart = parts.first,
                      let rawYear = firstPart.first else { continue }
                if let year = rawYear as? Int { return year }
                if let yearString = rawYear as? String, let year = Int(yearString) { return year }
            }
            return nil
        }()

        let referenceType: ReferenceType = {
            switch stringValue("type") {
            case "article-journal", "journal-article": return .journalArticle
            case "article-magazine": return .magazineArticle
            case "article-newspaper": return .newspaperArticle
            case "book", "monograph": return .book
            case "chapter", "book-chapter": return .bookSection
            case "paper-conference", "proceedings-article": return .conferencePaper
            case "thesis", "dissertation": return .thesis
            case "report": return .report
            case "dataset": return .dataset
            case "standard": return .standard
            case "webpage", "web": return .webpage
            default: return .journalArticle
            }
        }()

        return Reference(
            title: stringValue("title") ?? "Untitled",
            authors: authors,
            year: year,
            journal: stringValue("container-title"),
            volume: stringValue("volume"),
            issue: stringValue("issue"),
            pages: stringValue("page") ?? stringValue("pages"),
            doi: stringValue("DOI") ?? doi,
            url: stringValue("URL"),
            abstract: stringValue("abstract"),
            referenceType: referenceType,
            metadataSource: .crossRef,
            publisher: stringValue("publisher"),
            issn: stringValue("ISSN"),
            language: stringValue("language")
        )
    }

    /// Translate a CrossRef adapter row to `Reference`. Applies the CJK-swap
    /// heuristic on a per-author basis and re-interleaves organization authors
    /// (which come via the `author[*].name` path) with person authors (via
    /// `author[*].given` / `author[*].family`).
    /// Exposed internally so tests can feed synthetic rows directly.
    static func referenceFromCrossRefRow(_ row: [String: String], doi: String) -> Reference {
        let title: String = {
            if let full = row["titleWithSubtitle"]?.swiftlib_nilIfBlank { return full }
            return row["title"]?.swiftlib_nilIfBlank ?? "Untitled"
        }()

        // First non-empty date wins: published-print → online → issued → created.
        let year: Int? = [
            row["yearPrint"], row["yearOnline"], row["yearIssued"], row["yearCreated"]
        ]
        .compactMap { $0?.swiftlib_nilIfBlank }
        .first
        .flatMap { Int($0.prefix(4)) }

        let referenceType: ReferenceType = {
            switch row["type"] {
            case "journal-article": return .journalArticle
            case "newspaper-article": return .newspaperArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "report", "report-component": return .report
            case "standard": return .standard
            case "posted-content": return .preprint
            case .none: return .journalArticle
            default: return .other
            }
        }()

        return Reference(
            title: title,
            authors: buildCrossRefAuthors(row: row),
            year: year,
            journal: row["journal"]?.swiftlib_nilIfBlank,
            volume: row["volume"]?.swiftlib_nilIfBlank,
            issue: row["issue"]?.swiftlib_nilIfBlank,
            pages: row["pages"]?.swiftlib_nilIfBlank,
            doi: doi,
            url: row["url"]?.swiftlib_nilIfBlank,
            abstract: row["abstract"]?.swiftlib_nilIfBlank,
            referenceType: referenceType
        )
    }

    private static func buildCrossRefAuthors(row: [String: String]) -> [AuthorName] {
        var authors: [AuthorName] = []

        // Organization-style authors (only have `name`).
        let orgNames = (row["authorsName"] ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for org in orgNames {
            authors.append(AuthorName.parse(org))
        }

        // Person-style authors (have parallel `given` + `family` arrays).
        let givens = (row["authorsGiven"] ?? "").components(separatedBy: "||")
        let families = (row["authorsFamily"] ?? "").components(separatedBy: "||")
        let personCount = max(givens.count, families.count)
        for i in 0..<personCount {
            let given = (i < givens.count ? givens[i] : "").trimmingCharacters(in: .whitespaces)
            let family = (i < families.count ? families[i] : "").trimmingCharacters(in: .whitespaces)
            guard !family.isEmpty || !given.isEmpty else { continue }
            if looksLikeCJKName(given: given, family: family) {
                // CrossRef often swaps given/family for romanized CJK names; correct that.
                authors.append(AuthorName(given: family, family: given))
            } else {
                authors.append(AuthorName(given: given, family: family))
            }
        }
        return authors
    }

    // MARK: - CJK Author Name Correction

    /// Detect when CrossRef has swapped given/family for a CJK author name.
    /// CrossRef often returns `{"given":"Wu","family":"Haoyun"}` for Chinese authors
    /// when the correct mapping is `given:"Haoyun", family:"Wu"` (family name is the
    /// shorter, single-character-like segment for Chinese names romanized).
    private static func looksLikeCJKName(given: String, family: String) -> Bool {
        let g = given.trimmingCharacters(in: .whitespaces)
        let f = family.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, !f.isEmpty else { return false }
        let bothAscii = g.allSatisfy { $0.isASCII } && f.allSatisfy { $0.isASCII }
        guard bothAscii else { return false }
        let gWords = g.components(separatedBy: " ").filter { !$0.isEmpty }
        return gWords.count == 1 && g.count <= 3 && f.count > g.count
    }

}
