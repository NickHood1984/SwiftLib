import SwiftUI
import AppKit

/// A ScrollView wrapper that forces overlay-style (thin) scrollbars,
/// matching the appearance of PDFView's native scrollbars.
struct OverlayScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = scrollView.documentView as? NSHostingView<Content> else { return }
        hostingView.rootView = content
        scrollView.applySwiftLibElegantScrollers()

        let preservedOrigin = scrollView.contentView.bounds.origin

        // Nudge AppKit to recompute the document height after content changes
        // without forcing the clip view to re-reflect its scroll position on
        // every transient hover animation frame.
        DispatchQueue.main.async {
            scrollView.documentView?.invalidateIntrinsicContentSize()
            scrollView.layoutSubtreeIfNeeded()
            scrollView.documentView?.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: preservedOrigin)
        }
    }
}
