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
        alphaValue = 0.42
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
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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
        var current: NSView? = view
        while let v = current {
            if let sv = v.enclosingScrollView { return sv }
            if let sv = v as? NSScrollView { return sv }
            current = v.superview
        }
        return nil
    }
}
