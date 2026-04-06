import Foundation

/// High-performance citation formatter — all string ops, no regex, <0.1ms per citation
public enum CitationFormatter {

    public static let supportedStyles = ["apa", "mla", "chicago", "ieee", "harvard", "vancouver", "nature"]

    public static let stylesJSON: String = {
        let styles = supportedStyles.map { """
        {"id":"\($0)","name":"\($0.uppercased())"}
        """ }
        return "[\(styles.joined(separator: ","))]"
    }()

    public static func citationKind(for style: String) -> CitationKind {
        if let resolved = CSLManager.shared.availableStyles().first(where: { $0.id == style })?.citationKind {
            return resolved
        }
        switch style {
        case "ieee", "vancouver", "nature":
            return .numeric
        default:
            return .authorDate
        }
    }

    // MARK: - Inline Citation (in-text)

    /// Format inline citation for multiple references
    /// e.g. "(Smith et al., 2024; Jones & Lee, 2023)"
    public static func formatInlineCitation(_ refs: [Reference], style: String) -> String {
        if citationKind(for: style) == .numeric {
            let numbers = Array(1...max(refs.count, 1))
            return formatNumericInlineCitation(numbers: numbers, style: style)
        }

        let parts = refs.map { formatSingleInline($0, style: style) }

        switch style {
        case "ieee":
            return "[\(parts.joined(separator: ", "))]"
        default:
            return "(\(parts.joined(separator: "; ")))"
        }
    }

    private static func formatSingleInline(_ ref: Reference, style: String) -> String {
        let firstAuthor = extractLastName(ref.authors)
        let authorCount = ref.authors.count
        let year = ref.year.map { String($0) } ?? "n.d."

        switch style {
        case "apa", "harvard":
            // (Smith, 2024) or (Smith et al., 2024)
            if authorCount > 2 {
                return "\(firstAuthor) et al., \(year)"
            } else if authorCount == 2 {
                let second = extractSecondLastName(ref.authors)
                return "\(firstAuthor) & \(second), \(year)"
            }
            return "\(firstAuthor), \(year)"

        case "mla":
            // (Smith 42) or (Smith et al. 42)
            let page = ref.pages?.components(separatedBy: "-").first ?? ""
            if authorCount > 2 {
                return "\(firstAuthor) et al.\(page.isEmpty ? "" : " \(page)")"
            }
            return "\(firstAuthor)\(page.isEmpty ? "" : " \(page)")"

        case "chicago":
            // (Smith 2024, 42)
            if authorCount > 2 {
                return "\(firstAuthor) et al. \(year)"
            }
            return "\(firstAuthor) \(year)"

        case "ieee":
            // [1] style — return placeholder number
            return "\(ref.id ?? 0)"

        case "vancouver":
            return "\(ref.id ?? 0)"

        case "nature":
            return "\(ref.id ?? 0)"

        default:
            return "\(firstAuthor), \(year)"
        }
    }

    // MARK: - Bibliography Entry

    /// Format full bibliography entry
    public static func formatBibliography(_ ref: Reference, style: String) -> String {
        switch style {
        case "apa":
            return formatAPA(ref)
        case "mla":
            return formatMLA(ref)
        case "chicago":
            return formatChicago(ref)
        case "ieee":
            return formatIEEE(ref)
        case "harvard":
            return formatHarvard(ref)
        case "vancouver":
            return formatVancouver(ref)
        case "nature":
            return formatNature(ref)
        default:
            return formatAPA(ref)
        }
    }

    public static func formatNumericInlineCitation(numbers: [Int], style: String) -> String {
        let sorted = numbers.sorted()
        guard !sorted.isEmpty else { return style == "nature" ? "0" : "[0]" }

        var ranges: [String] = []
        var start = sorted[0]
        var end = sorted[0]

        for i in 1..<sorted.count {
            if sorted[i] == end + 1 {
                end = sorted[i]
            } else {
                ranges.append(start == end ? "\(start)" : "\(start)-\(end)")
                start = sorted[i]
                end = sorted[i]
            }
        }
        ranges.append(start == end ? "\(start)" : "\(start)-\(end)")

        let formatted = ranges.joined(separator: ", ")
        switch style {
        case "nature":
            return formatted
        default:
            return "[\(formatted)]"
        }
    }

    public static func formatNumericBibliographyEntry(_ entry: String, number: Int, style: String) -> String {
        switch style {
        case "ieee":
            return "[\(number)] \(entry)"
        case "vancouver", "nature":
            return "\(number). \(entry)"
        default:
            return "[\(number)] \(entry)"
        }
    }

    // MARK: - APA 7th Edition

