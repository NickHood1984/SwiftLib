import SwiftUI

struct SLPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SLPrimaryButtonBody(configuration: configuration)
    }
}

private struct SLPrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false

    var body: some View {
        let isSmall = controlSize == .small || controlSize == .mini
        configuration.label
            .font(isSmall ? .slCaption : .slBodyMedium)
            .foregroundStyle(Color.white)
            .padding(.horizontal, isSmall ? SLDesign.Spacing.lg : 14)
            .padding(.vertical, isSmall ? SLDesign.Spacing.xs : SLDesign.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SLDesign.CornerRadius.standard, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.accentColor.opacity(0.72)
                            : (isHovered ? Color.accentColor.opacity(0.86) : Color.accentColor)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct SLSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SLSecondaryButtonBody(configuration: configuration)
    }
}

private struct SLSecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false

    var body: some View {
        let isSmall = controlSize == .small || controlSize == .mini
        configuration.label
            .font(isSmall ? .slCaption : .slBodyMedium)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, isSmall ? SLDesign.Spacing.lg : 14)
            .padding(.vertical, isSmall ? SLDesign.Spacing.xs : SLDesign.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SLDesign.CornerRadius.standard, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? SLDesign.Background.primaryPressed
                            : (isHovered ? SLDesign.Background.primaryHover : SLDesign.Background.primarySubtle)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct SLDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SLDestructiveButtonBody(configuration: configuration)
    }
}

private struct SLDestructiveButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false

    var body: some View {
        let isSmall = controlSize == .small || controlSize == .mini
        configuration.label
            .font(isSmall ? .slCaption : .slBodyMedium)
            .foregroundStyle(Color.red)
            .padding(.horizontal, isSmall ? SLDesign.Spacing.lg : 14)
            .padding(.vertical, isSmall ? SLDesign.Spacing.xs : SLDesign.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SLDesign.CornerRadius.standard, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.red.opacity(0.18)
                            : (isHovered ? Color.red.opacity(0.12) : Color.red.opacity(0.08))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
