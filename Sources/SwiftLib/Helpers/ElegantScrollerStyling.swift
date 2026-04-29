import SwiftUI
import AppKit

extension NSScrollView {
    func applySwiftLibElegantScrollers() {
        scrollerStyle = .overlay
        scrollerKnobStyle = .default
        autohidesScrollers = true

        if hasVerticalScroller {
            installSwiftLibThinVerticalScrollerIfNeeded()
        }

        verticalScroller?.applySwiftLibElegantStyle()
        horizontalScroller?.applySwiftLibElegantStyle()

        // SwiftUI.Table on macOS wraps an NSTableView but its custom header
        // view lacks the native hover resize cursor. We attempt to restore it.
        applySwiftLibTableHeaderResizeCursor()
    }

    /// SwiftUI.Table wraps an NSTableView with a custom header view that does
    /// not show the resize cursor on hover (only after mouse-down drag).
    /// If we can locate the underlying NSTableView we poke its AppKit-level
    /// settings; if the header is still a native NSTableHeaderView this helps.
    private func applySwiftLibTableHeaderResizeCursor() {
        guard let tableView = findNSTableView(in: self) else { return }

        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing

        // If a real NSTableHeaderView is present, force it to rebuild tracking
        // areas so divider hover detection works.
        if let header = tableView.headerView as? NSTableHeaderView {
            header.updateTrackingAreas()
        }
    }

    private func findNSTableView(in view: NSView) -> NSTableView? {
        if let tv = view as? NSTableView { return tv }
        for subview in view.subviews {
            if let tv = findNSTableView(in: subview) { return tv }
        }
        return nil
    }

    private func installSwiftLibThinVerticalScrollerIfNeeded() {
        if let thinScroller = verticalScroller as? SwiftLibThinOverlayScroller {
            thinScroller.applySwiftLibElegantStyle()
            return
        }

        let thinScroller = SwiftLibThinOverlayScroller()
        thinScroller.applySwiftLibElegantStyle()
        verticalScroller = thinScroller
        tile()
        reflectScrolledClipView(contentView)
    }
}

extension NSScroller {
    func applySwiftLibElegantStyle() {
        scrollerStyle = .overlay
        controlSize = .mini
        knobStyle = .default
    }
}

final class SwiftLibThinOverlayScroller: NSScroller {
    private static let visualThickness: CGFloat = 6
    private static let edgePadding: CGFloat = 2

    override var isOpaque: Bool {
        false
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Keep the track invisible so only the thin overlay knob is visible.
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0, knobRect.height > 0 else { return }

        let visualRect: NSRect
        if knobRect.height >= knobRect.width {
            let width = min(Self.visualThickness, knobRect.width)
            let insetX = max(0, floor((knobRect.width - width) / 2))
            visualRect = knobRect.insetBy(dx: insetX, dy: Self.edgePadding)
        } else {
            let height = min(Self.visualThickness, knobRect.height)
            let insetY = max(0, floor((knobRect.height - height) / 2))
            visualRect = knobRect.insetBy(dx: Self.edgePadding, dy: insetY)
        }

        let radius = min(visualRect.width, visualRect.height) / 2
        knobFillColor.setFill()
        NSBezierPath(roundedRect: visualRect, xRadius: radius, yRadius: radius).fill()
    }

    private var knobFillColor: NSColor {
        let alpha: CGFloat = hitPart == .noPart ? 0.38 : 0.52
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(alpha)
        }
        return NSColor.black.withAlphaComponent(alpha)
    }
}

extension View {
    func swiftLibElegantScrollers() -> some View {
        background(SwiftUIScrollViewScrollerConfigurator())
    }
}

struct SwiftUIScrollViewScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = _ScrollerWatcherNSView()
        DispatchQueue.main.async {
            view.attachToNearestScrollView()
        }
        // SwiftUI.Table instantiates its NSScrollView later than List, so
        // retry a few frames later to catch it.
        for delay in [0.05, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                view?.attachToNearestScrollView()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let watcher = nsView as? _ScrollerWatcherNSView else { return }
        DispatchQueue.main.async {
            watcher.attachToNearestScrollView()
        }
    }
}

/// An NSView that locates its enclosing NSScrollView and uses KVO to apply
/// elegant scroller styles even after SwiftUI lazily instantiates the scroller.
private final class _ScrollerWatcherNSView: NSView {
    private weak var watchedScrollView: NSScrollView?
    private var verticalScrollerObservation: NSKeyValueObservation?
    private var horizontalScrollerObservation: NSKeyValueObservation?

    func attachToNearestScrollView() {
        guard let sv = findEnclosingScrollView(from: self) else { return }
        guard sv !== watchedScrollView else { return }
        watchedScrollView = sv

        // Apply immediately in case scroller already exists.
        sv.applySwiftLibElegantScrollers()

        // Re-apply whenever SwiftUI creates/replaces the vertical scroller.
        verticalScrollerObservation = sv.observe(\.verticalScroller, options: [.new]) { scrollView, _ in
            DispatchQueue.main.async {
                scrollView.applySwiftLibElegantScrollers()
            }
        }
        horizontalScrollerObservation = sv.observe(\.horizontalScroller, options: [.new]) { scrollView, _ in
            DispatchQueue.main.async {
                scrollView.applySwiftLibElegantScrollers()
            }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in
            self?.attachToNearestScrollView()
        }
    }

    private func findEnclosingScrollView(from view: NSView) -> NSScrollView? {
        // 1. Walk up the superview chain — works for ScrollView + LazyVStack.
        var current: NSView? = view
        while let v = current {
            if let sv = v.enclosingScrollView { return sv }
            if let sv = v as? NSScrollView { return sv }
            current = v.superview
        }

        // 2. Search siblings and their descendants.
        // SwiftUI List / Table places the background NSView and the
        // underlying NSOutlineView/NSTableView as *siblings* under the same
        // NSHostingView, so the scroll view is never reachable by walking up.
        // Walk outward a few superview levels, scanning each parent's subtree
        // for an NSScrollView. Table's NSScrollView tends to live a couple of
        // levels up vs List, so we try multiple ancestors.
        var ancestor: NSView? = view.superview
        for _ in 0..<6 {
            guard let parent = ancestor else { break }
            for subview in parent.subviews where subview !== view {
                if let sv = subview as? NSScrollView { return sv }
                if let sv = findScrollViewInSubviews(of: subview) { return sv }
            }
            ancestor = parent.superview
        }

        return nil
    }

    private func findScrollViewInSubviews(of view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for subview in view.subviews {
            if let sv = findScrollViewInSubviews(of: subview) { return sv }
        }
        return nil
    }
}
