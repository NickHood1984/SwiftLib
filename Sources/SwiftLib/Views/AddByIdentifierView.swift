import SwiftUI
import SwiftLibCore

struct AddByIdentifierView: View {
    let resolver: MetadataResolver
    let onSave: (Reference) -> Void
    let onQueueResult: (MetadataResolutionResult, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var isFetching = false
    @State private var fetchedReference: Reference?
    @State private var pendingResolution: MetadataResolutionResult?
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("元数据导入")
                .font(.headline)

            HStack {
                TextField("DOI、ISBN、PMID、arXiv、CNKI 链接或中文题名", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { fetchMetadata() }

                Button(action: fetchMetadata) {
                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetching)
            }

            Text("支持 DOI · ISBN · PMID · arXiv · CNKI 链接 · 中文题名")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if isFetching, let statusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let ref = fetchedReference {
                resolutionCard(title: "已验证：", titleText: ref.title, bodyText: verifiedSummary(for: ref))
            } else if let pendingResolution {
                resolutionCard(
                    title: "待确认：",
                    titleText: pendingResolutionTitle(pendingResolution),
                    bodyText: pendingResolutionMessage(pendingResolution)
                )
            }

            Spacer()

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SLSecondaryButtonStyle())
                Spacer()
                if let pendingResolution {
                    Button("加入待确认队列") {
                        onQueueResult(pendingResolution, inputText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(isFetching)
                    .buttonStyle(SLSecondaryButtonStyle())
                }
                Button("导入到资料库") {
                    if let ref = fetchedReference {
                        onSave(ref)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fetchedReference == nil)
                .buttonStyle(SLPrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 440)
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func resolutionCard(title: String, titleText: String, bodyText: String) -> some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(titleText)
                .font(.body.bold())

            Text(bodyText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fetchMetadata() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isFetching = true
        errorMessage = nil
        fetchedReference = nil
        pendingResolution = nil
        statusMessage = statusMessage(for: text)

        Task { @MainActor in
            let result = await resolver.resolveManualEntry(text)
            switch result {
            case .verified(let envelope):
                fetchedReference = envelope.reference
            case .candidate, .blocked, .seedOnly, .rejected:
                pendingResolution = result
            }
            isFetching = false
            statusMessage = nil
        }
    }

    private func statusMessage(for text: String) -> String {
        if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            if MetadataResolution.metadataSource(for: text, fallback: .translationServer) == .cnki {
                return "正在匹配中文元数据…"
            }
            return "正在校验输入…"
        }
        if MetadataFetcher.extractIdentifier(from: text) != nil {
            return "正在启动本地元数据服务…"
        }
        return "正在匹配中文元数据…"
    }

    private func verifiedSummary(for reference: Reference) -> String {
        let publicationLine = [reference.journal, reference.publisher, reference.year.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
        let identifierLine = [
            reference.doi.map { "DOI: \($0)" },
            reference.isbn.map { "ISBN: \($0)" },
            reference.issn.map { "ISSN: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let abstract = reference.abstract?.swiftlib_nilIfBlank ?? ""
        return [reference.authors.displayString, publicationLine, identifierLine, abstract]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func pendingResolutionTitle(_ result: MetadataResolutionResult) -> String {
        switch result {
        case .candidate(let envelope):
            return envelope.currentReference?.title
                ?? envelope.fallbackReference?.title
                ?? envelope.seed?.title
                ?? "待确认候选"
        case .blocked(let envelope):
            return envelope.currentReference?.title
                ?? envelope.fallbackReference?.title
                ?? envelope.seed?.title
                ?? "待确认条目"
        case .seedOnly(let envelope):
            return envelope.currentReference?.title
                ?? envelope.fallbackReference?.title
                ?? envelope.seed?.title
                ?? "待确认条目"
        case .rejected(let envelope):
            return envelope.currentReference?.title
                ?? envelope.fallbackReference?.title
                ?? envelope.seed?.title
                ?? "待确认条目"
        case .verified(let envelope):
            return envelope.reference.title
        }
    }

    private func pendingResolutionMessage(_ result: MetadataResolutionResult) -> String {
        switch result {
        case .candidate(let envelope):
            return envelope.message
        case .blocked(let envelope):
            return envelope.message
        case .seedOnly(let envelope):
            return envelope.message
        case .rejected(let envelope):
            return envelope.message
        case .verified:
            return ""
        }
    }
}
