import SwiftUI
import SwiftLibCore

struct PDFInfoSidebarView: View {
    let reference: Reference
    @State private var expandedRows: Set<String> = []

    var body: some View {
        OverlayScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoSection("基本信息") {
                    infoRow("标题", value: reference.title)
                    infoRow("作者", value: reference.authors.map { $0.displayName }.joined(separator: ", "))
                    infoRow("年份", value: reference.year.map { String($0) })
                    infoRow("类型", value: reference.referenceType.rawValue)
                }

                infoSection("出版信息") {
                    infoRow("期刊", value: reference.journal)
                    infoRow("卷", value: reference.volume)
                    infoRow("期", value: reference.issue)
                    infoRow("页码", value: reference.pages)
                    infoRow("出版社", value: reference.publisher)
                    infoRow("出版地", value: reference.publisherPlace)
                    infoRow("版次", value: reference.edition)
                    infoRow("机构", value: reference.institution)
                    infoRow("语言", value: reference.language)
                    infoRow("页数", value: reference.numberOfPages)
                }

                infoSection("标识符") {
                    infoRow("DOI", value: reference.doi)
                    infoRow("ISBN", value: reference.isbn)
                    infoRow("ISSN", value: reference.issn)
                    if let url = reference.url {
                        infoRow("URL", value: url)
                    }
                }

                if let abstract = reference.abstract, !abstract.isEmpty {
                    infoSection("摘要") {
                        Text(abstract)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
        }
    }

    private func infoSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            let isExpanded = expandedRows.contains(label)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedRows.remove(label)
                    } else {
                        expandedRows.insert(label)
                    }
                }
            }) {
                HStack(alignment: .top, spacing: 8) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 45, alignment: .trailing)
                        .padding(.top, 1)
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }
}
