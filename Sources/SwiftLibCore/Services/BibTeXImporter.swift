import Foundation

/// High-performance BibTeX parser for bulk import
public enum BibTeXImporter {
    /// Parse BibTeX string into Reference array — optimized for large files
    public static func parse(_ bibtex: String) -> [Reference] {
        var references: [Reference] = []
        references.reserveCapacity(1000)

        let scanner = Scanner(string: bibtex)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            guard scanner.scanUpToString("@") != nil || scanner.scanString("@") != nil else {
                break
            }
            if scanner.scanString("@") == nil && scanner.isAtEnd { break }

            guard let entryType = scanner.scanUpToString("{")?.lowercased().trimmingCharacters(in: .whitespaces) else { continue }
            _ = scanner.scanString("{")
            _ = scanner.scanUpToString(",") // citation key
            _ = scanner.scanString(",")

            var fields: [String: String] = [:]
            var braceDepth = 1

            while braceDepth > 0 && !scanner.isAtEnd {
                // Skip whitespace
                _ = scanner.scanCharacters(from: .whitespacesAndNewlines)

                if scanner.scanString("}") != nil {
                    braceDepth -= 1
                    continue
                }

                guard let key = scanner.scanUpToString("=")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { break }
                _ = scanner.scanString("=")
                _ = scanner.scanCharacters(from: .whitespaces)

                var value = ""
                if scanner.scanString("{") != nil {
                    var depth = 1
                    let maxDepth = 50
                    var chars: [Character] = []
                    while depth > 0 && !scanner.isAtEnd {
                        if let c = scanner.scanCharacter() {
                            if c == "{" {
                                depth += 1
                                if depth > maxDepth {
                                    // Abort: excessively nested braces — skip to end of value
                                    while depth > 0 && !scanner.isAtEnd {
                                        if let skip = scanner.scanCharacter() {
                                            if skip == "{" { depth += 1 }
                                            else if skip == "}" { depth -= 1 }
                                        }
                                    }
                                    break
                                }
                                chars.append(c)
                            }
                            else if c == "}" { depth -= 1; if depth > 0 { chars.append(c) } }
                            else { chars.append(c) }
                        }
                    }
                    value = String(chars)
                } else if scanner.scanString("\"") != nil {
                    value = scanner.scanUpToString("\"") ?? ""
                    _ = scanner.scanString("\"")
                } else {
                    value = scanner.scanUpToString(",") ?? ""
                }

                fields[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = scanner.scanString(",")
            }

            let refType: ReferenceType = {
                switch entryType {
                case "article": return .journalArticle
                case "book": return .book
                case "inbook", "incollection": return .bookSection
                case "inproceedings", "conference": return .conferencePaper
                case "phdthesis", "mastersthesis": return .thesis
                case "misc", "online": return .webpage
                case "techreport": return .report
                default: return .other
                }
            }()

            // Parse month to integer if present
            let issuedMonth = parseMonth(fields["month"])

            // Parse editors (BibTeX uses "and" separator like authors)
            let editorsJson = Reference.encodeNames(AuthorName.parseList(fields["editor"] ?? ""))

            // Genre for thesis types
            let genre: String? = {
                switch entryType {
                case "phdthesis": return "Doctoral dissertation"
                case "mastersthesis": return "Master's thesis"
                default: return fields["type"]
                }
            }()

            let ref = Reference(
                title: fields["title"] ?? "Untitled",
                authors: AuthorName.parseList(fields["author"] ?? ""),
                year: fields["year"].flatMap { Int($0) },
                journal: fields["journal"] ?? fields["booktitle"],
                volume: fields["volume"],
                issue: fields["number"],
                pages: fields["pages"],
                doi: fields["doi"],
                url: fields["url"],
                abstract: fields["abstract"],
                referenceType: refType,
                // Extended metadata (P0)
                publisher: fields["publisher"],
                publisherPlace: fields["address"],
                edition: fields["edition"],
                editors: editorsJson,
                isbn: fields["isbn"],
                issn: fields["issn"],
                issuedMonth: issuedMonth,
                // Extended metadata (P1)
                eventTitle: (refType == .conferencePaper) ? fields["booktitle"] : nil,
                eventPlace: fields["location"],
                genre: genre,
                number: fields["number"],
                collectionTitle: fields["series"],
                numberOfPages: fields["numpages"],
                // Extended metadata (P2)
                language: fields["language"]
            )
            references.append(ref)
        }

        return references
    }

    /// Parse BibTeX month field to integer (1-12)
    private static func parseMonth(_ raw: String?) -> Int? {
        guard let m = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !m.isEmpty else {
            return nil
        }
        // Numeric month
        if let n = Int(m), (1...12).contains(n) { return n }
        // BibTeX standard month abbreviations
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
                      "january": 1, "february": 2, "march": 3, "april": 4,
                      "june": 6, "july": 7, "august": 8, "september": 9,
                      "october": 10, "november": 11, "december": 12]
        return months[m]
    }
}
