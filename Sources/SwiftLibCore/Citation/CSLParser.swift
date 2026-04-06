import Foundation

public enum CitationKind: String, Codable {
    case numeric
    case authorDate
    case note
}

/// CSL (Citation Style Language) file parser
/// Parses .csl XML files (Citation Style Language)
public struct CSLStyle: Identifiable, Codable {
    public let id: String
    public var title: String
    public var isDependent: Bool = false
    public var parentURL: String?
    public var citationKind: CitationKind = .authorDate

    // Citation (inline) config
    public var citationLayout: CSLLayout
    public var citationSort: [CSLSortKey]

    // Bibliography config
    public var bibliographyLayout: CSLLayout
    public var bibliographySort: [CSLSortKey]

    // Macros
    public var macros: [String: [CSLNode]]

    // Global options
    public var etAlMin: Int
    public var etAlUseFirst: Int
    public var etAlSubsequentMin: Int?
    public var etAlSubsequentUseFirst: Int?
    public var disambiguateAddYearSuffix: Bool
}

public struct CSLLayout: Codable {
    public var prefix: String
    public var suffix: String
    public var delimiter: String
    public var verticalAlign: String?
    public var fontStyle: String?
    public var fontWeight: String?
    public var fontVariant: String?
    public var textDecoration: String?
    public var nodes: [CSLNode]
}

public struct CSLSortKey: Codable {
    public var variable: String
    public var sort: String // "ascending" or "descending"
}

/// CSL formatting node — represents one formatting instruction
public indirect enum CSLNode: Codable {
    case text(variable: String?, macro: String?, value: String?, prefix: String, suffix: String, fontStyle: String?)
    case names(variable: String, nameForm: NameForm, delimiter: String, etAlMin: Int?, etAlUseFirst: Int?, prefix: String, suffix: String)
    case date(variable: String, form: String, dateParts: [CSLDatePart], prefix: String, suffix: String)
    case group(delimiter: String, prefix: String, suffix: String, children: [CSLNode])
    case label(variable: String, form: String, prefix: String, suffix: String)
    case number(variable: String, prefix: String, suffix: String)
    case choose(conditions: [CSLCondition])

    public struct NameForm: Codable {
        public var form: String // "long", "short"
        public var nameAsSortOrder: String? // "first", "all"
        public var sortSeparator: String
        public var delimiter: String
        public var initializeWith: String?
        public var and: String? // "text", "symbol"
    }

    public struct CSLDatePart: Codable {
        public var name: String // "year", "month", "day"
        public var form: String? // "long", "short", "numeric"
    }

    public struct CSLCondition: Codable {
        public var type: String? // journal-article, book, etc.
        public var variable: String?
        public var isNumeric: String?
        public var match: String // "any", "all", "none"
        public var children: [CSLNode]
    }
}

// MARK: - CSL XML Parser

public final class CSLXMLParser: NSObject, XMLParserDelegate {
    private var style: CSLStyle?
    private var elementStack: [String] = []
    private var currentText = ""

    // Parsing state
    private var macros: [String: [CSLNode]] = [:]
    private var currentMacroName: String?
    private var currentMacroNodes: [CSLNode] = []

    private var citationNodes: [CSLNode] = []
    private var bibliographyNodes: [CSLNode] = []
    private var citationSort: [CSLSortKey] = []
    private var bibliographySort: [CSLSortKey] = []
    private var citationLayout = CSLLayout(
        prefix: "(",
        suffix: ")",
        delimiter: "; ",
        verticalAlign: nil,
        fontStyle: nil,
        fontWeight: nil,
        fontVariant: nil,
        textDecoration: nil,
        nodes: []
    )
    private var bibliographyLayout = CSLLayout(
        prefix: "",
        suffix: "",
        delimiter: "\n",
        verticalAlign: nil,
        fontStyle: nil,
        fontWeight: nil,
        fontVariant: nil,
        textDecoration: nil,
        nodes: []
    )

    private var nodeStack: [[CSLNode]] = []
    private var currentNodes: [CSLNode] = []

    private var conditionStack: [[CSLNode.CSLCondition]] = []
    private var pendingConditionAttrs: [String: String] = [:]

    private var groupAttrStack: [(delimiter: String, prefix: String, suffix: String)] = []

    private var inCitation = false
    private var inBibliography = false
    private var inMacro = false
    private var inSort = false

