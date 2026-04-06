import AppKit
import SwiftUI
import SwiftLibCore

struct BatchImportView: View {
    let resolver: MetadataResolver
    let onImport: ([Reference]) -> Void
    let onQueueResult: (MetadataResolutionResult, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var results: [ImportResult] = []
    @State private var progress = 0
    @State private var total = 0
    @State private var queuedInputs: [String] = []
    @State private var currentIndex = 0
    @State private var statusMessage: String?

    struct ImportResult: Identifiable {
        enum Outcome {
            case imported(Reference)
            case queued(String)
            case failed(String)
        }

        let id = UUID()
        let identifier: String
        let outcome: Outcome

        var isSuccess: Bool {
            if case .imported = outcome { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("批量元数据导入")
                    .font(.headline)
                Spacer()
                if !results.isEmpty {
                    Button("导入 \(results.filter(\.isSuccess).count) 条到资料库") {
                        let refs = results.compactMap { result -> Reference? in
                            if case .imported(let ref) = result.outcome { return ref }
                            return nil
                        }
                        onImport(refs)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(results.filter(\.isSuccess).isEmpty)
                } else {
                    Button("全部抓取") { startBatchFetch() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(identifiers.isEmpty || isProcessing)
                }
            }
            .padding()

            Divider()

            if results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("粘贴 DOI / ISBN / PMID / arXiv / 中文题名，或 CNKI 链接，每行一个：")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $inputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .border(Color.secondary.opacity(0.3))

                    HStack {
                        Text("已识别 \(identifiers.count) 条输入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("从剪贴板粘贴") {
                            if let text = NSPasteboard.general.string(forType: .string) {
                                inputText = text
                            }
                        }
                        .font(.caption)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("示例（每行一个）：")
                                .font(.caption.bold())
                            Text("""
                            10.1038/nature12373
                            9787302511854
                            https://book.douban.com/subject/35723636/
                            arXiv:2301.07041
                            太湖流域水环境研究进展
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    if isProcessing {
                        HStack {
                            ProgressView(value: Double(progress), total: Double(total))
                            Text("\(progress)/\(total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                    }

                    let succeeded = results.filter(\.isSuccess).count
                    let queued = results.filter {
                        if case .queued = $0.outcome { return true }
                        return false
                    }.count
                    let failed = results.filter {
                        if case .failed = $0.outcome { return true }
                        return false
                    }.count
                    HStack {
                        Label("\(succeeded) 条已验证", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if queued > 0 {
                            Label("\(queued) 条进入待确认", systemImage: "clock.badge.exclamationmark")
                                .foregroundStyle(.orange)
                        }
                        if failed > 0 {
                            Label("\(failed) 条失败", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal)

                    List(results) { result in
                        HStack(spacing: 8) {
                            Image(systemName: iconName(for: result.outcome))
                                .foregroundStyle(iconColor(for: result.outcome))
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 2) {
                                switch result.outcome {
                                case .imported(let ref):
                                    Text(ref.title)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(
                                        [
                                            ref.authors.displayString,
                                            ref.year.map(String.init),
                                            ref.publisher ?? ref.journal
                                        ]
                                        .compactMap { $0 }
                                        .joined(separator: " · ")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                case .queued(let message):
                                    Text(result.identifier)
                                        .font(.callout)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                case .failed(let error):
                                    Text(result.identifier)
                                        .font(.callout)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(width: 680, height: 540)
    }

    private var identifiers: [String] {
        inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func startBatchFetch() {
        queuedInputs = identifiers
        total = queuedInputs.count
        progress = 0
        currentIndex = 0
        results = []
        isProcessing = !queuedInputs.isEmpty

        guard isProcessing else { return }

        Task { @MainActor in
            let maxConcurrency = 3
            let inputs = queuedInputs

            await withTaskGroup(of: (String, MetadataResolutionResult).self) { group in
                var nextIndex = 0

                // Seed initial batch
                while nextIndex < min(maxConcurrency, inputs.count) {
                    let identifier = inputs[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let result = await resolver.resolveManualEntry(identifier)
                        return (identifier, result)
                    }
                }

                // Process results as they arrive, enqueue more work
                for await (identifier, result) in group {
                    switch result {
                    case .verified(let envelope):
                        appendResult(identifier: identifier, outcome: .imported(envelope.reference))
                    case .candidate, .blocked, .seedOnly, .rejected:
                        onQueueResult(result, identifier)
                        appendResult(identifier: identifier, outcome: .queued("已加入待确认队列"))
                    }

                    if nextIndex < inputs.count {
                        let nextIdentifier = inputs[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            let result = await resolver.resolveManualEntry(nextIdentifier)
                            return (nextIdentifier, result)
                        }
                    }
                }
            }

            isProcessing = false
            statusMessage = nil
        }
    }

    private func appendResult(identifier: String, outcome: ImportResult.Outcome) {
        results.append(ImportResult(identifier: identifier, outcome: outcome))
        progress += 1
        if progress >= total {
            statusMessage = nil
        }
    }

    private func statusMessage(for input: String) -> String {
        if let url = URL(string: input), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            if MetadataResolution.metadataSource(for: input, fallback: .translationServer) == .cnki {
                return "正在匹配中文元数据…"
            }
            return "正在校验输入…"
        }
        if MetadataFetcher.extractIdentifier(from: input) != nil {
            return "正在启动本地元数据服务…"
        }
        return "正在匹配中文元数据…"
    }

    private func iconName(for outcome: ImportResult.Outcome) -> String {
        switch outcome {
        case .imported:
            return "checkmark.circle.fill"
        case .queued:
            return "clock.badge.exclamationmark"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func iconColor(for outcome: ImportResult.Outcome) -> Color {
        switch outcome {
        case .imported:
            return .green
        case .queued:
            return .orange
        case .failed:
            return .red
        }
    }
}
