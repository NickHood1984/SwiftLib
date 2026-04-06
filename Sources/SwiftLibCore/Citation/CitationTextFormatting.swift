import Foundation

public struct CitationTextFormatting: Codable, Equatable {
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var superscript: Bool?
    public var subscripted: Bool?
    public var smallCaps: Bool?

    enum CodingKeys: String, CodingKey {
        case bold
        case italic
        case underline
        case superscript
        case subscripted = "subscript"
        case smallCaps
    }

    public init(
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        superscript: Bool? = nil,
        subscripted: Bool? = nil,
        smallCaps: Bool? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.superscript = superscript
        self.subscripted = subscripted
        self.smallCaps = smallCaps
    }

    public var isEmpty: Bool {
        bold == nil &&
            italic == nil &&
            underline == nil &&
            superscript == nil &&
            subscripted == nil &&
            smallCaps == nil
    }
}

extension CSLLayout {
    public var citationTextFormatting: CitationTextFormatting? {
        var formatting = CitationTextFormatting()

        if let fontWeight = fontWeight?.lowercased() {
            switch fontWeight {
            case "bold":
                formatting.bold = true
            case "normal", "light":
                formatting.bold = false
            default:
                break
            }
        }

        if let fontStyle = fontStyle?.lowercased() {
            switch fontStyle {
            case "italic", "oblique":
                formatting.italic = true
            case "normal":
                formatting.italic = false
            default:
                break
            }
        }

        if let textDecoration = textDecoration?.lowercased() {
            switch textDecoration {
            case "underline":
                formatting.underline = true
            case "none":
                formatting.underline = false
            default:
                break
            }
        }

        if let fontVariant = fontVariant?.lowercased() {
            switch fontVariant {
            case "small-caps":
                formatting.smallCaps = true
            case "normal":
                formatting.smallCaps = false
            default:
                break
            }
        }

        if let verticalAlign = verticalAlign?.lowercased() {
            switch verticalAlign {
            case "sup":
                formatting.superscript = true
                formatting.subscripted = false
            case "sub":
                formatting.subscripted = true
                formatting.superscript = false
            case "baseline", "normal":
                formatting.superscript = false
                formatting.subscripted = false
            default:
                break
            }
        }

        return formatting.isEmpty ? nil : formatting
    }
}
