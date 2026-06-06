import Foundation

extension MetadataFetcher {
    // MARK: - Semantic Scholar

    /// Rich result from Semantic Scholar Graph API.
    public struct S2PaperResult: Sendable {
        public var paperId: String
        public var title: String
        public var abstract: String?
        public var tldr: String?
        public var year: Int?
        public var venue: String?
        public var journal: S2Journal?
        public var authors: [AuthorName]
        public var citationCount: Int
        public var influentialCitationCount: Int
        public var isOpenAccess: Bool
        public var openAccessPdfUrl: String?
        public var externalIds: S2ExternalIds?
        public var publicationDate: String?
    }

    public struct S2Journal: Sendable {
        public var name: String?
        public var volume: String?
        public var pages: String?
    }

    public struct S2ExternalIds: Sendable {
        public var doi: String?
        public var arxivId: String?
        public var pmid: String?
        public var pmcid: String?
    }

    /// Fetch full paper data from Semantic Scholar by DOI. Goes through the
    /// `semantic-scholar-paper.byDoi` adapter; returns nil on any transport or
    /// parse failure so callers can fall through to other sources.
    public static func fetchFromSemanticScholar(doi: String) async -> S2PaperResult? {
        let normalized = normalizedDOI(doi)
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "semantic-scholar-paper"),
              let route = adapter.routes["byDoi"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["doi": normalized])
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }
            guard let row = rows.first else { return nil }
            return s2PaperResultFromRow(row)
        } catch {
            log.debug("S2 fetch(doi=\(normalized, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Search Semantic Scholar by exact title match. Adapter route `byTitleMatch`.
    public static func searchSemanticScholar(title: String) async -> S2PaperResult? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "semantic-scholar-paper"),
              let route = adapter.routes["byTitleMatch"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["title": title])
        guard let url = URL(string: urlString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
            }
            guard let row = rows.first else { return nil }
            return s2PaperResultFromRow(row)
        } catch {
            return nil
        }
    }

    /// Translate an S2 adapter row to `S2PaperResult`. Exposed internally so
    /// fixture-based tests can exercise the mapping without hitting the network.
    static func s2PaperResultFromRow(_ row: [String: String]) -> S2PaperResult? {
        guard let paperId = row["paperId"]?.swiftlib_nilIfBlank,
              let title = row["title"]?.swiftlib_nilIfBlank else { return nil }

        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parseRomanizedCJKAware(String($0)) }

        let journal: S2Journal? = {
            let name = row["journalName"]?.swiftlib_nilIfBlank
            let volume = row["journalVolume"]?.swiftlib_nilIfBlank
            let pages = row["journalPages"]?.swiftlib_nilIfBlank
            if name == nil && volume == nil && pages == nil { return nil }
            return S2Journal(name: name, volume: volume, pages: pages)
        }()

        let externalIds: S2ExternalIds? = {
            let doi = row["doi"]?.swiftlib_nilIfBlank
            let arxiv = row["arxivId"]?.swiftlib_nilIfBlank
            let pmid = row["pmid"]?.swiftlib_nilIfBlank
            let pmcid = row["pmcid"]?.swiftlib_nilIfBlank
            if doi == nil && arxiv == nil && pmid == nil && pmcid == nil { return nil }
            return S2ExternalIds(doi: doi, arxivId: arxiv, pmid: pmid, pmcid: pmcid)
        }()

        return S2PaperResult(
            paperId: paperId,
            title: title,
            abstract: row["abstract"]?.swiftlib_nilIfBlank,
            tldr: row["tldr"]?.swiftlib_nilIfBlank,
            year: row["year"].flatMap(Int.init),
            venue: row["venue"]?.swiftlib_nilIfBlank,
            journal: journal,
            authors: authors,
            citationCount: row["citationCount"].flatMap(Int.init) ?? 0,
            influentialCitationCount: row["influentialCitationCount"].flatMap(Int.init) ?? 0,
            isOpenAccess: row["isOpenAccess"] == "true",
            openAccessPdfUrl: row["openAccessPdfUrl"]?.swiftlib_nilIfBlank,
            externalIds: externalIds,
            publicationDate: row["publicationDate"]?.swiftlib_nilIfBlank
        )
    }

    /// Convert S2PaperResult to Reference for merge purposes.
    public static func referenceFromS2(_ s2: S2PaperResult) -> Reference {
        let doi = s2.externalIds?.doi
        let pages: String? = s2.journal?.pages
        return Reference(
            title: s2.title,
            authors: s2.authors,
            year: s2.year,
            journal: s2.journal?.name ?? (s2.venue?.isEmpty == false ? s2.venue : nil),
            volume: s2.journal?.volume,
            pages: pages,
            doi: doi,
            abstract: s2.abstract,
            referenceType: .journalArticle,
            metadataSource: .semanticScholar,
            pmid: s2.externalIds?.pmid,
            pmcid: s2.externalIds?.pmcid,
            isOpenAccess: s2.isOpenAccess ? true : nil,
            oaUrl: s2.openAccessPdfUrl,
            citedByCount: s2.citationCount > 0 ? s2.citationCount : nil
        )
    }

    /// Fetch abstract from Semantic Scholar via the `abstractByDoi` route.
    public static func fetchAbstractFromSemanticScholar(doi: String) async throws -> String? {
        let normalized = normalizedDOI(doi)
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "semantic-scholar-paper"),
              let route = adapter.routes["abstractByDoi"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["doi": normalized])
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                let rows = (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
                return rows.first?["abstract"]?.swiftlib_nilIfBlank
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    /// Fetch abstract from OpenAlex (free, no API key, covers ~250M works)
}
