import SwiftUI
import WebKit
import SwiftLibCore

struct WebImportView: View {
    let collections: [Collection]
    let onSave: (Reference) -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var clipperExtractor = ClipperWebMetadataExtractor()
    @State private var url = ""
    @State private var collectionId: Int64?
    @State private var clipperError: String?
    @State private var isSaving = false

    private var urlValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        ZStack {
            HiddenWKWebViewHost(
                configure: { configuration in
                    configuration.userContentController.add(
                        clipperExtractor.extractionManager,
                        name: ReaderExtractionManager.readerResultHandlerName
                    )
                },
                onCreate: { webView in
                    clipperExtractor.registerWebView(webView)
                }
            )
            .frame(width: 4, height: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                    Spacer()
                    Text("网页剪藏")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("保存") {
                            saveWebpageWithClipper()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!urlValid || isSaving)
                    }
                }
                .padding()

                Divider()

                Form {
                    Section("网页") {
                        TextField("页面链接", text: $url, prompt: Text("https://…"))
                            .textContentType(.URL)
                            .disabled(isSaving)
                        Text("保存时将使用内置 Obsidian Clipper 流水线抓取标题、摘要与正文。YouTube 会额外尝试 transcript fallback。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let clipperError {
                        Section {
                            Text(clipperError)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Button("仍保存链接（不抓取）") {
                                saveWebpageURLOnlyFallback()
                            }
                            .disabled(isSaving)
                        }
                    }

                    Section("合集") {
                        Picker("合集", selection: $collectionId) {
                            Text("不加入合集").tag(nil as Int64?)
                            ForEach(collections) { col in
                                Label(col.name, systemImage: col.icon).tag(col.id as Int64?)
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 460, height: clipperError == nil ? 300 : 380)
        .interactiveDismissDisabled(isSaving)
    }

    private func saveWebpageWithClipper() {
        clipperError = nil
        isSaving = true
        let urlTrimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let collection = collectionId

        Task { @MainActor in
            defer { isSaving = false }

            do {
                let result = try await clipperExtractor.extract(urlString: urlTrimmed)
                let reference = Reference(
                    title: result.title,
                    authors: result.authors,
                    url: result.resolvedURLString,
                    abstract: result.abstract,
                    webContent: result.webContent,
                    siteName: result.siteHost,
                    referenceType: .webpage,
                    collectionId: collection
                )
                onSave(reference)
                dismiss()
            } catch {
                clipperError = error.localizedDescription
            }
        }
    }

    private func saveWebpageURLOnlyFallback() {
        let urlTrimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: urlTrimmed)?.host
        let reference = Reference(
            title: host ?? "网页",
            url: urlTrimmed,
            siteName: host,
            referenceType: .webpage,
            collectionId: collectionId
        )
        onSave(reference)
        dismiss()
    }
}
