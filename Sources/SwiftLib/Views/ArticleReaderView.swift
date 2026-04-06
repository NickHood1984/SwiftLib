import SwiftUI
import SwiftLibCore

struct ArticleReaderView: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            if let content = reference.webContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                articleBody(content)
            } else {
                ContentUnavailableView(
                    "No article content",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("这个网页条目还没有抓取到正文内容。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(reference.referenceType.rawValue, systemImage: reference.referenceType.icon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())

                    Text(reference.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)

                    if !reference.authors.isEmpty {
                        Text(reference.authors.displayString)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                if let urlString = reference.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("打开原文", systemImage: "safari")
                    }
                    .buttonStyle(SLPrimaryButtonStyle())
                }
            }

            HStack(spacing: 12) {
                if let siteName = reference.siteName ?? reference.journal {
                    Label(siteName, systemImage: "globe")
                }
                if let year = reference.year {
                    Label(String(year), systemImage: "calendar")
                }
                if let urlString = reference.url {
                    Text(urlString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if let summary = reference.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func articleBody(_ content: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineSpacing(5)
        } else {
            Text(content)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineSpacing(5)
        }
    }
}