    private static func formatAPA(_ ref: Reference) -> String {
        var parts: [String] = []

        // Authors: Last, F. M., & Last, F. M.
        let authorStr = formatAuthorsAPA(ref.authors)
        parts.append(authorStr)

        // Year
        if let year = ref.year {
            parts.append("(\(year)).")
        } else {
            parts.append("(n.d.).")
        }

        // Title
        parts.append("\(ref.title).")

        // Journal (italic) + volume, issue, pages
        if let journal = ref.journal, !journal.isEmpty {
            var journalPart = journal
            if let vol = ref.volume {
                journalPart += ", \(vol)"
                if let issue = ref.issue {
                    journalPart += "(\(issue))"
                }
            }
            if let pages = ref.pages {
                journalPart += ", \(pages)"
            }
            parts.append("\(journalPart).")
        }

        // DOI
        if let doi = ref.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - MLA 9th Edition

    private static func formatMLA(_ ref: Reference) -> String {
        var parts: [String] = []

        let authorStr = formatAuthorsLastFirst(ref.authors)
        parts.append("\(authorStr).")
        parts.append("\"\(ref.title).\"")

        if let journal = ref.journal {
            var jPart = journal
            if let vol = ref.volume {
                jPart += ", vol. \(vol)"
            }
            if let issue = ref.issue {
                jPart += ", no. \(issue)"
            }
            if let year = ref.year {
                jPart += ", \(year)"
            }
            if let pages = ref.pages {
                jPart += ", pp. \(pages)"
            }
            parts.append("\(jPart).")
        }

        if let doi = ref.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Chicago 17th

    private static func formatChicago(_ ref: Reference) -> String {
        var parts: [String] = []

        let authorStr = formatAuthorsLastFirst(ref.authors)
        parts.append("\(authorStr).")
        parts.append("\"\(ref.title).\"")

        if let journal = ref.journal {
            var jPart = journal
            if let vol = ref.volume {
                jPart += " \(vol)"
                if let issue = ref.issue {
                    jPart += ", no. \(issue)"
                }
            }
            if let year = ref.year {
                jPart += " (\(year))"
            }
            if let pages = ref.pages {
                jPart += ": \(pages)"
            }
            parts.append("\(jPart).")
        }

        if let doi = ref.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - IEEE

    private static func formatIEEE(_ ref: Reference) -> String {
        var parts: [String] = []

        let authorStr = formatAuthorsIEEE(ref.authors)
        parts.append(authorStr + ",")
        parts.append("\"\(ref.title),\"")

        if let journal = ref.journal {
            var jPart = journal
            if let vol = ref.volume {
                jPart += ", vol. \(vol)"
            }
            if let issue = ref.issue {
                jPart += ", no. \(issue)"
            }
            if let pages = ref.pages {
                jPart += ", pp. \(pages)"
            }
            if let year = ref.year {
                jPart += ", \(year)"
            }
            parts.append("\(jPart).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Harvard

    private static func formatHarvard(_ ref: Reference) -> String {
        formatAPA(ref) // Harvard is very similar to APA
    }

    // MARK: - Vancouver

    private static func formatVancouver(_ ref: Reference) -> String {
        var parts: [String] = []

        let authorStr = formatAuthorsVancouver(ref.authors)
        parts.append("\(authorStr).")
        parts.append("\(ref.title).")

        if let journal = ref.journal {
            var jPart = journal
            if let year = ref.year {
                jPart += ". \(year)"
            }
            if let vol = ref.volume {
                jPart += ";\(vol)"
                if let issue = ref.issue {
                    jPart += "(\(issue))"
                }
            }
            if let pages = ref.pages {
                jPart += ":\(pages)"
            }
            parts.append("\(jPart).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Nature

    private static func formatNature(_ ref: Reference) -> String {
        var parts: [String] = []

        let authorStr = formatAuthorsNature(ref.authors)
        parts.append(authorStr)
        parts.append("\(ref.title).")

        if let journal = ref.journal {
            var jPart = journal
            if let vol = ref.volume {
                jPart += " \(vol)"
            }
            if let pages = ref.pages {
                jPart += ", \(pages)"
            }
            if let year = ref.year {
                jPart += " (\(year))"
            }
            parts.append("\(jPart).")
        }

        if let doi = ref.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Author Formatting Helpers

    private static func extractLastName(_ authors: [AuthorName]) -> String {
        authors.first?.family ?? "Unknown"
    }

    private static func extractSecondLastName(_ authors: [AuthorName]) -> String {
        guard authors.count >= 2 else { return "" }
        return authors[1].family
    }

    private static func formatAuthorsAPA(_ authors: [AuthorName]) -> String {
        let list = authors
        if list.isEmpty { return "Unknown" }
        if list.count == 1 { return list[0].shortName }
        if list.count == 2 { return "\(list[0].shortName), & \(list[1].shortName)" }
        if list.count <= 20 {
            let allButLast = list.dropLast().map { $0.shortName }.joined(separator: ", ")
            return "\(allButLast), & \(list.last!.shortName)"
        }
        let first19 = list.prefix(19).map { $0.shortName }.joined(separator: ", ")
        return "\(first19), ... \(list.last!.shortName)"
    }

    private static func formatAuthorsLastFirst(_ authors: [AuthorName]) -> String {
        guard let first = authors.first else { return "Unknown" }
        if authors.count == 1 { return first.shortName }
        if authors.count <= 3 {
            return authors.map { $0.shortName }.joined(separator: ", ")
        }
        return "\(first.shortName), et al"
    }

    private static func formatAuthorsIEEE(_ authors: [AuthorName]) -> String {
        if authors.isEmpty { return "Unknown" }
        let formatted = authors.prefix(6).map { a in
            let initials = a.given.components(separatedBy: " ").map { String($0.prefix(1)) + "." }.joined(separator: " ")
            return initials.isEmpty ? a.family : "\(initials) \(a.family)"
        }
        return formatted.joined(separator: ", ") + (authors.count > 6 ? ", et al." : "")
    }

    private static func formatAuthorsVancouver(_ authors: [AuthorName]) -> String {
        if authors.isEmpty { return "Unknown" }
        let formatted = authors.prefix(6).map { a in
            let initials = a.given.components(separatedBy: " ").map { String($0.prefix(1)) }.joined()
            return "\(a.family) \(initials)"
        }
        return formatted.joined(separator: ", ") + (authors.count > 6 ? ", et al" : "")
    }

    private static func formatAuthorsNature(_ authors: [AuthorName]) -> String {
        if authors.isEmpty { return "Unknown" }
        let formatted = authors.prefix(5).map { a in
            let initials = a.given.components(separatedBy: " ").map { String($0.prefix(1)) }.joined()
            return "\(a.family) \(initials)"
        }
        return formatted.joined(separator: ", ") + (authors.count > 5 ? " et al." : "")
    }
}
