import Foundation
import SwiftLibCore

extension LibraryViewModel {

    func importBibTeX(from url: URL) {
        isImporting = true
        importProgress = "正在读取文件…"

        Task.detached { [weak self] in
            guard let self else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { self.importProgress = "正在解析 BibTeX…" }

                let refs = BibTeXImporter.parse(content)
                await MainActor.run { self.importProgress = "正在导入 \(refs.count) 条条目…" }

                let count = try self.db.batchImportReferences(refs)
                await MainActor.run {
                    self.importProgress = "已导入 \(count) 条条目"
                    self.isImporting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.importProgress = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.importProgress = "导入失败：\(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }

    func importRIS(from url: URL) {
        isImporting = true
        importProgress = "正在读取文件…"

        Task.detached { [weak self] in
            guard let self else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { self.importProgress = "正在解析 RIS…" }

                let refs = RISImporter.parse(content)
                await MainActor.run { self.importProgress = "正在导入 \(refs.count) 条条目…" }

                let count = try self.db.batchImportReferences(refs)
                await MainActor.run {
                    self.importProgress = "已导入 \(count) 条条目"
                    self.isImporting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.importProgress = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.importProgress = "导入失败：\(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }
}
