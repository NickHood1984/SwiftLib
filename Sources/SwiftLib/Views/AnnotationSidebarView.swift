import SwiftUI
import SwiftLibCore

struct AnnotationSidebarView: View {
    private static let topScrollID = "swiftlib-pdf-annotation-sidebar-top"

    let annotations: [PDFAnnotationRecord]
    let selectedAnnotationId: Int64?
    let onNavigate: (PDFAnnotationRecord) -> Void
    let onDelete: (PDFAnnotationRecord) -> Void
    let onUpdateNote: (PDFAnnotationRecord, String) -> Void
    @State private var filterType: AnnotationType?
    @State private var editingAnnotation: PDFAnnotationRecord?
    @State private var editNoteText = ""

    private var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil) { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.15, alpha: 1.0)
                : NSColor(calibratedWhite: 0.90, alpha: 1.0)
        })
    }

    private var panelBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var panelStroke: Color {
        Color(nsColor: .separatorColor).opacity(0.55)
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()

            if filteredAnnotations.isEmpty {
                emptyState
            } else {
                annotationList
                    .padding(.top, 10)
                    .clipped()
            }
        }
        .background(sidebarBackground)
        .sheet(item: $editingAnnotation) { annotation in
            editNoteSheet(annotation: annotation)
        }
    }

    private var filteredAnnotations: [PDFAnnotationRecord] {
        if let filterType {
            return annotations.filter { $0.type == filterType }
        }
        return annotations
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            DraggableSegmentedControl(selection: $filterType, items: [
                ("全部", nil),
                ("高亮", .highlight),
                ("下划线", .underline),
                ("笔记", .note),
            ])
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 36)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(panelBackground)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "highlighter")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(panelStroke, lineWidth: 0.5)
                )

            VStack(spacing: 6) {
                Text("暂无标注")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("选择正文内容后，可在悬浮工具条中添加高亮、下划线或笔记。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    // MARK: - Annotation List

    private var annotationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topScrollID)

                    ForEach(filteredAnnotations) { annotation in
                        AnnotationCard(
                            annotation: annotation,
                            isSelected: selectedAnnotationId == annotation.id,
                            onTap: {
                                onNavigate(annotation)
                            },
                            onEdit: {
                                editNoteText = annotation.noteText ?? ""
                                editingAnnotation = annotation
                            },
                            onDelete: {
                                onDelete(annotation)
                            }
                        )
                        .id(annotation.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .background(alignment: .top) {
                    // Placed INSIDE the ScrollView content so the configurator's
                    // NSView is a child of the NSScrollView — enclosingScrollView
                    // then correctly reaches the outer NSScrollView and applies
                    // the thin overlay scroller style.
                    SwiftUIScrollViewScrollerConfigurator()
                        .frame(height: 1)
                }
            }
            .onAppear {
                guard selectedAnnotationId == nil else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.topScrollID, anchor: .top)
                }
            }
            .onChange(of: filterType) { _, _ in
                guard selectedAnnotationId == nil else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.topScrollID, anchor: .top)
                }
            }
            .onChange(of: selectedAnnotationId) { _, newId in
                if let newId {
                    withAnimation { proxy.scrollTo(newId, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Edit Note Sheet

    private func editNoteSheet(annotation: PDFAnnotationRecord) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("编辑笔记")
                    .font(.headline)
                Spacer()
                Button("取消") { editingAnnotation = nil }
                    .keyboardShortcut(.cancelAction)
            }

            if let text = annotation.selectedText, !text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选中文本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.callout)
                        .lineLimit(3)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("笔记内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RichNoteEditorView(markdown: $editNoteText)
                    .frame(minHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            }

            HStack {
                Spacer()
                Button("保存") {
                    onUpdateNote(annotation, editNoteText)
                    editingAnnotation = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
    }
}

extension AnnotationSidebarView: Equatable {
    static func == (lhs: AnnotationSidebarView, rhs: AnnotationSidebarView) -> Bool {
        lhs.annotations == rhs.annotations
            && lhs.selectedAnnotationId == rhs.selectedAnnotationId
    }
}

// MARK: - Annotation Card

struct AnnotationCard: View {
    let annotation: PDFAnnotationRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private let fullNoteText: String?
    private let normalizedNotePreview: String?
    private let normalizedNoteAttributedPreview: AttributedString?

    @State private var isHovered = false
    @State private var isShowingNotePreview = false

    init(
        annotation: PDFAnnotationRecord,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.annotation = annotation
        self.isSelected = isSelected
        self.onTap = onTap
        self.onEdit = onEdit
        self.onDelete = onDelete

        let note = annotation.noteText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usableNote = (note?.isEmpty == false) ? note : nil
        self.fullNoteText = usableNote

        if let usableNote {
            let cleanedNote = usableNote
                .replacingOccurrences(of: #"(?m)^#{1,6} "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?m)^```[^\n]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = cleanedNote.isEmpty ? nil : cleanedNote
            self.normalizedNotePreview = preview
            if let preview {
                self.normalizedNoteAttributedPreview = try? AttributedString(
                    markdown: preview,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )
            } else {
                self.normalizedNoteAttributedPreview = nil
            }
        } else {
            self.normalizedNotePreview = nil
            self.normalizedNoteAttributedPreview = nil
        }
    }

    private var showsActionButtons: Bool {
        isHovered || isSelected
    }

    private var cardBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.08)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var cardStroke: Color {
        isSelected ? Color.accentColor.opacity(0.30) : Color(nsColor: .separatorColor).opacity(0.45)
    }

    private var cardShadow: Color {
        Color.black.opacity(isSelected ? 0.10 : 0.04)
    }

    private var excerptBackground: Color {
        Color.primary.opacity(isSelected ? 0.055 : 0.030)
    }

    private var noteBackground: Color {
        Color.primary.opacity(isSelected ? 0.045 : 0.022)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(Color(hex: annotation.color).opacity(0.85))
                    .frame(width: 8, height: 8)

                Text(annotation.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                if showsActionButtons {
                    HStack(spacing: 6) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("编辑笔记")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("删除标注")
                    }
                } else {
                    Text("P\(annotation.pageIndex + 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text(annotation.dateCreated.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(height: 16)

            if let text = annotation.selectedText, !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(hex: annotation.color).opacity(0.75))
                            .frame(width: 3)
                    }
                    .padding(8)
                    .background(excerptBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let previewNote = normalizedNotePreview, let fullNote = fullNoteText {
                VStack(alignment: .leading, spacing: 4) {
                    if let attributed = normalizedNoteAttributedPreview {
                        Text(attributed)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(previewNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 8)
                .padding(.trailing, 28)
                .padding(.bottom, 18)
                .background(noteBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    notePreviewIndicator(noteText: fullNote)
                        .padding(.trailing, 7)
                        .padding(.bottom, 7)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: isSelected ? 1 : 0.5)
            )
                .shadow(color: cardShadow, radius: isSelected ? 8 : 0, y: isSelected ? 3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { onTap() }
            .onHover { isHovered = $0 }
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

    private func cardActionButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}

struct AnnotationNoteHoverBubble: View {
    let noteText: String

    private var plainText: String {
        Self.sanitizedPlainText(from: noteText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("完整笔记")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(plainText)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(width: 220, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 4)
    }

    private static func sanitizedPlainText(from source: String) -> String {
        let regexReplacements: [(String, String)] = [
            (#"!\[([^\]]*)\]\([^)]+\)"#, "$1"),
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),
            (#"(?m)^\s*```[^\n]*$"#, ""),
            (#"(?m)^\s*~~~[^\n]*$"#, ""),
            (#"(?m)^\s{0,3}#{1,6}\s*"#, ""),
            (#"(?m)^\s{0,3}>\s?"#, ""),
            (#"(?m)^\s*[-*+]\s+\[[ xX]\]\s*"#, ""),
            (#"(?m)^\s*[-*+]\s+"#, ""),
            (#"(?m)^\s*\d+\.\s+"#, ""),
            (#"(?m)^\s*([-*_]\s*){3,}$"#, ""),
            (#"(\*\*|__)(.*?)\1"#, "$2"),
            (#"(\*|_)(.*?)\1"#, "$2"),
            (#"~~(.*?)~~"#, "$1"),
            (#"`([^`]*)`"#, "$1"),
            (#"<[^>]+>"#, "")
        ]

        var result = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for (pattern, replacement) in regexReplacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        result = result
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "`", with: "")

        let lines = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }
}
