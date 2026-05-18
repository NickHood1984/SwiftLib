import Foundation

extension MetadataFetcher {
    // MARK: - Identifier Detection

    public enum Identifier {
        case doi(String)
        case pmid(String)
        case arxiv(String)
        case isbn(String)
    }

    /// Parse raw text input and detect identifier type (priority: DOI > ISBN > arXiv > PMID)
    public static func extractIdentifier(from text: String) -> Identifier? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // DOI: 10.XXXX/... (most specific)
        if let doi = cleanDOI(trimmed) {
            return .doi(doi)
        }

        // ISBN: 10 or 13 digits, with checksum validation to avoid phone-number
        // style false positives (plain numeric strings are common).
        let digitsOnly = trimmed.replacingOccurrences(of: "[^0-9X]", with: "", options: .regularExpression)
        if digitsOnly.count == 13,
           digitsOnly.hasPrefix("978") || digitsOnly.hasPrefix("979"),
           isValidISBN13(digitsOnly) {
            return .isbn(digitsOnly)
        }
        if digitsOnly.count == 10, isValidISBN10(digitsOnly) {
            return .isbn(digitsOnly)
        }

        // arXiv: YYMM.NNNNN or category/NNNNNNN
        let arxivPatterns = [
            #"(\d{4}\.\d{4,5})(v\d+)?"#,
            #"([a-z\-]+/\d{7})"#,
            #"arXiv:(.+)"#
        ]
        for pattern in arxivPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                return .arxiv(String(trimmed[range]))
            }
        }

        // PMID: bare number. Modern PMIDs are 7–8 digits; we require ≥6 to avoid
        // grabbing arbitrary small integers (e.g. a random "42").
        if Int(trimmed) != nil, trimmed.count >= 6, trimmed.count <= 9 {
            return .pmid(trimmed)
        }

        return nil
    }

    /// Clean and extract DOI from various formats (URL, bare DOI, etc.).
    /// Preserve the input casing for display/storage; use `normalizedDOI`
    /// for cache keys and outbound requests.
    private static func cleanDOI(_ input: String) -> String? {
        var text = input
        // Handle doi.org URLs
        if let range = text.range(of: "doi.org/") {
            text = String(text[range.upperBound...])
        }
        // Handle "doi:" prefix
        if text.lowercased().hasPrefix("doi:") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        // Match DOI pattern: 10.XXXX/...
        let pattern = #"(10\.\d{4,}\/[^\s]+[^\s\.,;\]\)])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// Normalize a DOI for cache keys and outbound requests (lowercase, trimmed).
    static func normalizedDOI(_ doi: String) -> String {
        doi.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - ISBN Checksum Validation

    /// Validate ISBN-10 using the standard weighted-sum checksum.
    static func isValidISBN10(_ isbn: String) -> Bool {
        let digits = isbn.uppercased().unicodeScalars
        guard digits.count == 10 else { return false }
        var sum = 0
        for (i, scalar) in digits.enumerated() {
            let weight = 10 - i
            let digit: Int
            if scalar.value >= 0x30 && scalar.value <= 0x39 {
                digit = Int(scalar.value - 0x30)
            } else if i == 9 && scalar == "X" {
                digit = 10
            } else {
                return false
            }
            sum += digit * weight
        }
        return sum % 11 == 0
    }

    /// Validate ISBN-13 using the standard EAN-13 checksum.
    static func isValidISBN13(_ isbn: String) -> Bool {
        let digits = isbn.unicodeScalars
        guard digits.count == 13 else { return false }
        var sum = 0
        for (i, scalar) in digits.enumerated() {
            guard scalar.value >= 0x30 && scalar.value <= 0x39 else { return false }
            let digit = Int(scalar.value - 0x30)
            sum += (i % 2 == 0) ? digit : digit * 3
        }
        return sum % 10 == 0
    }

    /// Convert a valid ISBN-10 to its equivalent ISBN-13 (978 prefix).
    static func isbn10To13(_ isbn10: String) -> String? {
        guard isValidISBN10(isbn10) else { return nil }
        let prefix = "978" + String(isbn10.prefix(9))
        var sum = 0
        for (i, ch) in prefix.enumerated() {
            guard let digit = Int(String(ch)) else { return nil }
            sum += (i % 2 == 0) ? digit : digit * 3
        }
        let check = (10 - (sum % 10)) % 10
        return prefix + String(check)
    }

    /// Convert a valid 978-prefixed ISBN-13 to its ISBN-10 equivalent.
    static func isbn13To10(_ isbn13: String) -> String? {
        guard isValidISBN13(isbn13), isbn13.hasPrefix("978") else { return nil }
        let core = String(isbn13.dropFirst(3).prefix(9))
        var sum = 0
        for (i, ch) in core.enumerated() {
            guard let digit = Int(String(ch)) else { return nil }
            sum += digit * (10 - i)
        }
        let rem = sum % 11
        let checkValue = (11 - rem) % 11
        let check = checkValue == 10 ? "X" : String(checkValue)
        return core + check
    }

}
