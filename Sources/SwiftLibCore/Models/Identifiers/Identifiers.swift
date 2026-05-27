import Foundation

// ---------------------------------------------------------------------------
// Identifier value objects
//
// These types encapsulate the normalization and validation rules for the
// scholarly identifiers used in SwiftLib. Each type:
//
//   1. Parses / normalises raw input strings
//   2. Provides a canonical string for deduplication / comparison
//   3. Provides the display form shown in UI
//   4. Provides the form expected by CSL-JSON / citeproc-js
//
// Reference.doi / isbn / issn etc. remain `String?` for DB compatibility,
// but all code that interprets them should route through these types.
// ---------------------------------------------------------------------------

// MARK: - DOI

/// Digital Object Identifier.
///
/// Canonical form: lowercase DOI suffix only, e.g. "10.1103/physrevlett.132.041601"
/// CSL-JSON form:  bare DOI without https://doi.org/ prefix (same as canonical)
/// Display form:   "https://doi.org/10.1103/PhysRevLett.132.041601" (original case)
public struct DOIIdentifier: Equatable, Hashable, Sendable, CustomStringConvertible {

    /// The normalised (lowercase, prefix-stripped) DOI string.
    public let canonical: String
    /// The original raw string with case and prefix preserved for display.
    public let raw: String

    /// Returns nil if the input does not look like a DOI.
    public init?(_ raw: String) {
        let stripped = Self.strip(raw)
        guard !stripped.isEmpty, stripped.hasPrefix("10.") else { return nil }
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canonical = stripped.lowercased()
    }

    /// Bare DOI string for CSL-JSON (no "https://doi.org/" prefix).
    public var cslString: String { stripped }

    /// Full HTTPS URL for display and linking.
    public var displayURL: String { "https://doi.org/\(stripped)" }

    /// Bare DOI with original case.
    public var stripped: String { Self.strip(raw) }

    public var description: String { cslString }

    // MARK: - Normalization

