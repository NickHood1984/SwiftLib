import SwiftUI
import SwiftLibCore

struct PDFInfoSidebarView: View {
    let reference: Reference

    @State private var expandedRows: Set<String> = []
    @State private var isAbstractExpanded = false

    private var basicFields: [InfoField] {
        [
            InfoField(id: "basic-title", label: "标题", value: reference.title),
            InfoField(id: "basic-authors", label: "作者", value: reference.authors.map { $0.displayName }.joined(separator: ", ")),
            InfoField(id: "basic-year", label: "年份", value: reference.year.map(String.init)),
            InfoField(id: "basic-type", label: "类型", value: reference.referenceType.rawValue),
            InfoField(id: "basic-language", label: "语言", value: reference.language),
        ]
        .compactMap { $0.normalized }
    }

    private var publicationFields: [InfoField] {
        [
            InfoField(id: "publication-journal", label: "期刊", value: reference.journal),
            InfoField(id: "publication-volume", label: "卷", value: reference.volume),
            InfoField(id: "publication-issue", label: "期", value: reference.issue),
            InfoField(id: "publication-pages", label: "页码", value: reference.pages),
            InfoField(id: "publication-publisher", label: "出版社", value: reference.publisher),
            InfoField(id: "publication-place", label: "出版地", value: reference.publisherPlace),
            InfoField(id: "publication-edition", label: "版次", value: reference.edition),
            InfoField(id: "publication-institution", label: "机构", value: reference.institution),
            InfoField(id: "publication-page-count", label: "页数", value: reference.numberOfPages),
        ]
        .compactMap { $0.normalized }
    }

    private var identifierFields: [InfoField] {
        [
            InfoField(id: "identifier-doi", label: "DOI", value: reference.doi),
            InfoField(id: "identifier-isbn", label: "ISBN", value: reference.isbn),
            InfoField(id: "identifier-issn", label: "ISSN", value: reference.issn),
            InfoField(id: "identifier-url", label: "URL", value: reference.url),
        ]
        .compactMap { $0.normalized }
    }

    private var abstractText: String? {
        let text = reference.abstract?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !basicFields.isEmpty {
                    infoSection("基本信息") {
                        fieldRows(basicFields)
                    }
                }

                if !publicationFields.isEmpty {
                    infoSection("出版信息") {
                        fieldRows(publicationFields)
                    }
                }

                if !identifierFields.isEmpty {
                    infoSection("标识符") {
                        fieldRows(identifierFields)
                    }
                }

                if let abstractText {
                    abstractSection(abstractText)
                }

                if basicFields.isEmpty && publicationFields.isEmpty && identifierFields.isEmpty && abstractText == nil {
                    emptyState
                }
            }
            .padding(12)
            .background(alignment: .top) {
                SwiftUIScrollViewScrollerConfigurator()
                    .frame(height: 1)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("暂无可显示的信息")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text("这条记录目前只有很少元数据。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func infoSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func fieldRows(_ fields: [InfoField]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(fields) { field in
                infoRow(field)
            }
        }
    }

    private func infoRow(_ field: InfoField) -> some View {
        let isExpanded = expandedRows.contains(field.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isExpanded {
                    expandedRows.remove(field.id)
                } else {
                    expandedRows.insert(field.id)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(field.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
                    .padding(.top, 1)

                Text(field.value ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func abstractSection(_ abstractText: String) -> some View {
        let shouldShowToggle = abstractText.count > 260

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("摘要")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if shouldShowToggle {
                    Button(isAbstractExpanded ? "收起" : "展开") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAbstractExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
            }

            Text(abstractText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(isAbstractExpanded ? nil : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(10)
                .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 0.5)
                )
        }
    }
}

private struct InfoField: Identifiable {
    let id: String
    let label: String
    let value: String?

    var normalized: InfoField? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        return InfoField(id: id, label: label, value: trimmedValue)
    }
}
