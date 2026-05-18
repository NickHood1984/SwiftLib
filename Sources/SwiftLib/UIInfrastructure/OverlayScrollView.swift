import SwiftUI
import AppKit

/// A ScrollView wrapper that forces overlay-style (thin) scrollbars,
/// matching the appearance of PDFView's native scrollbars.
///
/// Pass `scrollToY` (document-coordinate Y of the row *centre*) to
/// programmatically scroll to that position with a smooth animation.
/// The coordinator ensures only actual changes trigger a scroll, so
/// transient SwiftUI redraws (hover, etc.) do not interrupt the user.
struct OverlayScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    /// Document-coordinate Y of the target row centre.  Pass `nil` to
    /// leave the scroll position alone.
    var scrollToY: CGFloat? = nil

    init(scrollToY: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.scrollToY = scrollToY
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.applySwiftLibElegantScrollers()

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = hostingView

        // Pin leading, trailing, and top to the clip view so the content
        // fills the width and starts at the top.  Height is intentionally
        // left unconstrained: NSHostingView reports its intrinsic content
        // size to AppKit, which uses it to set the document view height and
        // enable vertical scrolling automatically.
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])

        // Use KVO to re-apply only when SwiftUI unexpectedly replaces the
        // vertical scroller — avoids calling applySwiftLibElegantScrollers()
        // on every content update, which would reset auto-hide state.
        context.coordinator.observe(scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = scrollView.documentView as? NSHostingView<Content> else { return }
        hostingView.rootView = content

        let targetY = scrollToY
        let coordinator = context.coordinator

        // Skip expensive layout work when only transient SwiftUI state
        // changed (hover, local animation, etc.).  The costly
        // invalidateIntrinsicContentSize + layoutSubtreeIfNeeded calls
        // were previously dispatched on *every* body re-evaluation,
        // causing severe stutter with 200+ rows.
        guard targetY != coordinator.lastScrollToY else {
            if targetY == nil { coordinator.lastScrollToY = nil }
            return
        }

        let preservedOrigin = scrollView.contentView.bounds.origin

        DispatchQueue.main.async {
            scrollView.documentView?.invalidateIntrinsicContentSize()
            // layoutSubtreeIfNeeded() recursively lays out all subviews,
            // so the documentView is already covered; calling it again
            // on the documentView separately is redundant.
            scrollView.layoutSubtreeIfNeeded()

            if let ty = targetY {
                // Selection changed to a new row. But we should only ACTUALLY
                // scroll when the target is not already comfortably on
                // screen — otherwise clicking a row that's already visible
                // would yank the whole list to re-centre it, which feels like
                // "the list scrolls along with my click".
                coordinator.lastScrollToY = ty

                let visibleH = scrollView.contentView.bounds.height
                let docH     = scrollView.documentView?.bounds.height ?? 0
                let visibleOriginY = scrollView.contentView.bounds.minY
                let visibleMaxY    = visibleOriginY + visibleH

                // Require a small inset from the viewport edges before we
                // consider the row "visible enough" — prevents partially
                // clipped rows at top/bottom from being treated as visible.
                let edgeInset: CGFloat = 24
                let comfortablyVisible =
                    ty >= visibleOriginY + edgeInset &&
                    ty <= visibleMaxY - edgeInset

                if comfortablyVisible {
                    // Already on screen — just preserve the scroll position,
                    // no animation, no jump.
                    scrollView.contentView.scroll(to: preservedOrigin)
                } else {
                    // Off-screen or near-edge: animate into the viewport centre.
                    let centred = ty - visibleH / 2
                    let clamped = max(0, min(centred, max(0, docH - visibleH)))
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.22
                        ctx.allowsImplicitAnimation = true
                        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clamped))
                    }
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            } else {
                // No new scroll target — just keep the current position.
                coordinator.lastScrollToY = nil
                scrollView.contentView.scroll(to: preservedOrigin)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        private var observation: NSKeyValueObservation?
        /// The last document-Y we scrolled to; prevents re-scrolling on
        /// every SwiftUI redraw that doesn't change the selection.
        var lastScrollToY: CGFloat? = nil

        func observe(_ scrollView: NSScrollView) {
            observation = scrollView.observe(\.verticalScroller, options: [.new]) { sv, _ in
                DispatchQueue.main.async {
                    // Only re-install the thin scroller; do NOT call the full
                    // applySwiftLibElegantScrollers() which would flash the bar.
                    if !(sv.verticalScroller is SwiftLibThinOverlayScroller) {
                        sv.applySwiftLibElegantScrollers()
                    }
                }
            }
        }
    }
}
