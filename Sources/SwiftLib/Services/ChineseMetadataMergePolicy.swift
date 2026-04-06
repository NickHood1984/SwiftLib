import Foundation
import SwiftLibCore

enum ChineseMetadataMergePolicy {
    private static let chineseSources: Set<MetadataSource> = [.cnki, .wanfang, .vip]

    static func shouldPreferChineseText(
        seed: MetadataResolutionSeed? = nil,
        inputURL: URL? = nil,
        reference: Reference? = nil,
        existingReference: Reference? = nil
    ) -> Bool {
        if seedContainsChineseText(seed) {
            return true
        }

        if let url = preferredChineseSourceURL(seed: seed, inputURL: inputURL),
           chineseSources.contains(MetadataResolution.metadataSource(for: url.absoluteString, fallback: .translationServer)) {
            return true
        }

        if let source = reference?.metadataSource, chineseSources.contains(source) {
            return true
        }

        if let source = existingReference?.metadataSource, chineseSources.contains(source) {
            return true
        }

        if MetadataResolution.containsHanCharacters(reference?.title)
            || MetadataResolution.containsHanCharacters(reference?.journal)
            || MetadataResolution.containsHanCharacters(existingReference?.title)
            || MetadataResolution.containsHanCharacters(existingReference?.journal) {
            return true
        }

        return false
    }

    static func shouldAttemptChineseCorrection(
        seed: MetadataResolutionSeed? = nil,
        inputURL: URL? = nil,
        reference: Reference? = nil,
        existingReference: Reference? = nil
    ) -> Bool {
        shouldPreferChineseText(
            seed: seed,
            inputURL: inputURL,
            reference: reference,
            existingReference: existingReference
        )
    }

    static func merge(backend: Reference, chinese: Reference) -> Reference {
        var merged = MetadataResolution.mergeReference(primary: backend, fallback: chinese)
        applyChinesePreferredFields(from: chinese, to: &merged)
        return merged
    }

    static func mergeResolvedChineseReference(_ chinese: Reference, fallback: Reference) -> Reference {
        var merged = MetadataResolution.mergeReference(primary: chinese, fallback: fallback)
        applyChinesePreferredFields(from: chinese, to: &merged)
        return merged
    }

    static func mergeRefreshedChineseReference(_ chinese: Reference, existing: Reference) -> Reference {
        var merged = MetadataResolution.mergeRefreshedReference(primary: chinese, existing: existing)
        applyChinesePreferredFields(from: chinese, to: &merged)
        return merged
    }

    private static func applyChinesePreferredFields(from chinese: Reference, to merged: inout Reference) {
        merged.title = preferredChineseText(chinese.title, fallback: merged.title) ?? merged.title
        merged.journal = preferredChineseText(chinese.journal, fallback: merged.journal)
        merged.abstract = preferredChineseText(chinese.abstract, fallback: merged.abstract)
        merged.publisher = preferredChineseText(chinese.publisher, fallback: merged.publisher)

        if let chineseLanguage = chinese.language?.swiftlib_nilIfBlank {
            merged.language = chineseLanguage
        } else if MetadataResolution.containsHanCharacters(chinese.title) || MetadataResolution.containsHanCharacters(chinese.journal) {
            merged.language = "zh-CN"
        }

        if !chinese.authors.isEmpty {
            merged.authors = mergeAuthors(primary: chinese.authors, secondary: merged.authors)
        }

        if let source = chinese.metadataSource ?? sourceFromChineseReference(chinese) {
            merged.metadataSource = source
        }

        if let siteName = chinese.siteName?.swiftlib_nilIfBlank {
            merged.siteName = siteName
        } else if let source = merged.metadataSource {
            merged.siteName = source.displayName
        }
    }

    /// Merge author lists intelligently: prefer Chinese (primary) authors as the base,
    /// then append any unique authors from the secondary list that aren't already present.
    private static func mergeAuthors(primary: [AuthorName], secondary: [AuthorName]) -> [AuthorName] {
        guard !secondary.isEmpty else { return primary }
        guard !primary.isEmpty else { return secondary }

        var merged = primary
        let primaryNormalized = Set(primary.map { normalizeAuthorForComparison($0) })

        for author in secondary {
            let normalized = normalizeAuthorForComparison(author)
            if !primaryNormalized.contains(normalized) {
                merged.append(author)
            }
        }
        return merged
    }

    /// Normalize an author name for deduplication comparison.
    /// Lowercases, trims whitespace, and strips punctuation so that
    /// "Wu, H." matches "Wu, Haoyun" by family name.
    private static func normalizeAuthorForComparison(_ author: AuthorName) -> String {
        let family = author.family.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // For dedup purposes, use family name only — given names vary in completeness
        // across sources (e.g. "H." vs "Haoyun" vs "浩云")
        return family
    }

    private static func sourceFromChineseReference(_ reference: Reference) -> MetadataSource? {
        let sourceFromURL = MetadataResolution.metadataSource(for: reference.url, fallback: .translationServer)
        return chineseSources.contains(sourceFromURL) ? sourceFromURL : nil
    }

    private static func preferredChineseText(_ preferred: String?, fallback: String?) -> String? {
        let preferredTrimmed = preferred?.swiftlib_nilIfBlank
        let fallbackTrimmed = fallback?.swiftlib_nilIfBlank

        if let preferredTrimmed, MetadataResolution.containsHanCharacters(preferredTrimmed) {
            return preferredTrimmed
        }
        if let preferredTrimmed, fallbackTrimmed == nil {
            return preferredTrimmed
        }
        return fallbackTrimmed ?? preferredTrimmed
    }

    private static func preferredChineseSourceURL(seed: MetadataResolutionSeed?, inputURL: URL?) -> URL? {
        if let inputURL {
            return inputURL
        }
        guard let raw = seed?.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    private static func seedContainsChineseText(_ seed: MetadataResolutionSeed?) -> Bool {
        guard let seed else { return false }
        return seed.languageHint == .chinese
            || MetadataResolution.containsHanCharacters(seed.title)
            || MetadataResolution.containsHanCharacters(seed.fileName)
            || MetadataResolution.containsHanCharacters(seed.journal)
            || MetadataResolution.containsHanCharacters(seed.publisher)
            || MetadataResolution.containsHanCharacters(seed.textSnippet)
    }
}
