import SwiftUI
import SwiftLibCore

struct WebAnnotationSidebarView: View {
    @ObservedObject var viewModel: WebReaderViewModel
    @State private var filterType: AnnotationType?
    @State private var editingAnnotation: WebAnnotationRecord?
    @State private var editNoteText = ""

    /// `ScrollViewReader.scrollTo` 目标 id（与正文的 `swiftlib-article-summary` 对应侧栏卡片）。
    private static let summaryCardScrollID = "swiftlib-web-sidebar-summary"

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()

            if !viewModel.hasSidebarSummary && filteredAnnotations.isEmpty {
                emptyState
            } else {
                scrollableSidebarBody
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $editingAnnotation) { annotation in
            editNoteSheet(annotation: annotation)
        }
    }

    private var filteredAnnotations: [WebAnnotationRecord] {
        if let filterType {
            return viewModel.annotations.filter { $0.type == filterType }
        }
        return viewModel.annotations
    }

    private var sidebarHeader: some View {
        VStack(spacing: 0) {
            DraggableSegmentedControl(selection: $filterType, items: [
                ("全部", nil),
                ("高亮", .highlight),
                ("下划线", .underline),
                ("笔记", .note),
            ])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "highlighter")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("暂无标注")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("选择文本后使用悬浮菜单进行标注")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var scrollableSidebarBody: some View {
        ScrollViewReader { proxy in
            OverlayScrollView {
                VStack(spacing: 8) {
                    if viewModel.hasSidebarSummary {
                        WebSummarySidebarCard(
                            text: (viewModel.reference.abstract ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                            isHighlighted: viewModel.highlightSidebarSummary,
                            onTap: { viewModel.scrollArticleToSummary() }
                        )
                        .id(Self.summaryCardScrollID)
                    }

                    if filteredAnnotations.isEmpty {
                        compactEmptyAnnotations
                    } else {
                        ForEach(filteredAnnotations) { annotation in
                            WebAnnotationCard(
                                annotation: annotation,
                                isSelected: viewModel.selectedAnnotationId == annotation.id,
                                onTap: {
                                    viewModel.navigateTo(annotation)
                                },
                                onEdit: {
                                    editNoteText = annotation.noteText ?? ""
                                    editingAnnotation = annotation
                                },
                                onDelete: {
                                    viewModel.deleteAnnotation(annotation)
                                }
                            )
                            .id(annotation.id)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.sidebarSummaryScrollToken) { _, _ in
                withAnimation {
                    proxy.scrollTo(Self.summaryCardScrollID, anchor: .top)
                }
            }
            .onChange(of: viewModel.selectedAnnotationId) { _, newId in
                if let newId {
                    withAnimation {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }

    private var compactEmptyAnnotations: some View {
        VStack(spacing: 6) {
            Text("暂无标注")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("选中文本后可添加高亮、下划线或笔记")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func editNoteSheet(annotation: WebAnnotationRecord) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("编辑笔记")
                    .font(.headline)
                Spacer()
                Button("取消") { editingAnnotation = nil }
                    .keyboardShortcut(.cancelAction)
            }

            Text(annotation.selectedText)
                .font(.callout)
                .lineLimit(4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            RichNoteEditorView(markdown: $editNoteText)
                .frame(minHeight: 110)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

            HStack {
                Spacer()
                Button("保存") {
                    viewModel.updateAnnotationNote(annotation, noteText: editNoteText)
                    editingAnnotation = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
    }
}

// MARK: - 摘要卡片（与正文摘要块联动）

private struct WebSummarySidebarCard: View {
    let text: String
    let isHighlighted: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("摘要")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.down.to.line")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted
                    ? Color.accentColor.opacity(0.1)
                    : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHighlighted ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .help("跳转到正文中的摘要位置")
    }
}

private struct WebAnnotationCard: View {
    let annotation: WebAnnotationRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isShowingNotePreview = false
    @StateObject private var hoverProgress = ManualHoverProgressController()

    private var showsActionButtons: Bool {
        isHovered || isSelected
    }

    private var actionButtonOpacity: CGFloat {
        ManualHoverMotion.footerOpacity(progress: hoverProgress.progress)
    }

    private var footerRevealHeight: CGFloat {
        ManualHoverMotion.footerReserve(progress: hoverProgress.progress, maxHeight: 32)
    }

    private var actionButtonOffset: CGFloat {
        ManualHoverMotion.footerOffset(progress: hoverProgress.progress, maxOffset: 6)
    }

    private var actionButtonHitTestingEnabled: Bool {
        showsActionButtons || hoverProgress.progress > 0.76
    }

    private let footerBarHeight: CGFloat = 26

    private var fullNoteText: String? {
        guard let note = annotation.noteText?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        return note
    }

    private var normalizedNotePreview: String? {
        guard let note = fullNoteText else { return nil }
        let cleanedNote = note
            .replacingOccurrences(of: #"(?m)^#{1,6} "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^```[^\n]*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedNote.isEmpty ? nil : cleanedNote
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: annotation.color).opacity(0.8))
                    .frame(width: 10, height: 10)

                Image(systemName: annotation.type.icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(annotation.type.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(annotation.dateCreated.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(annotation.selectedText)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: annotation.color).opacity(0.7))
                        .frame(width: 3)
                }

            if let previewNote = normalizedNotePreview, let fullNote = fullNoteText {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let attributed = try? AttributedString(markdown: previewNote, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(previewNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 16)
                .overlay(alignment: .bottomTrailing) {
                    notePreviewIndicator(noteText: fullNote)
                        .padding(.trailing, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footerActionStrip: some View {
        HStack(spacing: 8) {
            Button { onEdit() } label: {
                Image(systemName: "pencil")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("编辑笔记")

            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("删除标注")
        }
        .padding(.horizontal, 8)
        .frame(height: footerBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
        .opacity(actionButtonOpacity)
        .offset(y: actionButtonOffset)
        .allowsHitTesting(actionButtonHitTestingEnabled)
    }

    private var footerExtension: some View {
        ZStack(alignment: .bottomTrailing) {
            footerActionStrip
                .padding(.trailing, 12)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: footerRevealHeight, alignment: .bottom)
        .clipped()
        .onHover { hovering in
            isHovered = hovering
            syncHoverProgress()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            cardContent
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                    syncHoverProgress()
                }
            footerExtension
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color.primary.opacity(ManualHoverMotion.hoverFill(progress: hoverProgress.progress, maxOpacity: 0.04))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onTap() }
        .onAppear {
            hoverProgress.sync(to: showsActionButtons)
        }
        .onChange(of: isSelected) { _, _ in
            syncHoverProgress()
        }
        .onDisappear {
            hoverProgress.cancel()
        }
    }

    private func syncHoverProgress() {
        hoverProgress.setVisible(showsActionButtons)
    }

    private func notePreviewIndicator(noteText: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isShowingNotePreview {
                AnnotationNoteHoverBubble(noteText: noteText)
            }

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(4)
                .background(Color.primary.opacity(0.04), in: Circle())
                .opacity(0.82)
                .help("查看完整笔记")
        }
        .onHover { hovering in
            isShowingNotePreview = hovering
        }
    }
}
