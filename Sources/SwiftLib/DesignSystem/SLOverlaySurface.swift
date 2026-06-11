import SwiftUI
import AppKit

/// Unified chrome for transient floating surfaces (progress toasts, message
/// banners, queue notices): one background, hairline border, and shadow so
/// every overlay reads as the same family of UI.
struct SLOverlaySurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = SLDesign.CornerRadius.xl

    func body(content: Content) -> some View {
        content
            .background(
                Color(NSColor.controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

extension View {
    func slOverlaySurface(cornerRadius: CGFloat = SLDesign.CornerRadius.xl) -> some View {
        modifier(SLOverlaySurfaceModifier(cornerRadius: cornerRadius))
    }
}
