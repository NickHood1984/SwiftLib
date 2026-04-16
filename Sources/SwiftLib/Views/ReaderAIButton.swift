import SwiftUI
import AppKit

// MARK: - AI Sparkles Hover Button
// Custom hover-triggered popup that replaces native Menu{}. Design matches
// the dark toolbar language of SelectionActionBar / WebSelectionActionBar.

struct AISparklesHoverButton: View {
    let metrics: ReaderActionBarMetrics
    let isLoading: Bool
    let onTranslate: () -> Void
    let onQA: () -> Void

    @State private var showMenu = false
    @State private var isHoveringButton = false
    @State private var isHoveringMenu = false

    var body: some View {
        // ── Sparkle icon (stays in place, never moves) ─────────────────
        Image(systemName: "sparkles")
            .font(.system(size: metrics.buttonIconSize, weight: .semibold))
            .foregroundStyle(.white.opacity(isLoading ? 0.3 : 0.88))
            .frame(width: metrics.buttonWidth, height: metrics.buttonHeight)
            .contentShape(Rectangle())
            .overlay {
                if isLoading { ProgressView().controlSize(.small) }
            }
            .background(
                RoundedRectangle(cornerRadius: metrics.buttonCornerRadius)
                    .fill(Color.white.opacity(isHoveringButton && !isLoading ? 0.12 : 0))
            )
            .onHover { hovering in
                isHoveringButton = hovering
                if hovering && !isLoading {
                    withAnimation(.easeOut(duration: 0.1)) { showMenu = true }
                } else if !hovering {
                    scheduleHide()
                }
            }
            // Popup floats above the button via overlay — zero layout impact
            .overlay(alignment: .bottom) {
                if showMenu && !isLoading {
                    menuPopup
                        .fixedSize()
                        .offset(y: -metrics.buttonHeight - 4)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .bottom)),
                            removal: .opacity
                        ))
                        .zIndex(100)
                        .allowsHitTesting(true)
                }
            }
            .animation(.spring(response: 0.16, dampingFraction: 0.82), value: showMenu)
            .help("Ask AI")
    }

    // Wait briefly before hiding so mouse can travel from button to popup.
    private func scheduleHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if !isHoveringButton && !isHoveringMenu {
                withAnimation(.easeOut(duration: 0.1)) { showMenu = false }
            }
        }
    }

    // MARK: Popup view

    private var menuPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            AIMenuItem(icon: "character.book.closed", label: "翻译") {
                withAnimation(.easeOut(duration: 0.08)) { showMenu = false }
                onTranslate()
            }
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, 8)
            AIMenuItem(icon: "text.bubble", label: "问答（手动发送）") {
                withAnimation(.easeOut(duration: 0.08)) { showMenu = false }
                onQA()
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 148)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: NSColor(white: 0.17, alpha: 0.97)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.40), radius: 14, x: 0, y: 5)
        // Invisible bridge below popup: keeps hover zone continuous while
        // mouse travels across the gap between popup and button.
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringMenu = hovering
            if !hovering { scheduleHide() }
        }
    }
}

// MARK: - Single menu item with hover highlight

private struct AIMenuItem: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 14, alignment: .center)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.90))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .onHover { isHovered = $0 }
    }
}
