import SwiftUI
import Combine
import SwiftLibCore

extension LibraryViewModel {

    // MARK: - Mutation

    func moveReferences(ids: Set<Int64>, toCollectionId: Int64?) {
        do {
            try db.moveReferences(ids: Array(ids), toCollectionId: toCollectionId)
        } catch {
            errorMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    func deleteReferences(ids: Set<Int64>) {
        let idArray = Array(ids)
        do {
            let pdfPaths = try db.deleteReferencesReturningPDFPaths(ids: idArray)
            for path in pdfPaths {
                PDFService.deletePDF(at: path)
            }
            WordAddinServer.shared.invalidateRenderCache()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveReference(_ ref: inout Reference) -> SaveReferenceOutcome? {
        ref.dateModified = Date()
        do {
            let outcome = try db.saveReference(&ref)
            WordAddinServer.shared.invalidateRenderCache()
            if case .mergedInto(_, let title) = outcome {
                mergeBannerMessage = "已与现有条目「\(title.prefix(30))」合并"
                scheduleClearMergeBanner()
            }
            return outcome
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return nil
        }
    }

    private func scheduleClearMergeBanner() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.mergeBannerMessage = nil
        }
    }

    func translateAbstract(_ ref: Reference) async -> Reference? {
        guard let abstract = ref.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
              !abstract.isEmpty else {
            return nil
        }

        let langName = SwiftLibPreferences.abstractTranslationLanguageOptions
            .first { $0.code == SwiftLibPreferences.abstractTranslationLanguage }?
            .name ?? "中文"

        let prompt = "请将以下内容翻译成\(langName)，只返回翻译结果，不要添加任何解释：\n\n\(abstract)"

        do {
            let translated = try await AIChatWindowManager.shared.sendText(prompt)
            let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            var mutable = ref
            mutable.translatedAbstract = trimmed
            mutable.dateModified = Date()
            saveReference(&mutable)
            return mutable
        } catch {
            await MainActor.run {
                errorMessage = "翻译摘要失败：\(error.localizedDescription)"
            }
            return nil
        }
    }

    func saveManualReference(_ ref: inout Reference, reviewedBy: String = "manual-entry") {
        if ref.id == nil && !ref.verificationStatus.isLibraryReady {
            ref = MetadataVerifier.manuallyVerified(ref, reviewedBy: reviewedBy)
        }
        saveReference(&ref)
    }

    func batchImportReferences(_ refs: [Reference]) {
        do {
            let result = try db.batchImportReferences(refs)
            lastBatchResult = result
            WordAddinServer.shared.invalidateRenderCache()
        } catch {
            errorMessage = "Batch import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Queries

    nonisolated func fetchReference(id: Int64) throws -> Reference? {
        try db.fetchReference(id: id)
    }

    nonisolated func fetchReferenceAsync(id: Int64) async throws -> Reference? {
        try await db.fetchReferenceAsync(id: id)
    }

    nonisolated func fetchReferences(ids: [Int64]) throws -> [Reference] {
        try db.fetchReferences(ids: ids)
    }

    nonisolated func fetchReferences(scope: ReferenceScope, filter: ReferenceFilter, limit: Int, offset: Int = 0) throws -> [Reference] {
        try db.fetchReferences(scope: scope, filter: filter, limit: limit, offset: offset)
    }

    nonisolated func fetchTags(forReference id: Int64) throws -> [Tag] {
        try db.fetchTags(forReference: id)
    }

    nonisolated func annotationCount(referenceId: Int64) throws -> Int {
        try db.annotationCount(referenceId: referenceId)
    }

    nonisolated func webAnnotationCount(referenceId: Int64) throws -> Int {
        try db.webAnnotationCount(referenceId: referenceId)
    }

    nonisolated func hasWebContent(id: Int64) throws -> Bool {
        try db.hasWebContent(id: id)
    }

    nonisolated func fetchWebContent(id: Int64) throws -> String? {
        try db.fetchWebContent(id: id)
    }

    func observePendingMetadataIntakesPublisher() -> some Publisher<[MetadataIntake], Error> {
        db.observePendingMetadataIntakes()
    }
}
