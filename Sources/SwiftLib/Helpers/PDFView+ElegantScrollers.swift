import AppKit
import PDFKit

extension PDFView {
    /// PDFKit 内部的滚动视图（macOS 下通常是 subviews.first 的私有 PDFScrollView 类）。
    /// `enclosingScrollView` 只向上找祖先，因此永远返回 nil；这里向下找子视图。
    var internalScrollView: NSScrollView? {
        // 最快路径：PDFKit 实现里 PDFScrollView 就是第一个子视图
        subviews.first as? NSScrollView ?? descendantScrollViews(of: self).first
    }

    func applyElegantScrollers() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let scrollViews = descendantScrollViews(of: self)
            for scrollView in scrollViews {
                scrollView.applySwiftLibElegantScrollers()
            }

            let scrollers = descendantScrollers(of: self)
            for scroller in scrollers {
                scroller.applySwiftLibElegantStyle()
            }
        }
    }

    func descendantScrollViews(of view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                result.append(scrollView)
            }
            result.append(contentsOf: descendantScrollViews(of: subview))
        }
        return result
    }

    private func descendantScrollers(of view: NSView) -> [NSScroller] {
        var result: [NSScroller] = []
        for subview in view.subviews {
            if let scroller = subview as? NSScroller {
                result.append(scroller)
            }
            result.append(contentsOf: descendantScrollers(of: subview))
        }
        return result
    }
}
