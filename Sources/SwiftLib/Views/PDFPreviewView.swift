import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let url: URL
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("完成") {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            PDFKitView(url: url)
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        pdfView.applyElegantScrollers()
        context.coordinator.loadDocument(from: url, into: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.loadDocument(from: url, into: pdfView)
        pdfView.applyElegantScrollers()
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.cancelLoad()
        pdfView.document = nil
    }

    final class Coordinator {
        private var loadedURL: URL?
        private var loadTask: Task<Void, Never>?
        private weak var pdfView: PDFView?

        deinit {
            cancelLoad()
        }

        func loadDocument(from url: URL, into pdfView: PDFView) {
            guard loadedURL != url || pdfView.document == nil else { return }

            cancelLoad()
            loadedURL = url
            self.pdfView = pdfView

            loadTask = Task.detached(priority: .userInitiated) { [weak self] in
                let document = PDFDocument(url: url)
                guard !Task.isCancelled else { return }
                await self?.finishLoadingDocument(document, for: url)
            }
        }

        @MainActor
        private func finishLoadingDocument(_ document: PDFDocument?, for url: URL) {
            guard loadedURL == url, let pdfView else { return }
            pdfView.document = document
        }

        func cancelLoad() {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}