    // Style metadata
    private var styleId = ""
    private var styleTitle = ""
    private var styleCitationKind: CitationKind = .authorDate
    private var etAlMin = 4
    private var etAlUseFirst = 1

    public func parse(data: Data) -> CSLStyle? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return style
    }

    public func parse(url: URL) -> CSLStyle? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    // MARK: - XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String] = [:]) {
        elementStack.append(el)
        currentText = ""

        switch el {
        case "style":
            break

        case "category":
            if let format = attrs["citation-format"] {
                styleCitationKind = CitationKind(cslCitationFormat: format)
            }

        case "citation":
            inCitation = true
            if let min = attrs["et-al-min"].flatMap({ Int($0) }) { etAlMin = min }
            if let first = attrs["et-al-use-first"].flatMap({ Int($0) }) { etAlUseFirst = first }

        case "bibliography":
            inBibliography = true

        case "macro":
            inMacro = true
            currentMacroName = attrs["name"]
            currentNodes = []

        case "layout":
            if inCitation {
                citationLayout.prefix = attrs["prefix"] ?? "("
                citationLayout.suffix = attrs["suffix"] ?? ")"
                citationLayout.delimiter = attrs["delimiter"] ?? "; "
                citationLayout.verticalAlign = attrs["vertical-align"]
                citationLayout.fontStyle = attrs["font-style"]
                citationLayout.fontWeight = attrs["font-weight"]
                citationLayout.fontVariant = attrs["font-variant"]
                citationLayout.textDecoration = attrs["text-decoration"]
            } else if inBibliography {
                bibliographyLayout.prefix = attrs["prefix"] ?? ""
                bibliographyLayout.suffix = attrs["suffix"] ?? ""
                bibliographyLayout.delimiter = attrs["delimiter"] ?? "\n"
                bibliographyLayout.verticalAlign = attrs["vertical-align"]
                bibliographyLayout.fontStyle = attrs["font-style"]
                bibliographyLayout.fontWeight = attrs["font-weight"]
                bibliographyLayout.fontVariant = attrs["font-variant"]
                bibliographyLayout.textDecoration = attrs["text-decoration"]
            }
            currentNodes = []

        case "sort":
            inSort = true

        case "key":
            if inSort {
                let key = CSLSortKey(
                    variable: attrs["variable"] ?? attrs["macro"] ?? "",
                    sort: attrs["sort"] ?? "ascending"
                )
                if inCitation { citationSort.append(key) }
                else if inBibliography { bibliographySort.append(key) }
            }

        case "text":
            let node = CSLNode.text(
                variable: attrs["variable"],
                macro: attrs["macro"],
                value: attrs["value"],
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? "",
                fontStyle: attrs["font-style"]
            )
            currentNodes.append(node)

        case "names":
            let nameForm = CSLNode.NameForm(
                form: attrs["form"] ?? "long",
                nameAsSortOrder: attrs["name-as-sort-order"],
                sortSeparator: attrs["sort-separator"] ?? ", ",
                delimiter: attrs["delimiter"] ?? ", ",
                initializeWith: attrs["initialize-with"],
                and: attrs["and"]
            )
            let node = CSLNode.names(
                variable: attrs["variable"] ?? "author",
                nameForm: nameForm,
                delimiter: attrs["delimiter"] ?? ", ",
                etAlMin: attrs["et-al-min"].flatMap { Int($0) },
                etAlUseFirst: attrs["et-al-use-first"].flatMap { Int($0) },
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? ""
            )
            currentNodes.append(node)

        case "name":
            // Update the last names node with name formatting
            if let last = currentNodes.last, case .names(let v, _, let d, let eam, let eauf, let p, let s) = last {
                let nameForm = CSLNode.NameForm(
                    form: attrs["form"] ?? "long",
                    nameAsSortOrder: attrs["name-as-sort-order"],
                    sortSeparator: attrs["sort-separator"] ?? ", ",
                    delimiter: attrs["delimiter"] ?? ", ",
                    initializeWith: attrs["initialize-with"],
                    and: attrs["and"]
                )
                currentNodes[currentNodes.count - 1] = .names(
                    variable: v, nameForm: nameForm, delimiter: d,
                    etAlMin: eam, etAlUseFirst: eauf, prefix: p, suffix: s
                )
            }

        case "date":
            let node = CSLNode.date(
                variable: attrs["variable"] ?? "issued",
                form: attrs["form"] ?? "long",
                dateParts: [],
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? ""
            )
            currentNodes.append(node)
            nodeStack.append(currentNodes)
            currentNodes = []

        case "date-part":
            let name = attrs["name"] ?? ""
            let form = attrs["form"]
            let node = CSLNode.text(
                variable: name,
                macro: nil,
                value: nil,
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? "",
                fontStyle: nil
            )
            currentNodes.append(node)
            _ = form

        case "group":
            groupAttrStack.append((
                delimiter: attrs["delimiter"] ?? " ",
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? ""
            ))
            nodeStack.append(currentNodes)
            currentNodes = []

        case "choose":
            conditionStack.append([])
            nodeStack.append(currentNodes)
            currentNodes = []

        case "if", "else-if":
            pendingConditionAttrs = attrs
            nodeStack.append(currentNodes)
            currentNodes = []

        case "else":
            pendingConditionAttrs = ["match": "else"]
            nodeStack.append(currentNodes)
            currentNodes = []

        case "label":
            let node = CSLNode.label(
                variable: attrs["variable"] ?? "",
                form: attrs["form"] ?? "long",
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? ""
            )
            currentNodes.append(node)

        case "number":
            let node = CSLNode.number(
                variable: attrs["variable"] ?? "",
                prefix: attrs["prefix"] ?? "",
                suffix: attrs["suffix"] ?? ""
            )
            currentNodes.append(node)

        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    public func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch el {
        case "title":
            if elementStack.count <= 3 { styleTitle = text }

        case "id":
            if elementStack.count <= 3 { styleId = text }

        case "macro":
            inMacro = false
            if let name = currentMacroName {
                macros[name] = currentNodes
            }
            currentNodes = []

        case "layout":
            if inCitation {
                citationLayout.nodes = currentNodes
            } else if inBibliography {
                bibliographyLayout.nodes = currentNodes
            }
            currentNodes = []

        case "citation":
            inCitation = false

        case "bibliography":
            inBibliography = false

        case "sort":
            inSort = false

        case "group":
            let children = currentNodes
            currentNodes = nodeStack.popLast() ?? []
            let attrs = groupAttrStack.popLast() ?? (delimiter: " ", prefix: "", suffix: "")
            let node = CSLNode.group(delimiter: attrs.delimiter, prefix: attrs.prefix, suffix: attrs.suffix, children: children)
            currentNodes.append(node)

        case "date":
            let datePartNodes = currentNodes
            currentNodes = nodeStack.popLast() ?? []
            if let lastIndex = currentNodes.lastIndex(where: { if case .date = $0 { return true }; return false }),
               case .date(let variable, let form, _, let prefix, let suffix) = currentNodes[lastIndex] {
                let dateParts = datePartNodes.compactMap { node -> CSLNode.CSLDatePart? in
                    if case .text(let variable, _, _, _, _, _) = node, let variable {
                        return CSLNode.CSLDatePart(name: variable, form: nil)
                    }
                    return nil
                }
                currentNodes[lastIndex] = .date(variable: variable, form: form, dateParts: dateParts, prefix: prefix, suffix: suffix)
            }

        case "if", "else-if", "else":
            let children = currentNodes
            currentNodes = nodeStack.popLast() ?? []
            let attrs = pendingConditionAttrs
            let condition = CSLNode.CSLCondition(
                type: attrs["type"],
                variable: attrs["variable"],
                isNumeric: attrs["is-numeric"],
                match: attrs["match"] ?? (el == "else" ? "else" : "all"),
                children: children
            )
            if var conditions = conditionStack.popLast() {
                conditions.append(condition)
                conditionStack.append(conditions)
            }
            pendingConditionAttrs = [:]

        case "choose":
            let conditions = conditionStack.popLast() ?? []
            currentNodes = nodeStack.popLast() ?? []
            if !conditions.isEmpty {
                currentNodes.append(.choose(conditions: conditions))
            }

        case "style":
            style = CSLStyle(
                id: styleId,
                title: styleTitle,
                citationKind: styleCitationKind,
                citationLayout: citationLayout,
                citationSort: citationSort,
                bibliographyLayout: bibliographyLayout,
                bibliographySort: bibliographySort,
                macros: macros,
                etAlMin: etAlMin,
                etAlUseFirst: etAlUseFirst,
                disambiguateAddYearSuffix: false
            )

        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}

private extension CitationKind {
    init(cslCitationFormat: String) {
        switch cslCitationFormat.lowercased() {
        case "numeric":
            self = .numeric
        case "note", "label":
            self = .note
        default:
            self = .authorDate
        }
    }
}
