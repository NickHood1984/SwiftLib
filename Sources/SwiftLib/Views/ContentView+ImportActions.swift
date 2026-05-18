import SwiftUI
import SwiftLibCore

extension ContentView {

    func importBibTeX() {
        guard let url = OpenPanelPicker.pickBibTeXFile() else { return }
        viewModel.importBibTeX(from: url)
    }

    func importRIS() {
        guard let url = OpenPanelPicker.pickRISFile() else { return }
        viewModel.importRIS(from: url)
    }

    func importCitationStyles() {
        let urls = OpenPanelPicker.pickCitationStyleFiles()
        guard !urls.isEmpty else { return }

        var imported: [String] = []
        for url in urls {
            if let title = try? CSLManager.shared.importCSL(from: url) {
                imported.append(title)
            }
        }

        guard !imported.isEmpty else { return }

        cslImportMessage = "已导入：\(imported.joined(separator: "、"))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            cslImportMessage = nil
        }
    }

    func deleteReferences(ids: Set<Int64>) {
        if let selectedId, ids.contains(selectedId) {
            self.selectedId = nil
            self.selectedReference = nil
        }
        viewModel.deleteReferences(ids: ids)
    }

    func openReader(for referenceID: Int64) {
        guard let reference = try? viewModel.fetchReferences(ids: [referenceID]).first else { return }
        if reference.pdfPath != nil {
            ReaderWindowManager.shared.openPDFReader(for: reference)
        } else if reference.canOpenWebReader {
            ReaderWindowManager.shared.openWebReader(for: reference)
        }
    }

    func syncSelectedReference(visibleRows refs: [ReferenceListRow]) {
        guard let selectedId else { return }
        if !refs.contains(where: { $0.id == selectedId }) {
            self.selectedId = nil
            self.selectedReference = nil
        } else {
            selectedReference = try? viewModel.fetchReference(id: selectedId)
        }
    }

    func loadSelectedReference(for id: Int64?) {
        if let id {
            Task {
                let ref = try? await viewModel.fetchReferenceAsync(id: id)
                await MainActor.run {
                    selectedReference = ref
                }
            }
        } else {
            selectedReference = nil
        }
    }
}
