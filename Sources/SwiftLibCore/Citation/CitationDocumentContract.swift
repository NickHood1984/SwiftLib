import Foundation

public struct CitationDocumentItemOption: Codable, Equatable, Sendable {
    public var itemRef: String?
    public var refId: String?
    public var id: String?
    public var locator: String?
    public var label: String?
    public var prefix: String?
    public var suffix: String?
    public var suppressAuthor: Bool
    public var authorOnly: Bool

    public init(
        itemRef: String? = nil,
        refId: String? = nil,
        id: String? = nil,
        locator: String? = nil,
        label: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        suppressAuthor: Bool = false,
        authorOnly: Bool = false
    ) {
        self.itemRef = itemRef
        self.refId = refId
        self.id = id
        self.locator = locator
        self.label = label
        self.prefix = prefix
        self.suffix = suffix
        self.suppressAuthor = suppressAuthor
        self.authorOnly = authorOnly
    }

    public var resolvedItemID: String? {
        if let itemRef, itemRef.hasPrefix("lib:") {
            return String(itemRef.dropFirst(4)).swiftlib_nilIfBlank
        }
        return refId?.swiftlib_nilIfBlank ?? id?.swiftlib_nilIfBlank
    }

    public enum CodingKeys: String, CodingKey {
        case itemRef
        case refId
        case id
        case locator
        case label
        case prefix
        case suffix
        case suppressAuthor
        case suppressAuthorCSL = "suppress-author"
        case authorOnly
        case authorOnlyCSL = "author-only"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemRef = try container.decodeIfPresent(String.self, forKey: .itemRef)
        refId = Self.decodeFlexibleString(container, key: .refId)
        id = Self.decodeFlexibleString(container, key: .id)
        locator = try container.decodeIfPresent(String.self, forKey: .locator)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        suffix = try container.decodeIfPresent(String.self, forKey: .suffix)
        let suppressAuthorCSL = try container.decodeIfPresent(Bool.self, forKey: .suppressAuthorCSL)
        let suppressAuthorCamel = try container.decodeIfPresent(Bool.self, forKey: .suppressAuthor)
        suppressAuthor = suppressAuthorCSL ?? suppressAuthorCamel ?? false

        let authorOnlyCSL = try container.decodeIfPresent(Bool.self, forKey: .authorOnlyCSL)
        let authorOnlyCamel = try container.decodeIfPresent(Bool.self, forKey: .authorOnly)
        authorOnly = authorOnlyCSL ?? authorOnlyCamel ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(itemRef, forKey: .itemRef)
        try container.encodeIfPresent(refId, forKey: .refId)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(locator, forKey: .locator)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(prefix, forKey: .prefix)
        try container.encodeIfPresent(suffix, forKey: .suffix)
        if suppressAuthor {
            try container.encode(true, forKey: .suppressAuthorCSL)
        }
        if authorOnly {
            try container.encode(true, forKey: .authorOnlyCSL)
        }
    }

    public func citeprocJSONObject() -> [String: Any] {
        var object: [String: Any] = [:]
        if let resolvedItemID { object["id"] = resolvedItemID }
        if let locator = locator?.swiftlib_nilIfBlank { object["locator"] = locator }
        if let label = label?.swiftlib_nilIfBlank { object["label"] = label }
        if let prefix = prefix?.swiftlib_nilIfBlank { object["prefix"] = prefix }
        if let suffix = suffix?.swiftlib_nilIfBlank { object["suffix"] = suffix }
        if suppressAuthor { object["suppress-author"] = true }
        if authorOnly { object["author-only"] = true }
        return object
    }

    public static func normalizedJSONObjects(from rawItems: [[String: Any]]?) -> [[String: Any]]? {
        guard let rawItems, !rawItems.isEmpty else { return nil }
        let normalized = rawItems.compactMap { raw -> [String: Any]? in
            if let option = decode(fromJSONObject: raw) {
                let object = option.citeprocJSONObject()
                return object["id"] == nil ? nil : object
            }
            var merged = raw
            if let itemRef = raw["itemRef"] as? String, itemRef.hasPrefix("lib:") {
                merged["id"] = String(itemRef.dropFirst(4))
            } else if let refId = raw["refId"] {
                merged["id"] = String(describing: refId)
            }
            if let suppress = raw["suppressAuthor"] as? Bool, suppress {
                merged["suppress-author"] = true
            }
            if let authorOnly = raw["authorOnly"] as? Bool, authorOnly {
                merged["author-only"] = true
            }
            merged.removeValue(forKey: "itemRef")
            merged.removeValue(forKey: "refId")
            merged.removeValue(forKey: "suppressAuthor")
            merged.removeValue(forKey: "authorOnly")
            return merged["id"] == nil ? nil : merged
        }
        return normalized.isEmpty ? nil : normalized
    }

    public static func decodeArray(fromJSONObject raw: Any?) -> [CitationDocumentItemOption]? {
        guard let raw else { return nil }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode([CitationDocumentItemOption].self, from: data) else {
            return nil
        }
        return decoded
    }

    public static func decode(fromJSONObject raw: [String: Any]) -> CitationDocumentItemOption? {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode(CitationDocumentItemOption.self, from: data) else {
            return nil
        }
        return decoded
    }

    private static func decodeFlexibleString<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        key: Key
    ) -> String? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let int = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(int)
        }
        if let int64 = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return String(int64)
        }
        return nil
    }
}

public struct CitationDocumentCluster: Equatable, Sendable {
    public var id: String
    public var itemIDs: [String]
    public var position: Int
    public var citationItems: [CitationDocumentItemOption]?

    public init(
        id: String,
        itemIDs: [String],
        position: Int,
        citationItems: [CitationDocumentItemOption]? = nil
    ) {
        self.id = id
        self.itemIDs = itemIDs
        self.position = position
        self.citationItems = citationItems
    }

    public var citeprocCitationItems: [[String: Any]]? {
        guard let citationItems, !citationItems.isEmpty else { return nil }
        let items = citationItems.compactMap { option -> [String: Any]? in
            let object = option.citeprocJSONObject()
            return object["id"] == nil ? nil : object
        }
        return items.isEmpty ? nil : items
    }
}