    /// Strip common prefixes and return the bare DOI (preserving original case).
    public static func strip(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove URL prefix variants
        let prefixes = [
            "https://doi.org/",
            "http://doi.org/",
            "https://dx.doi.org/",
            "http://dx.doi.org/",
            "https://doi.crossref.org/",
            "doi:",
            "DOI:",
        ]
        for prefix in prefixes {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        // Strip URL fragment (#…) and query (?) that shouldn't be in DOIs
        if let fragIdx = s.firstIndex(of: "#") { s = String(s[..<fragIdx]) }
        // Percent-decode common encoded chars (%2F → /)
        s = s.removingPercentEncoding ?? s
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Canonical lowercase form for database dedup column.
    public static func canonical(for raw: String) -> String? {
        guard let doi = DOIIdentifier(raw) else { return nil }
        return doi.canonical
    }
}

// MARK: - ISBN

/// International Standard Book Number (ISBN-10 or ISBN-13).
///
/// Canonical form: digits only (+ X for ISBN-10 check digit), uppercase.
public struct ISBNIdentifier: Equatable, Hashable, Sendable, CustomStringConvertible {

    public let digits: String   // "0262046305" or "9780262046305"
    public let raw: String

    /// Returns nil if the input cannot be reduced to a valid ISBN-10 or ISBN-13.
    public init?(_ raw: String) {
        let normalized = Self.normalize(raw)
        guard normalized.count == 10 || normalized.count == 13 else { return nil }
        self.digits = normalized
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hyphenated display form (simple grouping: prefix-group-publisher-title-check).
    /// For display only; exact hyphenation positions depend on ISBN registration agency.
    public var display: String { raw }

    public var description: String { digits }

    /// Canonical uppercase form for DB dedup column.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            .uppercased()
    }
}

// MARK: - ISSN

/// International Standard Serial Number.
/// Canonical form: 8 digits (no hyphen), uppercase.
public struct ISSNIdentifier: Equatable, Hashable, Sendable, CustomStringConvertible {

    public let digits: String   // "00319007"
    public let raw: String

    public init?(_ raw: String) {
        let normalized = Self.normalize(raw)
        guard normalized.count == 8 else { return nil }
        self.digits = normalized
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Formatted "XXXX-XXXX" display form.
    public var hyphenated: String {
        guard digits.count == 8 else { return digits }
        return "\(digits.prefix(4))-\(digits.suffix(4))"
    }

    public var description: String { hyphenated }

    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            .uppercased()
    }
}

// MARK: - PMID

/// PubMed article identifier.
/// Canonical form: numeric string, no leading zeros.
public struct PMIDIdentifier: Equatable, Hashable, Sendable, CustomStringConvertible {

    public let value: String    // "12345678"
    public let raw: String

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip "PMID:" prefix
        if s.uppercased().hasPrefix("PMID:") { s = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        guard !s.isEmpty, s.allSatisfy(\.isNumber) else { return nil }
        // Strip leading zeros
        let normalized = s.drop { $0 == "0" }
        self.value = normalized.isEmpty ? "0" : String(normalized)
        self.raw = s
    }

    public var description: String { value }

    public static func normalize(_ raw: String) -> String? {
        PMIDIdentifier(raw)?.value
    }
}

// MARK: - PMCID

/// PubMed Central article identifier.
/// Canonical form: "PMC" + digits uppercase.
public struct PMCIDIdentifier: Equatable, Hashable, Sendable, CustomStringConvertible {

    public let value: String    // "PMC1234567"
    public let raw: String

    public init?(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.hasPrefix("PMC"), s.dropFirst(3).allSatisfy(\.isNumber), s.count > 3 else { return nil }
        self.value = s
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var description: String { value }

    public static func normalize(_ raw: String) -> String? {
        PMCIDIdentifier(raw)?.value
    }
}

// MARK: - ArxivID

/// arXiv preprint identifier.
/// Two common formats:
///   - New: "2401.12345" or "2401.12345v2"
///   - Old: "hep-th/9901001"
public struct ArxivIDIdentifier: Equatable, Hashable, Sendable, CustomStringConvertible {

    public let value: String    // bare ID without "arXiv:" prefix
    public let raw: String

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common prefixes
        for prefix in ["arXiv:", "arxiv:", "https://arxiv.org/abs/", "http://arxiv.org/abs/"] {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Basic pattern check
        let newStyle = #"^\d{4}\.\d{4,5}(v\d+)?$"#
        let oldStyle = #"^[a-z\-]+\/\d{7}(v\d+)?$"#
        let isNew = (try? NSRegularExpression(pattern: newStyle))?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        let isOld = (try? NSRegularExpression(pattern: oldStyle))?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        guard isNew || isOld else { return nil }
        self.value = s
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var description: String { value }

    /// Full arXiv abstract URL.
    public var abstractURL: String { "https://arxiv.org/abs/\(value)" }

    /// CSL DOI equivalent (arXiv provides DOIs for newer papers, but for legacy use the arXiv URL).
    public var cslNote: String { "arXiv:\(value)" }
}

// MARK: - Reference convenience accessors

extension Reference {

    /// Parsed DOI value object. Returns nil if the stored doi string is not a valid DOI.
    public var parsedDOI: DOIIdentifier? {
        doi.flatMap { DOIIdentifier($0) }
    }

    /// Parsed ISBN value object.
    public var parsedISBN: ISBNIdentifier? {
        isbn.flatMap { ISBNIdentifier($0) }
    }

    /// Parsed ISSN value object.
    public var parsedISSN: ISSNIdentifier? {
        issn.flatMap { ISSNIdentifier($0) }
    }

    /// Parsed PMID value object.
    public var parsedPMID: PMIDIdentifier? {
        pmid.flatMap { PMIDIdentifier($0) }
    }

    /// Parsed PMCID value object.
    public var parsedPMCID: PMCIDIdentifier? {
        pmcid.flatMap { PMCIDIdentifier($0) }
    }
}
