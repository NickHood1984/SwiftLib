import Foundation

extension MetadataFetcher {
    // MARK: - PMID → PubMed API

    /// Fetch metadata from PMID via NCBI esummary + (optional) efetch for abstract.
    public static func fetchFromPMID(_ pmid: String, forceRefresh: Bool = false) async throws -> Reference {
        let cacheKey = "pmid:\(pmid)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let urlString = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(pmid)&retmode=json\(pubmedIdentifyParams())"
            guard let url = URL(string: urlString) else {
                throw FetchError.invalidURL
            }

            var ref = try await performRequest(url: url) { data in
                try parsePubMedResponse(data, pmid: pmid)
            }

            // esummary doesn't include abstracts; efetch does. Try once, non-fatally.
            if (ref.abstract ?? "").isEmpty,
               let abs = try? await fetchAbstractFromPubMed(pmid: pmid) {
                ref.abstract = abs
            }

            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    /// Fetch abstract text from PubMed via efetch.
    public static func fetchAbstractFromPubMed(pmid: String) async throws -> String? {
        let urlString = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=\(pmid)&rettype=abstract&retmode=xml\(pubmedIdentifyParams())"
        guard let url = URL(string: urlString) else { return nil }

        do {
            return try await performRequest(url: url) { data in
                let parser = PubMedAbstractXMLParser(data: data)
                return parser.parse()
            }
        } catch FetchError.notFound {
            return nil
        }
    }

    /// NCBI recommends every request carry `tool=` and `email=` parameters so
    /// they can contact the operator before rate-limiting or blocking.
    private static func pubmedIdentifyParams() -> String {
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = "&tool=SwiftLib"
        if !email.isEmpty, email.contains("@"),
           let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            components += "&email=\(encoded)"
        }
        return components
    }

    static func parsePubMedResponse(_ data: Data, pmid: String) throws -> Reference {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let article = result[pmid] as? [String: Any] else {
            throw FetchError.parseError
        }

        let title = (article["title"] as? String)?.trimmingCharacters(in: .init(charactersIn: ".")) ?? "Untitled"

        let authors: [AuthorName] = {
            guard let authorList = article["authors"] as? [[String: Any]] else { return [] }
            return authorList.compactMap { entry -> AuthorName? in
                guard let name = entry["name"] as? String else { return nil }
                return AuthorName.parse(name)
            }
        }()

        let year: Int? = {
            if let pubDate = article["pubdate"] as? String {
                let components = pubDate.components(separatedBy: " ")
                return components.first.flatMap { Int($0) }
            }
            return nil
        }()

        let articleIDs = article["articleids"] as? [[String: Any]] ?? []

        let doi: String? = {
            articleIDs.first(where: { ($0["idtype"] as? String) == "doi" })?["value"] as? String
        }()

        let pmcid: String? = {
            articleIDs.first(where: { ($0["idtype"] as? String) == "pmc" })?["value"] as? String
        }()

        return Reference(
            title: title,
            authors: authors,
            year: year,
            journal: article["source"] as? String,
            volume: article["volume"] as? String,
            issue: article["issue"] as? String,
            pages: article["pages"] as? String,
            doi: doi,
            referenceType: .journalArticle,
            pmid: pmid,
            pmcid: pmcid
        )
    }

}

// MARK: - PubMed efetch Abstract XML Parser

/// Parses the subset of PubMed's efetch XML that we care about: the concatenated
/// `AbstractText` content. Multiple `AbstractText` elements (labelled abstracts)
/// are joined with a space, prefixed by their Label when present.
private final class PubMedAbstractXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var abstractParts: [String] = []

    private var currentText = ""
    private var currentLabel = ""
    private var inAbstractText = false

    init(data: Data) { self.data = data }

    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        guard !abstractParts.isEmpty else { return nil }
        let joined = abstractParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentText = ""
        if elementName == "AbstractText" {
            inAbstractText = true
            currentLabel = attributes["Label"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inAbstractText { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "AbstractText" {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !currentLabel.isEmpty {
                    abstractParts.append("\(currentLabel): \(trimmed)")
                } else {
                    abstractParts.append(trimmed)
                }
            }
            inAbstractText = false
            currentLabel = ""
        }
    }
}
