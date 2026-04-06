import SwiftUI
import PDFKit
import SwiftLibCore

struct PDFReaderSidebarView: View {
    let reference: Reference
    @Binding var selectedTab: PDFSidebarTab

    var body: some View {
        VStack(spacing: 0) {
            DraggableSegmentedControl(
                selection: $selectedTab,
                items: [
                    ("目录", .outline),
                    ("信息", .info),
                ]
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .outline:
                PDFOutlineSidebarView(reference: reference)
            case .info:
                PDFInfoSidebarView(reference: reference)
            case .annotations:
                PDFInfoSidebarView(reference: reference)
            }
        }
        .background(Color(nsColor: NSColor(name: nil) { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.15, alpha: 1.0)
                : NSColor(calibratedWhite: 0.90, alpha: 1.0)
        }))
        .navigationTitle("")
    }
}
