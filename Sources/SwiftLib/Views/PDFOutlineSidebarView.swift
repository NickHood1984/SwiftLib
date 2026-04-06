import SwiftUI
import PDFKit
import SwiftLibCore

struct PDFOutlineSidebarView: View {
    let reference: Reference

    @State private var outlineItems: [OutlineItem] = []
    @State private var activeOutlineItemId: UUID?

    var body: some View {
        Group {
            if outlineItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("暂无目录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                OverlayScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(outlineItems) { item in
                            outlineRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { loadOutline() }
    }

    private func outlineRow(_ item: OutlineItem) -> some View {
        OutlineRowView(item: item, isActive: activeOutlineItemId == item.id, onTap: { goToOutlineItem(item) })
    }

    private struct OutlineRowView: View {
        let item: OutlineItem
        let isActive: Bool
        let onTap: () -> Void
        @State private var isHovering = false

        var body: some View {
            HStack(spacing: 0) {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.accentColor : (isHovering ? Color.accentColor : .primary))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let pageIndex = item.pageIndex {
                    Text("\(pageIndex + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : (isHovering ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.tertiary)))
                        .monospacedDigit()
                }
            }
            .padding(.leading, CGFloat(item.level) * 16 + 12)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : (isHovering ? Color.accentColor.opacity(0.08) : .clear))
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }
            .onTapGesture { onTap() }
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
    }

    private func goToOutlineItem(_ item: OutlineItem) {
        guard let pageIndex = item.pageIndex,
              let pdfView = findPDFView(),
              let doc = pdfView.document,
              pageIndex < doc.pageCount,
              let page = doc.page(at: pageIndex) else { return }
        let point = item.destination?.point ?? CGPoint(x: 0, y: page.bounds(for: .mediaBox).maxY)
        let dest = PDFDestination(page: page, at: point)
        pdfView.go(to: dest)
        flashTitle(item.title, on: page, at: point, pdfView: pdfView)

        // Highlight the active outline item in the sidebar
        withAnimation(.easeOut(duration: 0.2)) { activeOutlineItemId = item.id }
    }

    private func flashTitle(_ title: String, on page: PDFPage, at point: CGPoint, pdfView: PDFView) {
        let selections = pdfView.document?.findString(title, withOptions: [.caseInsensitive]) ?? []
        let match = selections.first(where: { $0.pages.contains(page) })

        // Get the precise text bounds, or fallback to a band at the destination point
        let highlightRect: CGRect
        if let match {
            let bounds = match.bounds(for: page)
            guard !bounds.isEmpty, !bounds.isNull else {
                let pageBounds = page.bounds(for: .mediaBox)
                highlightRect = CGRect(x: pageBounds.minX + 20, y: point.y - 14, width: pageBounds.width - 40, height: 16)
                let flash = PDFAnnotation(bounds: highlightRect, forType: .highlight, withProperties: nil)
                flash.color = NSColor.controlAccentColor.withAlphaComponent(0.4)
                page.addAnnotation(flash)
                fadeOutAndRemoveFlash(flash, on: page, pdfView: pdfView)
                return
            }
            highlightRect = bounds.insetBy(dx: -3, dy: -2)
        } else {
            let pageBounds = page.bounds(for: .mediaBox)
            highlightRect = CGRect(
                x: pageBounds.minX + 20,
                y: point.y - 14,
                width: pageBounds.width - 40,
                height: 16
            )
        }

        let flash = PDFAnnotation(bounds: highlightRect, forType: .highlight, withProperties: nil)
        flash.color = NSColor.controlAccentColor.withAlphaComponent(0.4)
        page.addAnnotation(flash)

        fadeOutAndRemoveFlash(flash, on: page, pdfView: pdfView)
    }

    /// Fade-out the flash highlight over ~0.5s before removing it.
    private func fadeOutAndRemoveFlash(_ flash: PDFAnnotation, on page: PDFPage, pdfView: PDFView) {
        let totalDuration: Double = 2.0
        let fadeSteps = 5
        let fadeStart = totalDuration - 0.5
        let stepInterval = 0.5 / Double(fadeSteps)

        for step in 0..<fadeSteps {
            let delay = fadeStart + Double(step) * stepInterval
            let alpha = 0.4 * (1.0 - Double(step + 1) / Double(fadeSteps))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                flash.color = NSColor.controlAccentColor.withAlphaComponent(CGFloat(alpha))
                pdfView.setNeedsDisplay(pdfView.bounds)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            page.removeAnnotation(flash)
        }
    }

    private func loadOutline() {
        guard let pdfPath = reference.pdfPath else { return }
        let url = PDFService.pdfURL(for: pdfPath)
        guard let doc = PDFDocument(url: url),
              let root = doc.outlineRoot else { return }
        outlineItems = collectOutline(from: root, level: 0, document: doc)
    }

    private func collectOutline(from outline: PDFOutline, level: Int, document: PDFDocument) -> [OutlineItem] {
        var result: [OutlineItem] = []
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let title = child.label ?? ""
            let dest = child.destination
            let pageIndex = dest?.page.flatMap { document.index(for: $0) }
            result.append(OutlineItem(title: title, level: level, pageIndex: pageIndex, destination: dest))
            result.append(contentsOf: collectOutline(from: child, level: level + 1, document: document))
        }
        return result
    }

    private func findPDFView() -> PDFView? {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return nil }
        return findPDFViewIn(contentView)
    }

    private func findPDFViewIn(_ view: NSView) -> PDFView? {
        if let pdfView = view as? PDFView { return pdfView }
        for sub in view.subviews {
            if let found = findPDFViewIn(sub) { return found }
        }
        return nil
    }
}

struct OutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let level: Int
    let pageIndex: Int?
    let destination: PDFDestination?
}
