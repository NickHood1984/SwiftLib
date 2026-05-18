import Foundation

extension MetadataFetcher {
    // MARK: - arXiv

    /// Fetch metadata from arXiv ID via arXiv Atom API.
    public static func fetchFromArXiv(_ arxivId: String, forceRefresh: Bool = false) async throws -> Reference {
        let cacheKey = "arxiv:\(arxivId)"
        if !forceRefresh, let cached = cachedOrPersisted(key: cacheKey) { return cached }

        return try await InFlightCoalescer.shared.dedupedFetch(key: cacheKey) {
            let urlString = "https://export.arxiv.org/api/query?id_list=\(arxivId)&max_results=1"
            guard let url = URL(string: urlString) else {
                throw FetchError.invalidURL
            }

            let ref = try await performRequest(url: url) { data in
                try parseArXivResponse(data, arxivId: arxivId)
            }
            storeInBothCaches(ref, for: cacheKey)
            return ref
        }
    }

    static func parseArXivResponse(_ data: Data, arxivId: String) throws -> Reference {
        let parser = ArXivXMLParser(data: data)
        guard var entry = parser.parse() else {
            throw FetchError.parseError
        }
        entry.url = "https://arxiv.org/abs/\(arxivId)"
        return entry
    }

}

// MARK: - arXiv Atom XML Parser

private class ArXivXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var result: Reference?

    private var currentElement = ""
    private var currentText = ""
    private var title = ""
    private var abstract = ""
    private var authors: [AuthorName] = []
    private var currentAuthor = ""
    private var published = ""
    private var doi: String?
    private var inEntry = false
    private var inAuthor = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> Reference? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "entry" { inEntry = true }
        if elementName == "author" { inAuthor = true; currentAuthor = "" }
        if elementName == "link" && inEntry {
            if attributes["title"] == "doi", let href = attributes["href"] {
                if let range = href.range(of: "doi.org/") {
                    doi = String(href[range.upperBound...])
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inEntry {
            switch elementName {
            case "title":
                title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            case "summary":
                abstract = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            case "name":
                if inAuthor { currentAuthor = text }
            case "author":
                inAuthor = false
                if !currentAuthor.isEmpty { authors.append(AuthorName.parse(currentAuthor)) }
            case "published":
                published = text
            case "entry":
                inEntry = false
                let year = Int(published.prefix(4))
                result = Reference(
                    title: title,
                    authors: authors,
                    year: year,
                    doi: doi,
                    url: nil,
                    abstract: abstract,
                    referenceType: .journalArticle
                )
            default:
                break
            }
        }

        currentElement = ""
    }
}
