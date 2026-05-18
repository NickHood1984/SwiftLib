import Foundation

extension MetadataFetcher {
    // MARK: - ISBN → Open Library + Google Books

    /// Fetch book metadata from ISBN via Open Library (primary) with Google Books fallback.
    /// Also tries the ISBN-10 ↔ ISBN-13 alternate form if the primary form fails.
    public static func fetchFromISBN(_ isbn: String, forceRefresh: Bool = false) async throws -> Reference {
        let cacheKey = "isbn:\(isbn)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let candidates = isbnCandidates(for: isbn)

            for candidate in candidates {
                if let ref = try? await fetchFromOpenLibrary(isbn: candidate) {
                    storeInBothCaches(ref, for: cacheKey)
                    return ref
                }
            }
            for candidate in candidates {
                if let ref = try? await fetchFromGoogleBooks(isbn: candidate) {
                    storeInBothCaches(ref, for: cacheKey)
                    return ref
                }
            }
            throw FetchError.notFound
        }
    }

    /// Return the list of ISBN variants worth trying. Primary form first,
    /// followed by the 10↔13 conversion if applicable.
    private static func isbnCandidates(for isbn: String) -> [String] {
        var out = [isbn]
        if isbn.count == 13, let ten = isbn13To10(isbn) { out.append(ten) }
        if isbn.count == 10, let thirteen = isbn10To13(isbn) { out.append(thirteen) }
        return out
    }

    // MARK: - Open Library / Google Books (adapter-driven)

    private static func fetchFromOpenLibrary(isbn: String) async throws -> Reference? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openlibrary-book"),
              let route = adapter.routes["byIsbn"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["isbn": isbn])
        guard let url = URL(string: urlString) else { return nil }
        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                // `itemsPath` is templated as `ISBN:{isbn}` — context must be passed through.
                let rows = (try? SiteAdapterRuntime.extractJSON(
                    route: route,
                    data: data,
                    context: ["isbn": isbn]
                )) ?? []
                guard let row = rows.first else { return nil as Reference? }
                return referenceFromOpenLibraryIsbnRow(row, isbn: isbn)
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    private static func fetchFromGoogleBooks(isbn: String) async throws -> Reference? {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "google-books-volume"),
              let route = adapter.routes["byIsbn"] else { return nil }
        let urlString = SiteAdapterRuntime.expandURL(route.url, context: ["isbn": isbn])
        guard let url = URL(string: urlString) else { return nil }
        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                let rows = (try? SiteAdapterRuntime.extractJSON(route: route, data: data)) ?? []
                guard let row = rows.first else { return nil as Reference? }
                return referenceFromGoogleBooksRow(row, fallbackISBN: isbn)
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - Book adapter row → Reference mappers

    /// Map an Open Library `byIsbn` / `byTitle` adapter row to `Reference`.
    static func referenceFromOpenLibraryIsbnRow(_ row: [String: String], isbn: String) -> Reference {
        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parse(String($0)) }

        let title: String = {
            if let sub = row["subtitle"]?.swiftlib_nilIfBlank,
               let main = row["title"]?.swiftlib_nilIfBlank {
                return "\(main): \(sub)"
            }
            return row["title"]?.swiftlib_nilIfBlank ?? "Untitled"
        }()

        let publisher: String? = (row["publisher"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .first.map(String.init)

        return Reference(
            title: title,
            authors: authors,
            year: row["year"].flatMap(Int.init),
            url: row["url"]?.swiftlib_nilIfBlank,
            abstract: row["description"]?.swiftlib_nilIfBlank,
            referenceType: .book,
            publisher: publisher,
            isbn: row["isbn13"]?.swiftlib_nilIfBlank
                ?? row["isbn10"]?.swiftlib_nilIfBlank
                ?? isbn,
            numberOfPages: row["pageCount"]?.swiftlib_nilIfBlank
        )
    }

    /// Map a Google Books `byIsbn` / `byTitle` adapter row to `Reference`.
    /// Picks ISBN_13 over ISBN_10; falls back to caller-supplied ISBN.
    static func referenceFromGoogleBooksRow(
        _ row: [String: String],
        fallbackISBN: String? = nil
    ) -> Reference {
        let authors: [AuthorName] = (row["authors"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { AuthorName.parse(String($0)) }

        let title: String = {
            if let full = row["titleWithSubtitle"]?.swiftlib_nilIfBlank { return full }
            return row["title"]?.swiftlib_nilIfBlank ?? "Untitled"
        }()

        // Pick best identifier from parallel `industryIdentifiers` arrays.
        let bestISBN: String? = {
            let types = (row["identifierTypes"] ?? "").components(separatedBy: "||")
            let values = (row["identifierValues"] ?? "").components(separatedBy: "||")
            let pairs = zip(types, values)
            if let match = pairs.first(where: { $0.0 == "ISBN_13" }), !match.1.isEmpty { return match.1 }
            if let match = pairs.first(where: { $0.0 == "ISBN_10" }), !match.1.isEmpty { return match.1 }
            return fallbackISBN
        }()

        return Reference(
            title: title,
            authors: authors,
            year: row["year"].flatMap(Int.init),
            abstract: row["description"]?.swiftlib_nilIfBlank,
            referenceType: .book,
            publisher: row["publisher"]?.swiftlib_nilIfBlank,
            isbn: bestISBN,
            numberOfPages: row["pageCount"]?.swiftlib_nilIfBlank
        )
    }

    // MARK: - Book Title Search

    /// Search for book metadata by title when no ISBN is available.
    /// For Chinese titles: tries Douban first, then falls back to Open Library / Google Books.
    /// For non-Chinese titles: tries Open Library first, then Google Books.
    /// Returns nil if no result meets the title similarity threshold.
    public static func searchBookByTitle(_ title: String, forceRefresh: Bool = false) async throws -> Reference? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let cacheKey = "book-title:\(normalized.lowercased())"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedOptionalFetch(key: cacheKey) {
            // For Chinese titles, Douban is the most reliable source
            if MetadataResolution.containsHanCharacters(normalized) {
                if let ref = try? await searchDoubanBookByTitle(normalized) {
                    storeInBothCaches(ref, for: cacheKey)
                    return ref
                }
            }

            if let ref = try? await searchOpenLibraryByTitle(normalized) {
                storeInBothCaches(ref, for: cacheKey)
                return ref
            }

            if let ref = try? await searchGoogleBooksByTitle(normalized) {
                storeInBothCaches(ref, for: cacheKey)
                return ref
            }

            return nil
        }
    }

    /// Search Douban Books by title.
    ///
    /// This function is now a thin orchestrator: **all** URL templates, JSON
    /// paths, filters, and HTML regexes live in `Resources/adapters/douban-book.json`
    /// and are executed via `SiteAdapterRuntime`. When the upstream schema
    /// drifts (which Douban does on a ~yearly cadence) we can ship a fix by
    /// editing the JSON — no Swift rebuild — and the canary harness plus
    /// `scripts/canary.sh` will flag the drift before users hit it.
    ///
    /// Returns nil silently on network failure so non-CN users (where Douban
    /// is often unreachable) fall through to Open Library / Google Books.
    public static func searchDoubanBookByTitle(_ title: String) async throws -> Reference? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "douban-book") else {
            log.warning("douban-book adapter missing; Douban search disabled")
            return nil
        }
        guard let searchRoute = adapter.routes["search"] else { return nil }

        let searchURLString = SiteAdapterRuntime.expandURL(searchRoute.url, context: ["query": normalized])
        guard let searchURL = URL(string: searchURLString) else { return nil }

        do {
            let rows: [[String: String]] = try await fetchAdapterRequest(
                route: searchRoute,
                url: searchURL
            ) { data in
                (try? SiteAdapterRuntime.extractJSON(route: searchRoute, data: data)) ?? []
            }

            for row in rows {
                guard let resultTitle = row["title"], !resultTitle.isEmpty else { continue }
                let similarity = MetadataResolution.titleSimilarity(normalized, resultTitle)
                guard similarity >= 0.55 else { continue }

                let authors = parseDoubanAuthors(row["authorRaw"] ?? "")
                let year = row["year"].flatMap { Int($0.prefix(4)) }
                let subjectUrl = row["subjectUrl"]
                    ?? row["subjectId"].map { "https://book.douban.com/subject/\($0)/" }

                var ref = Reference(
                    title: resultTitle,
                    authors: authors,
                    year: year,
                    url: subjectUrl,
                    referenceType: .book,
                    metadataSource: .douban,
                    publisher: row["publisher"]?.swiftlib_nilIfBlank,
                    isbn: row["isbn"]?.swiftlib_nilIfBlank
                )

                // Follow detail route for ISBN / publisher / pages / abstract.
                if let subjectUrl,
                   let detailRoute = adapter.routes["detail"],
                   let detail = try? await fetchDoubanDetail(subjectUrl: subjectUrl, route: detailRoute) {
                    mergeDoubanDetail(&ref, detail: detail)
                }

                return ref
            }
            return nil
        } catch {
            log.debug("Douban search failed (graceful): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func parseDoubanAuthors(_ raw: String) -> [AuthorName] {
        guard !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: CharacterSet(charactersIn: "/／,，"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Strip Chinese role suffixes: "刘建康 编" → "刘建康".
            .map { $0.replacingOccurrences(of: #"\s*(编|著|译|等|主编)$"#, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { AuthorName.parse($0) }
    }

    private static func mergeDoubanDetail(_ ref: inout Reference, detail: [String: String]) {
        if ref.isbn?.swiftlib_nilIfBlank == nil,
           let isbn = detail["isbn"]?.swiftlib_nilIfBlank {
            ref.isbn = isbn
        }
        if ref.publisher?.swiftlib_nilIfBlank == nil,
           let publisher = detail["publisher"]?.swiftlib_nilIfBlank {
            ref.publisher = publisher
        }
        if ref.year == nil, let yearStr = detail["year"], let year = Int(yearStr.prefix(4)) {
            ref.year = year
        }
        if ref.numberOfPages?.swiftlib_nilIfBlank == nil,
           let pages = detail["pages"]?.swiftlib_nilIfBlank {
            ref.numberOfPages = pages
        }
        if ref.authors.isEmpty, let authorRaw = detail["authorRaw"]?.swiftlib_nilIfBlank {
            ref.authors = parseDoubanAuthors(authorRaw)
        }
        if (ref.abstract ?? "").isEmpty, let abs = detail["abstract"]?.swiftlib_nilIfBlank {
            ref.abstract = abs
        }
    }

    /// Fetch and parse a Douban subject detail page via the adapter runtime.
    /// Returns the raw extracted `[String: String]` row — callers map these
    /// strings onto `Reference` fields via `mergeDoubanDetail(_:detail:)`.
    static func fetchDoubanDetail(
        subjectUrl: String,
        route: SiteAdapterDefinition.Route
    ) async throws -> [String: String]? {
        let expanded = SiteAdapterRuntime.expandURL(route.url, context: ["subjectUrl": subjectUrl])
        // Special-case: `{subjectUrl}` is itself a full URL, not a query param.
        // `expandURL` percent-encodes it; reverse that one key.
        let finalURLString = route.url == "{subjectUrl}" ? subjectUrl : expanded
        guard let url = URL(string: finalURLString) else { return nil }

        do {
            return try await fetchAdapterRequest(
                route: route,
                url: url
            ) { data in
                guard let html = String(data: data, encoding: .utf8) else { return nil as [String: String]? }
                return (try? SiteAdapterRuntime.extractHTML(route: route, html: html)) ?? [:]
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    // MARK: - Douban Detail Page Parser (test-facing shim)

    /// Simple struct exposed to tests. Internal production code uses the
    /// adapter runtime's `[String: String]` rows directly — this shim exists
    /// so the existing fixture-based parser tests keep compiling.
    struct DoubanDetail: Sendable, Equatable {
        var isbn: String?
        var publisher: String?
        var publisherPlace: String?
        var year: Int?
        var pages: String?
        var authors: [AuthorName] = []
        var abstract: String?
    }

    /// Parse the Douban `#info` block out of the detail page HTML by
    /// delegating to the `douban-book` adapter's `detail` route.
    /// Keeps the old API stable for existing tests / external callers.
    static func parseDoubanDetailHTML(_ html: String) -> DoubanDetail {
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "douban-book"),
              let route = adapter.routes["detail"],
              let extracted = try? SiteAdapterRuntime.extractHTML(route: route, html: html) else {
            return DoubanDetail()
        }
        var detail = DoubanDetail()
        detail.isbn = extracted["isbn"]?.swiftlib_nilIfBlank
        detail.publisher = extracted["publisher"]?.swiftlib_nilIfBlank
        detail.pages = extracted["pages"]?.swiftlib_nilIfBlank
        detail.abstract = extracted["abstract"]?.swiftlib_nilIfBlank
        if let yearStr = extracted["year"], let year = Int(yearStr.prefix(4)) {
            detail.year = year
        }
        if let authorRaw = extracted["authorRaw"], !authorRaw.isEmpty {
            detail.authors = parseDoubanAuthors(authorRaw)
        }
        return detail
    }

    private static func searchOpenLibraryByTitle(_ title: String) async throws -> Reference? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://openlibrary.org/search.json?title=\(encoded)&limit=3&fields=key,title,author_name,first_publish_year,isbn,publisher,number_of_pages_median") else { return nil }

        let firstDoc: [String: Any]? = try? await performRequest(url: url) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["docs"] as? [[String: Any]],
                  let firstDoc = docs.first else {
                return nil as [String: Any]?
            }
            return firstDoc
        }

        guard let firstDoc,
              let resultTitle = firstDoc["title"] as? String,
              bookTitleSimilarity(title, resultTitle) >= 0.5 else { return nil }

        if let isbns = firstDoc["isbn"] as? [String],
           let bestISBN = isbns.first(where: { $0.count == 13 }) ?? isbns.first(where: { $0.count == 10 }),
           let ref = try? await fetchFromOpenLibrary(isbn: bestISBN) {
            return ref
        }

        let authors: [AuthorName] = {
            guard let names = firstDoc["author_name"] as? [String] else { return [] }
            return names.map { AuthorName.parse($0) }
        }()
        let year = firstDoc["first_publish_year"] as? Int
        let publisher = (firstDoc["publisher"] as? [String])?.first
        let numberOfPages = (firstDoc["number_of_pages_median"] as? Int).map(String.init)
        return Reference(
            title: resultTitle,
            authors: authors,
            year: year,
            referenceType: .book,
            publisher: publisher,
            numberOfPages: numberOfPages
        )
    }

    private static func searchGoogleBooksByTitle(_ title: String) async throws -> Reference? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=intitle:\(encoded)&maxResults=1") else { return nil }

        return try? await performRequest(url: url) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let first = items.first,
                  let volumeInfo = first["volumeInfo"] as? [String: Any],
                  let resultTitle = volumeInfo["title"] as? String,
                  bookTitleSimilarity(title, resultTitle) >= 0.5 else {
                return nil as Reference?
            }

            let authors: [AuthorName] = {
                guard let authorList = volumeInfo["authors"] as? [String] else { return [] }
                return authorList.map { AuthorName.parse($0) }
            }()
            let year: Int? = {
                guard let publishedDate = volumeInfo["publishedDate"] as? String else { return nil }
                return Int(publishedDate.prefix(4))
            }()
            let numberOfPages: String? = {
                guard let n = volumeInfo["pageCount"] as? Int else { return nil }
                return String(n)
            }()
            let isbn: String? = {
                guard let identifiers = volumeInfo["industryIdentifiers"] as? [[String: Any]] else { return nil }
                let isbn13 = identifiers.first(where: { $0["type"] as? String == "ISBN_13" })?["identifier"] as? String
                let isbn10 = identifiers.first(where: { $0["type"] as? String == "ISBN_10" })?["identifier"] as? String
                return isbn13 ?? isbn10
            }()
            return Reference(
                title: resultTitle,
                authors: authors,
                year: year,
                abstract: volumeInfo["description"] as? String,
                referenceType: .book,
                publisher: volumeInfo["publisher"] as? String,
                isbn: isbn,
                numberOfPages: numberOfPages
            )
        }
    }

    /// Word-overlap Jaccard similarity between two titles (0–1).
    private static func bookTitleSimilarity(_ a: String, _ b: String) -> Double {
        let tokenize: (String) -> Set<String> = { s in
            Set(
                s.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .flatMap { $0.components(separatedBy: .punctuationCharacters) }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.count > 1 }
            )
        }
        let wordsA = tokenize(a)
        let wordsB = tokenize(b)
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let intersection = Double(wordsA.intersection(wordsB).count)
        let union = Double(wordsA.union(wordsB).count)
        return intersection / union
    }

}
