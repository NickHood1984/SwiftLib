import Foundation

// ---------------------------------------------------------------------------
// MetadataFetcher+DOIContentNegotiation
//
// DOI content negotiation: resolves any DOI against doi.org with
//   Accept: application/vnd.citationstyles.csl+json
// This is the most authoritative single-step path for DOI → metadata, since
// the Registration Agency (Crossref, DataCite, mEDRA) returns the data it
// holds directly in CSL-JSON format, which maps cleanly to Reference fields.
//
// Architecture:
//   1. Strip and validate DOI using DOIIdentifier
//   2. GET https://doi.org/{doi}  (with polite email header and network rate limit)
//   3. Decode CSL-JSON → CSLItem
//   4. Map CSLItem → Reference candidate
//
// This fetcher is used by MetadataRoutePlanner as the primary source for
// DOI-bearing items, with CrossRef REST serving as a field-enrichment
// fallback (for keywords, cited-by-count, OA status from OpenAlex etc.).
// ---------------------------------------------------------------------------

extension MetadataFetcher {

    // MARK: - Public API

    /// Fetch a Reference candidate from DOI content negotiation.
    ///
    /// Returns nil if the DOI is invalid, the network is unavailable, or the
    /// Registration Agency does not support CSL-JSON for this DOI.
    ///
    /// - Parameters:
    ///   - doi: Raw DOI string — may contain https://doi.org/ prefix.
    ///   - contactEmail: Contact email for the Crossref polite pool.
    ///     Defaults to `MetadataFetcher.contactEmail`.
    public static func fetchFromDOIContentNegotiation(
        doi rawDOI: String,
        contactEmail: String? = nil
    ) async -> Reference? {
        // 1. Validate + normalise DOI
        guard let doiObj = DOIIdentifier(rawDOI) else { return nil }
        let cleanDOI = doiObj.stripped   // bare DOI with original case

        // 2. Build request
        let urlString = "https://doi.org/\(cleanDOI)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 15)
        // CSL-JSON is preferred; fall back to RDF XML which can also be decoded
        request.setValue("application/vnd.citationstyles.csl+json", forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.citationstyles.csl+json", forHTTPHeaderField: "Content-Type")
        // Identify ourselves to the Crossref polite pool
        let email = contactEmail ?? MetadataFetcher.contactEmail
        if !email.isEmpty {
            request.setValue("SwiftLib/1.0 (mailto:\(email))", forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("SwiftLib/1.0", forHTTPHeaderField: "User-Agent")
        }

        // 3. Fetch
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await NetworkClient.session.data(for: request)
        } catch {
            if SwiftLibCoreDebugLogging.runtimeVerbose {
                print("[DOIContentNegotiation] Network error for \(cleanDOI): \(error.localizedDescription)")
            }
            return nil
        }

        // 4. Check HTTP status (200 = OK; 406 = CSL-JSON not supported for this DOI)
        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                if SwiftLibCoreDebugLogging.runtimeVerbose {
                    print("[DOIContentNegotiation] HTTP \(http.statusCode) for \(cleanDOI)")
                }
                return nil
            }
        }

        // 5. Decode CSL-JSON
        let decoder = JSONDecoder()
        guard let cslItem = try? decoder.decode(CSLItem.self, from: data) else {
            if SwiftLibCoreDebugLogging.runtimeVerbose {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? "?"
                print("[DOIContentNegotiation] Failed to decode CSL-JSON for \(cleanDOI): \(preview)")
            }
            return nil
        }

