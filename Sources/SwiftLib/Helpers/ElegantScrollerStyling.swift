import AppKit

extension NSScrollView {
    func applySwiftLibElegantScrollers() {
        scrollerStyle = .overlay
        scrollerKnobStyle = .default
        autohidesScrollers = true
        verticalScroller?.applySwiftLibElegantStyle()
        horizontalScroller?.applySwiftLibElegantStyle()
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
