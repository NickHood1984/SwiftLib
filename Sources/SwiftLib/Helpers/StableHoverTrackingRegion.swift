import SwiftUI
import AppKit

struct StableHoverTrackingRegion: NSViewRepresentable {
    let extraBottom: CGFloat
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChange = onHoverChange
        view.extraBottom = extraBottom
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChange = onHoverChange
        nsView.extraBottom = extraBottom
        nsView.syncHoverState()
    }
}

final class TrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var extraBottom: CGFloat = 0 {
        didSet {
            if abs(oldValue - extraBottom) > 0.001 {
                refreshTrackingArea()
            }
        }
    }

    private var trackingAreaRef: NSTrackingArea?
    private var cachedTrackingRect: NSRect = .zero
    private var isHovering = false

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func layout() {
        super.layout()
        refreshTrackingArea()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        syncHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        syncHoverState()
    }

    func refreshTrackingArea() {
        guard bounds.width > 0, bounds.height > 0 else {
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
                self.trackingAreaRef = nil
            }
            cachedTrackingRect = .zero
            setHovering(false)
            return
        }

        let nextTrackingRect = trackingRect.integral
        if trackingAreaRef != nil, nextTrackingRect.equalTo(cachedTrackingRect) {
            syncHoverState()
            return
        }

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
            self.trackingAreaRef = nil
        }

        let area = NSTrackingArea(
            rect: nextTrackingRect,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
        cachedTrackingRect = nextTrackingRect
        syncHoverState()
    }

    private var trackingRect: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height + extraBottom)
    }

    func syncHoverState() {
        guard let window else {
            setHovering(false)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovering(trackingRect.contains(location))
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        onHoverChange?(hovering)
    }
}