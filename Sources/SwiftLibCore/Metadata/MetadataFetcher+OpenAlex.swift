import Foundation

extension MetadataFetcher {
    // MARK: - OpenAlex Enrichment

    /// Rich metadata returned by OpenAlex that supplements the core Reference fields.
    public struct OpenAlexEnrichment: Codable, Hashable, Sendable {
        public var keywords: [String]
        public var topics: [String]
        public var isOpenAccess: Bool
        public var oaUrl: String?
        public var citedByCount: Int
        public var fundingInfo: [String]
        public var referenceType: ReferenceType?
        public var openAlexId: String?
        public var abstract: String?
        public var reference: Reference?
    }

    /// Fetch rich enrichment data from OpenAlex by DOI.
    public static func enrichWithOpenAlex(doi: String) async -> OpenAlexEnrichment? {
        let normalized = normalizedDOI(doi)
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalized
        let urlString = "https://api.openalex.org/works/doi:\(encoded)?select=id,type,concepts,topics,open_access,cited_by_count,grants,abstract_inverted_index\(politeMailtoQuery)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw FetchError.parseError
                }
                return parseOpenAlexEnrichment(json)
            }
        } catch {
            log.debug("OpenAlex enrichment(doi=\(normalized, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Fetch rich enrichment data from OpenAlex by title search.
    public static func enrichWithOpenAlex(title: String) async -> OpenAlexEnrichment? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "https://api.openalex.org/works?search=\(encoded)&select=id,type,concepts,topics,open_access,cited_by_count,grants,abstract_inverted_index&per-page=1\(politeMailtoQuery)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let work = results.first else {
                    throw FetchError.notFound
                }
                return parseOpenAlexEnrichment(work)
            }
        } catch {
            return nil
        }
    }

    /// Parse OpenAlex work JSON into an enrichment struct.
    static func parseOpenAlexEnrichment(_ work: [String: Any]) -> OpenAlexEnrichment {
        let openAlexId = work["id"] as? String

        let keywords: [String] = {
            guard let concepts = work["concepts"] as? [[String: Any]] else { return [] }
            return concepts
                .sorted { ($0["score"] as? Double ?? 0) > ($1["score"] as? Double ?? 0) }
                .compactMap { $0["display_name"] as? String }
        }()

        let topics: [String] = {
            guard let topicList = work["topics"] as? [[String: Any]] else { return [] }
            return topicList.compactMap { $0["display_name"] as? String }
        }()

        let oa = work["open_access"] as? [String: Any]
        let isOpenAccess = oa?["is_oa"] as? Bool ?? false
        let oaUrl = oa?["oa_url"] as? String

        let citedByCount = work["cited_by_count"] as? Int ?? 0

        let fundingInfo: [String] = {
            guard let grants = work["grants"] as? [[String: Any]] else { return [] }
            return grants.compactMap { grant -> String? in
                let funder = grant["funder_display_name"] as? String
                let awardId = grant["award_id"] as? String
                guard let funder else { return nil }
                if let awardId, !awardId.isEmpty {
                    return "\(funder) (\(awardId))"
                }
                return funder
            }
        }()

        let referenceType: ReferenceType? = {
            switch work["type"] as? String {
            case "journal-article", "article": return .journalArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "preprint", "posted-content": return .preprint
            case "report": return .report
            case "dataset": return .dataset
            default: return nil
            }
        }()

        let abstract = reconstructAbstract(fromInvertedIndex: work["abstract_inverted_index"] as? [String: [Int]])

        return OpenAlexEnrichment(
            keywords: keywords,
            topics: topics,
            isOpenAccess: isOpenAccess,
            oaUrl: oaUrl,
            citedByCount: citedByCount,
            fundingInfo: fundingInfo,
            referenceType: referenceType,
            openAlexId: openAlexId,
            abstract: abstract
        )
    }

    /// Reconstruct a continuous abstract string from OpenAlex's inverted index format.
    /// Used by every OpenAlex parser that wants the abstract; centralized here.
    static func reconstructAbstract(fromInvertedIndex invertedIndex: [String: [Int]]?) -> String? {
        guard let invertedIndex else { return nil }
        var positions: [Int: String] = [:]
        for (word, indices) in invertedIndex {
            for idx in indices { positions[idx] = word }
        }
        guard !positions.isEmpty else { return nil }
        let abstract = positions.keys.sorted().compactMap { positions[$0] }.joined(separator: " ")
        return abstract.isEmpty ? nil : abstract
    }

    public static func fetchAbstractFromOpenAlex(doi: String) async throws -> String? {
        let normalized = normalizedDOI(doi)
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalized
        let urlString = "https://api.openalex.org/works/doi:\(encoded)?select=abstract_inverted_index\(politeMailtoQuery)"
        return try await fetchOpenAlexAbstract(urlString)
    }

    /// Fetch abstract from OpenAlex using Title fallback
    public static func fetchAbstractFromOpenAlex(title: String) async throws -> String? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "https://api.openalex.org/works?search=\(encoded)&select=abstract_inverted_index&per-page=1\(politeMailtoQuery)"
        return try await fetchOpenAlexAbstract(urlString, isSearch: true)
    }

    private static func fetchOpenAlexAbstract(_ urlString: String, isSearch: Bool = false) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            return try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil as String?
                }
                let workData: [String: Any]?
                if isSearch {
                    guard let results = json["results"] as? [[String: Any]], let first = results.first else {
                        return nil as String?
                    }
                    workData = first
                } else {
                    workData = json
                }
                return reconstructAbstract(fromInvertedIndex: workData?["abstract_inverted_index"] as? [String: [Int]])
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - OpenAlex Full Fetch (adapter-driven)

    /// Fetch Reference + OpenAlexEnrichment from OpenAlex by DOI.
    /// Goes through the `openalex-work.byDoi` adapter — URL, field paths, and
    /// abstract reconstruction are all declared in JSON and can be repaired
    /// without a Swift rebuild when OpenAlex evolves its schema.
    public static func fetchFullFromOpenAlex(doi: String) async -> (Reference, OpenAlexEnrichment)? {
        let normalized = normalizedDOI(doi)
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openalex-work"),
              let route = adapter.routes["byDoi"] else {
            log.warning("openalex-work adapter missing; OpenAlex DOI fetch disabled")
            return nil
        }
        let urlString = SiteAdapterRuntime.expandURL(
            route.url,
            context: ["doi": normalized, "mailto": contactEmail]
        )
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }
            guard let row = rows.first else { return nil }
            return referenceAndEnrichmentFromOpenAlexRow(row)
        } catch {
            return nil
        }
    }

    /// Fetch Reference + OpenAlexEnrichment from OpenAlex by title.
    /// Same adapter infrastructure; `byTitle` route. Gated by title similarity
    /// so we never accept a completely unrelated first result.
    public static func fetchFullFromOpenAlex(title: String, maxResults: Int = 5) async -> (Reference, OpenAlexEnrichment)? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openalex-work"),
              let route = adapter.routes["byTitle"] else {
            return nil
        }
        let urlString = SiteAdapterRuntime.expandURL(
            route.url,
            context: [
                "title": title,
                "perPage": String(maxResults),
                "mailto": contactEmail
            ]
        )
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }

            // Strong-match pass (similarity ≥ 0.80).
            for row in rows {
                let fetchedTitle = row["title"] ?? ""
                if MetadataResolution.titleSimilarity(title, fetchedTitle) >= 0.80 {
                    return referenceAndEnrichmentFromOpenAlexRow(row)
                }
            }
            // Weak-match fallback (≥ 0.55) for first result only.
            if let first = rows.first {
                let fetchedTitle = first["title"] ?? ""
                if MetadataResolution.titleSimilarity(title, fetchedTitle) >= 0.55 {
                    return referenceAndEnrichmentFromOpenAlexRow(first)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Translate an OpenAlex adapter row (`[String: String]`) to our domain
    /// types. Exposed internally so fixture-based tests can exercise the
    /// mapping without hitting the network.
    static func referenceAndEnrichmentFromOpenAlexRow(
        _ row: [String: String]
    ) -> (Reference, OpenAlexEnrichment) {
        let title = row["title"] ?? "Untitled"
        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parseRomanizedCJKAware(String($0)) }
        let year = row["year"].flatMap { Int($0.prefix(4)) }

        // Prefer the template-rendered "firstPage-lastPage" when both were
        // present; otherwise fall back to firstPage alone.
        let pages: String? = {
            if let both = row["pagesWhenBothPresent"]?.swiftlib_nilIfBlank { return both }
            return row["firstPage"]?.swiftlib_nilIfBlank
        }()

        let referenceType: ReferenceType = {
            switch row["type"] {
            case "journal-article", "article": return .journalArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "preprint", "posted-content": return .preprint
            case "report": return .report
            case "dataset": return .dataset
            default: return .journalArticle
            }
        }()

        let ref = Reference(
            title: title,
            authors: authors,
            year: year,
            journal: row["journal"]?.swiftlib_nilIfBlank,
            volume: row["volume"]?.swiftlib_nilIfBlank,
            issue: row["issue"]?.swiftlib_nilIfBlank,
            pages: pages,
            doi: row["doi"]?.swiftlib_nilIfBlank,
            abstract: row["abstract"]?.swiftlib_nilIfBlank,
            referenceType: referenceType,
            metadataSource: .openAlex
        )

        // Re-compose funding entries as "Funder (AwardID)" pairs when both sides are present.
        let funders = (row["grantFunders"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true).map(String.init)
        let awards = (row["grantAwards"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true).map(String.init)
        var fundingInfo: [String] = []
        for (i, funder) in funders.enumerated() {
            if i < awards.count, !awards[i].isEmpty {
                fundingInfo.append("\(funder) (\(awards[i]))")
            } else {
                fundingInfo.append(funder)
            }
        }

        let enrichment = OpenAlexEnrichment(
            keywords: (row["conceptNames"] ?? "")
                .split(separator: "|", omittingEmptySubsequences: true).map(String.init),
            topics: (row["topicNames"] ?? "")
                .split(separator: "|", omittingEmptySubsequences: true).map(String.init),
            isOpenAccess: row["isOpenAccess"] == "true",
            oaUrl: row["oaUrl"]?.swiftlib_nilIfBlank,
            citedByCount: row["citedByCount"].flatMap(Int.init) ?? 0,
            fundingInfo: fundingInfo,
            referenceType: referenceType,
            openAlexId: row["openAlexId"]?.swiftlib_nilIfBlank,
            abstract: row["abstract"]?.swiftlib_nilIfBlank
        )
        return (ref, enrichment)
    }

    /// Build a Reference from an OpenAlex work JSON object.
    static func buildReferenceFromOpenAlexWork(_ work: [String: Any]) -> Reference {
        let fetchedTitle = work["title"] as? String ?? "Untitled"
        let year = work["publication_year"] as? Int

        let authors: [AuthorName] = {
            guard let authorships = work["authorships"] as? [[String: Any]] else { return [] }
            return authorships.compactMap { authorship -> AuthorName? in
                guard let author = authorship["author"] as? [String: Any],
                      let name = author["display_name"] as? String else { return nil }
                return AuthorName.parseRomanizedCJKAware(name)
            }
        }()

        let doi: String? = {
            guard let raw = work["doi"] as? String else { return nil }
            if let range = raw.range(of: "doi.org/") {
                return String(raw[range.upperBound...])
            }
            return raw
        }()

        let journal: String? = {
            guard let location = work["primary_location"] as? [String: Any],
                  let source = location["source"] as? [String: Any] else { return nil }
            return source["display_name"] as? String
        }()

        let biblio = work["biblio"] as? [String: Any]
        let volume = biblio?["volume"] as? String
        let issue = biblio?["issue"] as? String
        let firstPage = biblio?["first_page"] as? String
        let lastPage = biblio?["last_page"] as? String
        let pages: String? = {
            guard let f = firstPage else { return nil }
            if let l = lastPage, l != f { return "\(f)-\(l)" }
            return f
        }()

        let abstract = reconstructAbstract(fromInvertedIndex: work["abstract_inverted_index"] as? [String: [Int]])

        let referenceType: ReferenceType = {
            switch work["type"] as? String {
            case "journal-article", "article": return .journalArticle
            case "book", "monograph", "edited-book": return .book
            case "book-chapter", "book-section": return .bookSection
            case "proceedings-article": return .conferencePaper
            case "dissertation": return .thesis
            case "preprint", "posted-content": return .preprint
            case "report": return .report
            default: return .journalArticle
            }
        }()

        return Reference(
            title: fetchedTitle,
            authors: authors,
            year: year,
            journal: journal,
            volume: volume,
            issue: issue,
            pages: pages,
            doi: doi,
            abstract: abstract,
            referenceType: referenceType,
            metadataSource: .openAlex
        )
    }

    // MARK: - OpenAlex Title Search (full metadata)

    /// Search OpenAlex by title and return a full Reference (for articles without identifiers).
    /// Gated by title similarity (≥0.80 strong, ≥0.55 weak fallback) so we never accept a
    /// completely unrelated first result.
    public static func fetchFromOpenAlexByTitle(_ title: String) async throws -> Reference? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "https://api.openalex.org/works?search=\(encoded)&select=id,doi,title,authorships,publication_year,primary_location,biblio,abstract_inverted_index,type&per-page=3\(politeMailtoQuery)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let results: [[String: Any]] = try await performRequest(url: url, timeout: 10) { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    throw FetchError.notFound
                }
                return results
            }

            for work in results {
                let fetchedTitle = work["title"] as? String ?? ""
                let score = MetadataResolution.titleSimilarity(title, fetchedTitle)
                if score >= 0.80 {
                    return buildReferenceFromOpenAlexWork(work)
                }
            }
            if let first = results.first {
                let score = MetadataResolution.titleSimilarity(title, first["title"] as? String ?? "")
                if score >= 0.55 {
                    return buildReferenceFromOpenAlexWork(first)
                }
            }
            return nil
        } catch FetchError.notFound {
            return nil
        }
    }

}
