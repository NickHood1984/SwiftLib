import Foundation

/// High-performance RIS format parser
public enum RISImporter {
    public static func parse(_ content: String) -> [Reference] {
        var references: [Reference] = []
        references.reserveCapacity(1000)

        var currentFields: [String: [String]] = [:]
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 2 else { continue }

            let tagEnd = cleaned.index(cleaned.startIndex, offsetBy: 2)
            let tag = String(cleaned[..<tagEnd]).uppercased()
            let remainder = cleaned[tagEnd...]
            guard let dashIndex = remainder.firstIndex(of: "-") else { continue }

            let separator = remainder[..<dashIndex]
            guard separator.allSatisfy(\.isWhitespace) else { continue }

            let valueStart = cleaned.index(after: dashIndex)
            let value = String(cleaned[valueStart...]).trimmingCharacters(in: .whitespaces)

            if tag == "ER" {
                if !currentFields.isEmpty {
                    references.append(buildReference(from: currentFields))
                    currentFields = [:]
                }
                continue
            }

            currentFields[tag, default: []].append(value)
        }

        if !currentFields.isEmpty {
            references.append(buildReference(from: currentFields))
        }

        return references
    }

    private static func buildReference(from fields: [String: [String]]) -> Reference {
        let risType = fields["TY"]?.first ?? ""

        let refType: ReferenceType = {
            switch risType {
            case "JOUR": return .journalArticle
            case "BOOK": return .book
            case "CHAP": return .bookSection
            case "CONF", "CPAPER": return .conferencePaper
            case "THES": return .thesis
            case "ELEC": return .webpage
            case "RPRT": return .report
            default: return .other
            }
        }()

        let authors = (fields["AU"] ?? fields["A1"] ?? []).map { AuthorName.parse($0) }
        let year = (fields["PY"] ?? fields["Y1"])?.first.flatMap { Int($0.prefix(4)) }

        // Parse editors (A2/ED tags)
        let editorNames = (fields["A2"] ?? fields["ED"] ?? []).map { AuthorName.parse($0) }
        let editorsJson = Reference.encodeNames(editorNames)

        // Parse translators (A4 tag)
        let translatorNames = (fields["A4"] ?? []).map { AuthorName.parse($0) }
        let translatorsJson = Reference.encodeNames(translatorNames)

        // Determine ISBN vs ISSN from SN tag based on reference type
        let snValue = fields["SN"]?.first
        let isbn: String? = (refType == .book || refType == .bookSection) ? snValue : nil
        let issn: String? = (refType == .journalArticle) ? snValue : nil

        // Parse month from date fields
        let issuedMonth = parseMonthFromRISDate((fields["DA"] ?? fields["Y1"])?.first)

        // Genre for thesis
        let genre: String? = {
            if refType == .thesis {
                return fields["M3"]?.first ?? "Thesis"
            }
            return nil
        }()

        // Accessed date (Y2 tag in RIS)
        let accessedDate = fields["Y2"]?.first

        return Reference(
            title: (fields["TI"] ?? fields["T1"])?.first ?? "Untitled",
            authors: authors,
            year: year,
            journal: (fields["JO"] ?? fields["JF"] ?? fields["T2"])?.first,
            volume: fields["VL"]?.first,
            issue: fields["IS"]?.first,
            pages: [fields["SP"]?.first, fields["EP"]?.first].compactMap { $0 }.joined(separator: "-"),
            doi: fields["DO"]?.first,
            url: fields["UR"]?.first,
            abstract: (fields["AB"] ?? fields["N2"])?.first,
            referenceType: refType,
            // Extended metadata (P0)
            publisher: fields["PB"]?.first,
            publisherPlace: fields["CY"]?.first,
            edition: fields["ET"]?.first,
            editors: editorsJson,
            isbn: isbn,
            issn: issn,
            accessedDate: accessedDate,
            issuedMonth: issuedMonth,
            // Extended metadata (P1)
            translators: translatorsJson,
            eventTitle: (refType == .conferencePaper) ? (fields["T2"] ?? fields["BT"])?.first : nil,
            eventPlace: fields["CY"]?.first,
            genre: genre,
            number: fields["M1"]?.first,
            collectionTitle: fields["T3"]?.first,
            numberOfPages: nil,
            // Extended metadata (P2)
            language: fields["LA"]?.first
        )
    }

    /// Parse month from RIS date format (YYYY/MM/DD or YYYY/MM)
    private static func parseMonthFromRISDate(_ dateStr: String?) -> Int? {
        guard let d = dateStr, !d.isEmpty else { return nil }
        let parts = d.split(separator: "/")
        guard parts.count >= 2, let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        return month
    }
}
