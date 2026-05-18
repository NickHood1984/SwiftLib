import SwiftUI

enum SLDesign {
    enum FontSize {
        static let caption2: CGFloat = 10
        static let caption: CGFloat = 11
        static let bodySmall: CGFloat = 12
        static let body: CGFloat = 13
        static let subheadline: CGFloat = 15
        static let headline: CGFloat = 18
        static let title3: CGFloat = 20
        static let title2: CGFloat = 24
        static let title: CGFloat = 30
        static let largeTitle: CGFloat = 36
    }

    enum Spacing {
        static let tiny: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
        static let xxxl: CGFloat = 20
        static let section: CGFloat = 24
    }

    enum CornerRadius {
        static let small: CGFloat = 4
        static let standard: CGFloat = 7
        static let medium: CGFloat = 8
        static let large: CGFloat = 10
        static let xl: CGFloat = 12
        static let panel: CGFloat = 20
    }

    enum Background {
        static func accent(opacity: CGFloat) -> Color { Color.accentColor.opacity(opacity) }
        static func primary(opacity: CGFloat) -> Color { Color.primary.opacity(opacity) }
        static func secondary(opacity: CGFloat) -> Color { Color.secondary.opacity(opacity) }

        static let accentHover = accent(opacity: 0.15)
        static let accentPressed = accent(opacity: 0.18)
        static let accentSubtle = accent(opacity: 0.08)

        static let primaryHover = primary(opacity: 0.09)
        static let primaryPressed = primary(opacity: 0.12)
        static let primarySubtle = primary(opacity: 0.05)
    }
}

extension Font {
    static func sl(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    static let slCaption2 = sl(SLDesign.FontSize.caption2, weight: .medium)
    static let slCaption = sl(SLDesign.FontSize.caption, weight: .medium)
    static let slBodySmall = sl(SLDesign.FontSize.bodySmall, weight: .regular)
    static let slBody = sl(SLDesign.FontSize.body, weight: .regular)
    static let slBodyMedium = sl(SLDesign.FontSize.body, weight: .medium)
    static let slSubheadline = sl(SLDesign.FontSize.subheadline, weight: .medium)
    static let slHeadline = sl(SLDesign.FontSize.headline, weight: .regular)
}
