import SwiftUI
import SwiftLibCore

extension ContentView {

    // MARK: - Metadata Refresh

    func refreshMetadataForIDs(_ ids: Set<Int64>) {
        guard let refs = try? viewModel.fetchReferences(ids: Array(ids)) else { return }
        refreshMetadata(for: refs)
    }

    func refreshMetadata(for references: [Reference]) {
        let candidates = references.compactMap { reference -> Reference? in
            guard reference.id != nil else { return nil }
            return reference
        }
        guard !candidates.isEmpty else { return }

        if candidates.count == 1, let reference = candidates.first {
            refreshSingleReferenceMetadata(reference)
        } else {
            refreshBatchMetadata(for: candidates)
        }
    }

    func refreshSingleReferenceMetadata(_ reference: Reference) {
        refreshTask?.cancel()
        viewModel.isImporting = true
        viewModel.importProgress = "正在刷新元数据…"

        let task = Task { @MainActor in
            let result = await metadataResolver.refreshReference(reference, allowCandidateSelection: true)
            // The cancel button already reset the toast; don't overwrite it
            // with a stale result from the cancelled refresh.
            guard !Task.isCancelled else { return }
            switch result {
            case .refreshed(let refreshed):
                saveRefreshedReference(refreshed, message: "已刷新：\(refreshed.title)")

            case .pending(let pendingResult):
                _ = queueResolutionResult(
                    pendingResult,
                    options: MetadataPersistenceOptions(
                        sourceKind: .refresh,
                        originalInput: reference.doi ?? reference.pmid ?? reference.isbn ?? reference.title,
                        linkedReferenceId: reference.id
                    ),
                    successMessage: "已加入待确认队列，等待你继续处理"
                )

            case .skipped(let reason):
                viewModel.isImporting = false
                viewModel.importProgress = reason
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if !viewModel.isImporting {
                        viewModel.importProgress = nil
                    }
                }

            case .failed(let message):
                viewModel.isImporting = false
                viewModel.importProgress = nil
                viewModel.errorMessage = message
            }
        }

