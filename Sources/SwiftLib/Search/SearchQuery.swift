import SwiftLibCore

struct SearchQuery {
    var keyword: String = ""
    var author: String = ""
    var yearFrom: Int?
    var yearTo: Int?
    var journal: String = ""
    var type: ReferenceType?

    static func parse(_ text: String) -> SearchQuery {
        var q = SearchQuery()
        var keywords: [String] = []
        for part in text.components(separatedBy: " ") {
            if part.hasPrefix("author:") {
                q.author = String(part.dropFirst("author:".count))
            } else if part.hasPrefix("year:") {
                let val = String(part.dropFirst("year:".count))
                if val.contains("-") {
                    let comps = val.split(separator: "-", maxSplits: 1)
                    if val.hasPrefix("-") {
                        q.yearTo = Int(comps.last ?? "")
                    } else if comps.count == 2 {
                        q.yearFrom = Int(comps[0])
                        q.yearTo = Int(comps[1])
                    } else {
                        q.yearFrom = Int(comps[0])
                    }
                } else {
                    q.yearFrom = Int(val)
                    q.yearTo = q.yearFrom
                }
            } else if part.hasPrefix("journal:") {
                q.journal = String(part.dropFirst("journal:".count))
            } else if part.hasPrefix("type:") {
                let val = String(part.dropFirst("type:".count))
                q.type = ReferenceType.allCases.first { $0.rawValue == val }
            } else if !part.isEmpty {
                keywords.append(part)
            }
        }
        q.keyword = keywords.joined(separator: " ")
        return q
    }
}