        // 6. Map CSLItem → Reference
        var ref = referenceFromCSLItem(cslItem)
        // Always stamp the DOI — use the stripped (original-case) form
        if ref.doi == nil || ref.doi?.isEmpty == true {
            ref.doi = cleanDOI
        }
        ref.metadataSource = .crossRef   // DOI content negotiation is backed by Crossref for most DOIs
        return ref
    }

    // MARK: - CSLItem → Reference mapping

    /// Map a decoded CSL-JSON item to a `Reference` candidate.
    /// This mirrors what `Reference.toCSLItem()` does in reverse.
    static func referenceFromCSLItem(_ item: CSLItem) -> Reference {
        // Reference type
        let refType = ReferenceType.from(cslType: item.type)

        // Authors
        let authors: [AuthorName] = (item.author ?? []).compactMap { name in
            if let literal = name.literal, !literal.isEmpty {
                // Institutional author: store in family, leave given empty
                return AuthorName(given: "", family: literal)
            }
            guard let family = name.family, !family.isEmpty else { return nil }
            var familyStr = family
            if let ndp = name.nonDroppingParticle, !ndp.isEmpty {
                familyStr = "\(ndp) \(family)"
            }
            return AuthorName(given: name.given ?? "", family: familyStr)
        }

        // Editors
        let editors: String? = {
            let eds = (item.editor ?? []).compactMap { name -> AuthorName? in
                if let literal = name.literal, !literal.isEmpty { return AuthorName(given: "", family: literal) }
                guard let family = name.family, !family.isEmpty else { return nil }
                return AuthorName(given: name.given ?? "", family: family)
            }
            return eds.isEmpty ? nil : Reference.encodeNames(eds)
        }()

        // Translators
        let translators: String? = {
            let trans = (item.translator ?? []).compactMap { name -> AuthorName? in
                if let literal = name.literal, !literal.isEmpty { return AuthorName(given: "", family: literal) }
                guard let family = name.family, !family.isEmpty else { return nil }
                return AuthorName(given: name.given ?? "", family: family)
            }
            return trans.isEmpty ? nil : Reference.encodeNames(trans)
        }()

        // Year / month / day
        let year: Int? = item.issued?.dateParts?.first?.first
        let issuedMonth: Int? = item.issued?.dateParts?.first.flatMap { $0.count >= 2 ? $0[1] : nil }
        let issuedDay: Int? = item.issued?.dateParts?.first.flatMap { $0.count >= 3 ? $0[2] : nil }

        // Accessed date
        let accessedDate: String? = {
            guard let parts = item.accessed?.dateParts?.first, !parts.isEmpty else { return nil }
            if parts.count >= 3 {
                return String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
            } else if parts.count == 2 {
                return String(format: "%04d-%02d", parts[0], parts[1])
            }
            return String(parts[0])
        }()

        // Publisher: thesis uses publisher as institution
        let publisher = item.publisher?.swiftlib_nilIfBlank
        let institution: String? = refType == .thesis ? publisher : nil
        let effectivePublisher: String? = refType == .thesis ? nil : publisher

        // Clean DOI (strip any prefix that might appear in content-negotiation responses)
        let cleanDOI = item.DOI.flatMap { DOIIdentifier($0)?.stripped }

        return Reference(
            title: item.title ?? "",
            authors: authors,
            year: year,
            journal: item.containerTitle?.swiftlib_nilIfBlank,
            volume: item.volume?.swiftlib_nilIfBlank,
            issue: item.issue?.swiftlib_nilIfBlank,
            pages: item.page?.swiftlib_nilIfBlank,
            doi: cleanDOI,
            url: item.URL?.swiftlib_nilIfBlank,
            abstract: item.abstract?.swiftlib_nilIfBlank,
            referenceType: refType,
            publisher: effectivePublisher,
            publisherPlace: item.publisherPlace?.swiftlib_nilIfBlank,
            edition: item.edition?.swiftlib_nilIfBlank,
            editors: editors,
            isbn: item.ISBN?.swiftlib_nilIfBlank,
            issn: item.ISSN?.swiftlib_nilIfBlank,
            accessedDate: accessedDate,
            issuedMonth: issuedMonth,
            issuedDay: issuedDay,
            translators: translators,
            eventTitle: item.eventTitle?.swiftlib_nilIfBlank,
            eventPlace: item.eventPlace?.swiftlib_nilIfBlank,
            genre: item.genre?.swiftlib_nilIfBlank,
            institution: institution,
            number: item.number?.swiftlib_nilIfBlank,
            collectionTitle: item.collectionTitle?.swiftlib_nilIfBlank,
            language: item.language?.swiftlib_nilIfBlank,
            pmid: item.PMID?.swiftlib_nilIfBlank,
            pmcid: item.PMCID?.swiftlib_nilIfBlank
        )
    }
}

// MARK: - ReferenceType from CSL type string

private extension ReferenceType {
    static func from(cslType: String) -> ReferenceType {
        switch cslType {
        case "article-journal":    return .journalArticle
        case "article-magazine":   return .magazineArticle
        case "article-newspaper":  return .newspaperArticle
        case "article":            return .preprint
        case "book":               return .book
        case "chapter":            return .bookSection
        case "paper-conference":   return .conferencePaper
        case "thesis":             return .thesis
        case "dataset":            return .dataset
        case "software":           return .software
        case "standard":           return .standard
        case "manuscript":         return .manuscript
        case "interview":          return .interview
        case "speech":             return .presentation
        case "post-weblog":        return .blogPost
        case "post":               return .forumPost
        case "legal_case":         return .legalCase
        case "legislation":        return .legislation
        case "webpage":            return .webpage
        case "report":             return .report
        case "patent":             return .patent
        default:                   return .other
        }
    }
}