        refreshTask = task
    }

    func refreshBatchMetadata(for references: [Reference]) {
        refreshTask?.cancel()

        let task = Task { @MainActor in
            viewModel.isImporting = true
            viewModel.importProgress = "准备刷新 \(references.count) 条条目…"

            var refreshedCount = 0
            var skippedCount = 0
            var failedMessages: [String] = []
            let total = references.count
            let maxConcurrency = 3

            for batchStart in stride(from: 0, to: total, by: maxConcurrency) {
                if Task.isCancelled { break }

                let batchEnd = min(batchStart + maxConcurrency, total)
                let batch = Array(references[batchStart..<batchEnd])

                viewModel.importProgress = "正在刷新 \(batchStart + 1)–\(batchEnd)/\(total)…"

                let batchResults: [(Reference, ReferenceMetadataRefreshResult)] = await withTaskGroup(
                    of: (Reference, ReferenceMetadataRefreshResult).self,
                    returning: [(Reference, ReferenceMetadataRefreshResult)].self
                ) { group in
                    for reference in batch {
                        group.addTask {
                            let result = await metadataResolver.refreshReference(reference, allowCandidateSelection: false)
                            return (reference, result)
                        }
                    }
                    var results: [(Reference, ReferenceMetadataRefreshResult)] = []
                    for await pair in group {
                        results.append(pair)
                    }
                    return results
                }

                if Task.isCancelled {
                    failedMessages.append(contentsOf: batch.map { "\($0.title)：已取消" })
                    break
                }

                for (reference, result) in batchResults {
                    switch result {
                    case .refreshed(let refreshed):
                        saveRefreshedReference(refreshed, message: nil, finishRefreshing: false, clearProgress: false)
                        refreshedCount += 1
                    case .pending(let pendingResult):
                        _ = queueResolutionResult(
                            pendingResult,
                            options: MetadataPersistenceOptions(
                                sourceKind: .refresh,
                                originalInput: reference.doi ?? reference.pmid ?? reference.isbn ?? reference.title,
                                linkedReferenceId: reference.id
                            ),
                            successMessage: nil,
                            suppressProgressReset: true
                        )
                        skippedCount += 1
                    case .skipped:
                        skippedCount += 1
                    case .failed(let message):
                        failedMessages.append("\(reference.title)：\(message)")
                    }
                }
            }

            if Task.isCancelled {
                viewModel.importProgress = "已取消：完成 \(refreshedCount)/\(total) 条"
            } else {
                viewModel.importProgress = "批量刷新完成：\(refreshedCount) 条已更新，\(skippedCount) 条跳过，\(failedMessages.count) 条失败"
            }
            viewModel.isImporting = false

            if !failedMessages.isEmpty && !Task.isCancelled {
                viewModel.errorMessage = failedMessages.prefix(5).joined(separator: "\n")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !viewModel.isImporting {
                    viewModel.importProgress = nil
                }
            }

            refreshTask = nil
        }

        refreshTask = task
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        viewModel.isImporting = false
        viewModel.importProgress = "已取消"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !viewModel.isImporting {
                viewModel.importProgress = nil
            }
        }
    }

    func saveRefreshedReference(
        _ reference: Reference,
        message: String?,
        finishRefreshing: Bool = true,
        clearProgress: Bool = true
    ) {
        var mutable = reference
        viewModel.saveReference(&mutable)
        viewModel.isImporting = !finishRefreshing ? viewModel.isImporting : false
        viewModel.importProgress = message

        guard clearProgress else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !viewModel.isImporting {
                viewModel.importProgress = nil
            }
        }
    }

    // MARK: - Metadata Queue

    @discardableResult
    func queueResolutionResult(
        _ result: MetadataResolutionResult,
        options: MetadataPersistenceOptions,
        successMessage: String?,
        suppressProgressReset: Bool = false
    ) -> MetadataPersistenceResult? {
        let persisted = viewModel.persistMetadataResolution(result, options: options)
        switch persisted {
        case .verified(let reference):
            selectedId = reference.id
            if !suppressProgressReset {
                viewModel.isImporting = false
                if reference.verificationStatus == .metadataEnriching {
                    viewModel.importProgress = "已导入，元数据补全中：\(reference.title)"
                } else {
                    viewModel.importProgress = successMessage ?? "已验证：\(reference.title)"
                }
                pendingQueueNotice = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if !viewModel.isImporting {
                        viewModel.importProgress = nil
                    }
                }
            }
        case .intake(let intake):
            if !suppressProgressReset {
                viewModel.isImporting = false
                viewModel.importProgress = nil
            }
            showPendingQueueNotice(for: intake, message: successMessage)
        case .none:
            if !suppressProgressReset {
                viewModel.isImporting = false
                viewModel.importProgress = nil
            }
        }

        return persisted
    }

    func showPendingQueueNotice(for intake: MetadataIntake, message: String?) {
        let title = "这条元数据还需要你确认"
        let lead = intake.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "该条目" : "\u{201C}\(intake.title)\u{201D}"
        let detail = message?.swiftlib_nilIfBlank
            ?? intake.statusMessage?.swiftlib_nilIfBlank
            ?? "已放入待确认队列。"

        let notice = PendingQueueNotice(
            title: title,
            message: "\(lead)\(detail.hasPrefix("已") ? "" : " ")\(detail) 你可以直接打开队列继续处理。"
        )
        pendingQueueNotice = notice

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if pendingQueueNotice?.id == notice.id {
                pendingQueueNotice = nil
            }
        }
    }

    func openPendingMetadataQueueWindow() {
        guard !viewModel.pendingMetadataIntakes.isEmpty else { return }
        let publisher = viewModel.observePendingMetadataIntakesPublisher()
            .replaceError(with: [])
            .eraseToAnyPublisher()
        PendingMetadataQueueWindowManager.shared.configure(
            intakesPublisher: publisher,
            resolver: metadataResolver,
            onPersistResult: { result, intake in
                queueResolutionResult(
                    result,
                    options: MetadataPersistenceOptions(
                        sourceKind: intake.sourceKind,
                        originalInput: intake.originalInput,
                        preferredPDFPath: intake.pdfPath,
                        linkedReferenceId: intake.linkedReferenceId,
                        existingIntakeId: intake.id
                    ),
                    successMessage: nil,
                    suppressProgressReset: true
                )
            },
            onConfirmManual: { intake in
                if let reference = viewModel.confirmPendingMetadataIntake(intake) {
                    selectedId = reference.id
                }
            },
            onDelete: { intake in
                viewModel.deletePendingMetadataIntake(intake)
            }
        )
        openWindow(value: PendingQueueWindowID.value)
    }

    // MARK: - PDF Import

    func importPDFWithMetadata() {
        guard let url = OpenPanelPicker.pickPDFFile() else { return }
        viewModel.isImporting = true
        viewModel.importProgress = "正在导入 PDF…"

        Task { @MainActor in
            do {
                let prepared = try PDFService.prepareImportedPDF(from: url)
                let fallbackReference = prepared.reference
                let seed = MetadataResolutionSeed.fromImportedPDF(url: url, extracted: prepared.extracted)

                if MetadataResolution.shouldPreferCNKIForImportedPDF(seed: seed) {
                    viewModel.importProgress = "正在匹配知网元数据…"
                } else if let doi = prepared.extracted.doi, !doi.isEmpty {
                    viewModel.importProgress = "正在获取元数据：\(doi)…"
                }

                let resolution = await metadataResolver.resolveImportedPDF(url: url, extracted: prepared.extracted)

                switch resolution {
                case .verified(let envelope):
                    var reference = envelope.reference
                    reference.pdfPath = fallbackReference.pdfPath
                    finishPDFImport(with: reference, message: "已导入: \(reference.title)")

                case .candidate, .blocked, .seedOnly, .rejected:
                    let queued = queueResolutionResult(
                        resolution,
                        options: MetadataPersistenceOptions(
                            sourceKind: .importedPDF,
                            preferredPDFPath: fallbackReference.pdfPath
                        ),
                        successMessage: "还不能自动确认，已加入待确认队列"
                    )
                    if queued == nil, let pdfPath = fallbackReference.pdfPath {
                        PDFService.deletePDF(at: pdfPath)
                    }
                }
            } catch {
                viewModel.isImporting = false
                viewModel.importProgress = nil
                viewModel.errorMessage = "PDF 导入失败: \(error.localizedDescription)"
            }
        }
    }

    func finishPDFImport(with reference: Reference, message: String?) {
        var mutable = reference
        viewModel.saveReference(&mutable)
        selectedId = mutable.id
        viewModel.isImporting = false
        viewModel.importProgress = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !viewModel.isImporting {
                viewModel.importProgress = nil
            }
        }
    }

    func translateAbstractForID(_ refId: Int64) {
        guard let reference = selectedReference, reference.id == refId else { return }
        guard let abstract = reference.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
              !abstract.isEmpty else {
            viewModel.importProgress = "该文献暂无摘要"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.viewModel.importProgress == "该文献暂无摘要" {
                    self.viewModel.importProgress = nil
                }
            }
            return
        }

        viewModel.isImporting = true
        viewModel.importProgress = "正在翻译摘要…"
        Task { @MainActor in
            if let updated = await viewModel.translateAbstract(reference) {
                selectedReference = updated
                viewModel.isImporting = false
                viewModel.importProgress = "摘要翻译完成"
            } else {
                viewModel.isImporting = false
                viewModel.importProgress = "摘要翻译失败"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !self.viewModel.isImporting {
                    self.viewModel.importProgress = nil
                }
            }
        }
    }
}
