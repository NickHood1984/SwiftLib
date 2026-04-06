import SwiftUI

// MARK: - SLPrimaryButtonStyle
// Filled accent-color button. Use for the primary / confirm action.

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
            .font(.system(size: isSmall ? 11 : 13, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, isSmall ? 10 : 14)
            .padding(.vertical, isSmall ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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

// MARK: - SLSecondaryButtonStyle
// Ghost background button. Use for cancel / auxiliary actions.

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
            .font(.system(size: isSmall ? 11 : 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, isSmall ? 10 : 14)
            .padding(.vertical, isSmall ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.12)
                            : (isHovered ? Color.primary.opacity(0.09) : Color.primary.opacity(0.06))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - SLDestructiveButtonStyle
// Soft red button. Use for irreversible / delete actions.

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
            .font(.system(size: isSmall ? 11 : 13, weight: .medium))
            .foregroundStyle(Color.red)
            .padding(.horizontal, isSmall ? 10 : 14)
            .padding(.vertical, isSmall ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
