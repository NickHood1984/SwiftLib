import Foundation

// MARK: - Deprecated: Native Fallback Renderer
//
// WordCitationRenderer is a native Swift fallback renderer that was previously
// used as a backup when citeproc-js was unavailable. It is NO LONGER used for
// generating official citation text in the Word add-in pipeline.
//
// The canonical renderer is exclusively citeproc-js (via CiteprocJSCorePool).
// When citeproc-js fails, the system returns an error and preserves the document
// as-is — it does NOT fall back to this renderer.
//
// This file is retained only because it is referenced by unit tests
// (CitationAndRenderingTests.swift). Do not call WordCitationRenderer.render()
// from any production code path.

public struct WordCitationGroup: Identifiable, Hashable {
    public let citationID: String
    public let start: Int
    public let end: Int
    public let referenceIDs: [Int64]
    public let styleID: String

    public var id: String { citationID }

    public init(citationID: String, start: Int, end: Int, referenceIDs: [Int64], styleID: String) {
        self.citationID = citationID
        self.start = start
        self.end = end
        self.referenceIDs = referenceIDs
        self.styleID = styleID
    }
}

public struct WordRenderedDocument {
    public let citationTexts: [String: String]
    public let superscriptCitationBookmarkNames: Set<String>
    public let bibliographyText: String
    public let citationKind: CitationKind

    public init(citationTexts: [String: String], superscriptCitationBookmarkNames: Set<String>, bibliographyText: String, citationKind: CitationKind) {
        self.citationTexts = citationTexts
        self.superscriptCitationBookmarkNames = superscriptCitationBookmarkNames
        self.bibliographyText = bibliographyText
        self.citationKind = citationKind
    }
}

public enum WordCitationRenderer {
    public static func render(groups: [WordCitationGroup], referencesByID: [Int64: Reference], styleID: String) -> WordRenderedDocument {
        let citationKind = CSLManager.shared.citationKind(for: styleID)
        switch citationKind {
        case .numeric:
            return renderNumeric(groups: groups, referencesByID: referencesByID, styleID: styleID)
        case .authorDate, .note:
            return renderTextual(groups: groups, referencesByID: referencesByID, styleID: styleID, citationKind: citationKind)
        }
    }

    private static func renderTextual(
        groups: [WordCitationGroup],
        referencesByID: [Int64: Reference],
        styleID: String,
        citationKind: CitationKind
    ) -> WordRenderedDocument {
        var citationTexts: [String: String] = [:]
        var bibliographyRefs: [Reference] = []
        var seenReferenceIDs = Set<Int64>()

        for group in groups.sorted(by: { $0.start < $1.start }) {
            let refs = references(for: group.referenceIDs, referencesByID: referencesByID)
            citationTexts[group.citationID] = CSLManager.shared.formatCitation(refs, style: styleID)

            for ref in refs {
                guard let id = ref.id, seenReferenceIDs.insert(id).inserted else { continue }
                bibliographyRefs.append(ref)
            }
        }

        let entries = bibliographyRefs.map { CSLManager.shared.formatBibliography($0, style: styleID) }
        return WordRenderedDocument(
            citationTexts: citationTexts,
            superscriptCitationBookmarkNames: [],
            bibliographyText: bibliographyBlock(entries: entries),
            citationKind: citationKind
        )
    }

    private static func renderNumeric(
        groups: [WordCitationGroup],
        referencesByID: [Int64: Reference],
        styleID: String
    ) -> WordRenderedDocument {
        var numbering: [Int64: Int] = [:]
        var orderedReferences: [Reference] = []
        var nextNumber = 1

        for group in groups.sorted(by: { $0.start < $1.start }) {
            for ref in references(for: group.referenceIDs, referencesByID: referencesByID) {
                guard let id = ref.id else { continue }
                if numbering[id] == nil {
                    numbering[id] = nextNumber
                    nextNumber += 1
                    orderedReferences.append(ref)
                }
            }
        }

        var citationTexts: [String: String] = [:]
        var superscriptCitationBookmarkNames = Set<String>()
        for group in groups {
            let numbers = references(for: group.referenceIDs, referencesByID: referencesByID)
                .compactMap(\.id)
                .compactMap { numbering[$0] }
            let citationText = CitationFormatter.formatNumericInlineCitation(numbers: numbers, style: styleID)
            citationTexts[group.citationID] = citationText
            if CSLManager.shared.shouldSuperscriptNumericCitation(styleID: styleID, citationText: citationText) {
                superscriptCitationBookmarkNames.insert(group.citationID)
            }
        }

        let entries = orderedReferences.compactMap { ref -> String? in
            guard let id = ref.id, let number = numbering[id] else { return nil }
            let base = CSLManager.shared.formatBibliography(ref, style: styleID)
            return CitationFormatter.formatNumericBibliographyEntry(base, number: number, style: styleID)
        }

        return WordRenderedDocument(
            citationTexts: citationTexts,
            superscriptCitationBookmarkNames: superscriptCitationBookmarkNames,
            bibliographyText: bibliographyBlock(entries: entries),
            citationKind: .numeric
        )
    }

    private static func references(for ids: [Int64], referencesByID: [Int64: Reference]) -> [Reference] {
        orderedUnique(ids).compactMap { referencesByID[$0] }
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func bibliographyBlock(entries: [String]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.joined(separator: "\n")
    }
}
