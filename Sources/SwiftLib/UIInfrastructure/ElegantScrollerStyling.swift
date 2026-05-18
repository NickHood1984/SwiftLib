import SwiftUI
import AppKit

private enum SwiftLibElegantScrollerStyle {
    static let visualThickness: CGFloat = 5
    static let edgePadding: CGFloat = 3

    static func knobFillColor(for scroller: NSScroller) -> NSColor {
        let isDark = scroller.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isInteracting = scroller.hitPart != .noPart
        let alpha: CGFloat

        if isDark {
            alpha = isInteracting ? 0.34 : 0.22
            return NSColor.white.withAlphaComponent(alpha)
        }

        alpha = isInteracting ? 0.24 : 0.14
        return NSColor.black.withAlphaComponent(alpha)
    }
}

extension NSView {
    func applySwiftLibElegantScrollersRecursively(forceVerticalScroller: Bool = false) {
        if let scrollView = self as? NSScrollView {
            if forceVerticalScroller {
                scrollView.hasVerticalScroller = true
            }
            scrollView.applySwiftLibElegantScrollers()
        }

        for subview in subviews {
            subview.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: forceVerticalScroller)
        }
    }
}

extension NSScrollView {
    func applySwiftLibElegantScrollers() {
        scrollerStyle = .overlay
        scrollerKnobStyle = .default
        autohidesScrollers = true

        if hasVerticalScroller {
            installSwiftLibThinVerticalScrollerIfNeeded()
        }
        if hasHorizontalScroller {
            installSwiftLibThinHorizontalScrollerIfNeeded()
        }

        verticalScroller?.applySwiftLibElegantStyle()
        horizontalScroller?.applySwiftLibElegantStyle()

        applySwiftLibTableHeaderResizeCursor()
    }

    private func applySwiftLibTableHeaderResizeCursor() {
        guard let tableView = findNSTableView(in: self) else { return }

        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing

        if let header = tableView.headerView {
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

    private func installSwiftLibThinHorizontalScrollerIfNeeded() {
        if let thinScroller = horizontalScroller as? SwiftLibThinOverlayScroller {
            thinScroller.applySwiftLibElegantStyle()
            return
        }

        let thinScroller = SwiftLibThinOverlayScroller()
        thinScroller.applySwiftLibElegantStyle()
        horizontalScroller = thinScroller
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
    override var isOpaque: Bool {
        false
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0, knobRect.height > 0 else { return }

        let visualRect: NSRect
        if knobRect.height >= knobRect.width {
            let width = min(SwiftLibElegantScrollerStyle.visualThickness, knobRect.width)
            let insetX = max(0, floor((knobRect.width - width) / 2))
            visualRect = knobRect.insetBy(dx: insetX, dy: SwiftLibElegantScrollerStyle.edgePadding)
        } else {
            let height = min(SwiftLibElegantScrollerStyle.visualThickness, knobRect.height)
            let insetY = max(0, floor((knobRect.height - height) / 2))
            visualRect = knobRect.insetBy(dx: SwiftLibElegantScrollerStyle.edgePadding, dy: insetY)
        }

        let radius = min(visualRect.width, visualRect.height) / 2
        knobFillColor.setFill()
        NSBezierPath(roundedRect: visualRect, xRadius: radius, yRadius: radius).fill()
    }

    private var knobFillColor: NSColor {
        SwiftLibElegantScrollerStyle.knobFillColor(for: self)
    }
}

extension View {
    func swiftLibElegantScrollers() -> some View {
        background(SwiftUIScrollViewScrollerConfigurator())
    }

    func swiftLibElegantScrollersInSubtree() -> some View {
        background(SwiftUIScrollViewTreeScrollerConfigurator())
    }
}

struct SwiftUIScrollViewScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = _ScrollerWatcherNSView()
        view.setupRetryTimer()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let watcher = nsView as? _ScrollerWatcherNSView else { return }
        DispatchQueue.main.async {
            watcher.attachToNearestScrollView()
        }
    }
}

struct SwiftUIScrollViewTreeScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = _ScrollerTreeWatcherNSView()
        view.setupRetryTimer()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let watcher = nsView as? _ScrollerTreeWatcherNSView else { return }
        watcher.scheduleApply()
    }
}

private final class _ScrollerTreeWatcherNSView: NSView {
    private var retryTimer: Timer?
    private var retryCount = 0
    private var scrollerObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private static let maxRetries = 24
    private static let retryInterval: TimeInterval = 0.1

    func setupRetryTimer() {
        scheduleApply()

        retryTimer?.invalidate()
        retryCount = 0
        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.retryCount += 1
            self.applyToCurrentWindow()

            if self.window != nil || self.retryCount >= Self.maxRetries {
                timer.invalidate()
                self.retryTimer = nil
            }
        }
    }

    func scheduleApply() {
        DispatchQueue.main.async { [weak self] in
            self?.applyToCurrentWindow()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleApply()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            scheduleApply()
        }
    }

    deinit {
        retryTimer?.invalidate()
        scrollerObservations.values.flatMap { $0 }.forEach { $0.invalidate() }
    }

    private func applyToCurrentWindow() {
        guard let root = window?.contentView ?? superview else { return }
        root.applySwiftLibElegantScrollersRecursively()
        observeScrollViews(in: root)
    }

    private func observeScrollViews(in root: NSView) {
        for scrollView in scrollViews(in: root) {
            let id = ObjectIdentifier(scrollView)
            guard scrollerObservations[id] == nil else { continue }

            let vertical = scrollView.observe(\.verticalScroller, options: [.new]) { [weak self, weak scrollView] _, _ in
                DispatchQueue.main.async {
                    scrollView?.applySwiftLibElegantScrollers()
                    self?.scheduleApply()
                }
            }

            let horizontal = scrollView.observe(\.horizontalScroller, options: [.new]) { [weak self, weak scrollView] _, _ in
                DispatchQueue.main.async {
                    scrollView?.applySwiftLibElegantScrollers()
                    self?.scheduleApply()
                }
            }

            scrollerObservations[id] = [vertical, horizontal]
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        for subview in view.subviews {
            result.append(contentsOf: scrollViews(in: subview))
        }
        return result
    }
}

private final class _ScrollerWatcherNSView: NSView {
    private weak var watchedScrollView: NSScrollView?
    private var verticalScrollerObservation: NSKeyValueObservation?
    private var horizontalScrollerObservation: NSKeyValueObservation?
    private var retryTimer: Timer?
    private var retryCount = 0
    private static let maxRetries = 20
    private static let retryInterval: TimeInterval = 0.1

    func setupRetryTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.attachToNearestScrollView()
        }

        retryTimer?.invalidate()
        retryCount = 0
        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.retryCount += 1
            guard self.retryCount <= Self.maxRetries else {
                timer.invalidate()
                self.retryTimer = nil
                return
            }
            self.attachToNearestScrollView()
            if self.watchedScrollView != nil {
                timer.invalidate()
                self.retryTimer = nil
            }
        }
    }

    func attachToNearestScrollView() {
        guard let sv = findEnclosingScrollView(from: self) else { return }
        guard sv !== watchedScrollView else { return }
        watchedScrollView = sv

        sv.applySwiftLibElegantScrollers()

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.attachToNearestScrollView()
            }
        }
    }

    deinit {
        retryTimer?.invalidate()
    }

    private func findEnclosingScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let sv = v.enclosingScrollView { return sv }
            if let sv = v as? NSScrollView { return sv }
            current = v.superview
        }

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
