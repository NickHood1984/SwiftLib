import SwiftUI
import AppKit

struct FloatingGlassIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color.white.opacity(
                            configuration.isPressed
                                ? (colorScheme == .dark ? 0.13 : 0.34)
                                : (colorScheme == .dark ? 0.04 : 0.12)
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FloatingGlassCapsuleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color.white.opacity(
                            configuration.isPressed
                                ? (colorScheme == .dark ? 0.14 : 0.36)
                                : (isActive
                                    ? (colorScheme == .dark ? 0.08 : 0.20)
                                    : (colorScheme == .dark ? 0.04 : 0.10))
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(
                            isActive
                                ? (colorScheme == .dark ? 0.08 : 0.16)
                                : 0
                        ),
                        lineWidth: 0.45
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SelectionActionBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    let metrics: ReaderActionBarMetrics
    @ObservedObject private var aiChat = AIChatWindowManager.shared
    @State private var noteMarkdown = ""
    @State private var editorContentHeight: CGFloat = 36
    @State private var capturedSelectionText = ""
    @State private var capturedPageRects: [Int: [CGRect]] = [:]
    @Environment(\.colorScheme) private var colorScheme

    private func saveNoteIfNeeded() {
        let md = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !md.isEmpty, !capturedSelectionText.isEmpty else { return }
        viewModel.addAnnotations(
            type: .note,
            selectedText: capturedSelectionText,
            noteText: md,
            pageRects: capturedPageRects
        )
        noteMarkdown = ""
    }

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
            : Color(nsColor: NSColor(white: 0.13, alpha: 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: actions + color dots
            HStack(spacing: metrics.topRowSpacing) {
                toolbarButton(icon: "highlighter", label: "高亮") {
                    viewModel.applySelectionAction(.highlight)
                }

                toolbarButton(icon: "doc.on.doc", label: "复制") {
                    if !viewModel.stagedSelectionText.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.stagedSelectionText, forType: .string)
                    }
                }

                AISparklesHoverButton(
                    metrics: metrics,
                    isLoading: aiChat.isLoading,
                    onTranslate: {
                        guard !viewModel.stagedSelectionText.isEmpty else { return }
                        let text = viewModel.stagedSelectionText
                        Task {
                            do {
                                let prompt = "请将以下内容翻译成中文，只返回翻译结果，不要添加任何解释：\n\n\(text)"
                                let response = try await AIChatWindowManager.shared.sendText(prompt)
                                let sep = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                                noteMarkdown += sep + response
                            } catch {
                                let sep = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                                noteMarkdown += sep + "⚠️ \(error.localizedDescription)"
                            }
                        }
                    },
                    onQA: {
                        guard !viewModel.stagedSelectionText.isEmpty else { return }
                        let text = viewModel.stagedSelectionText
                        Task {
                            do {
                                try await AIChatWindowManager.shared.injectTextOnly(text)
                            } catch {
                                let sep = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                                noteMarkdown += sep + "⚠️ \(error.localizedDescription)"
                            }
                        }
                    }
                )

                separator

                ForEach(AnnotationColor.palette) { color in
                    let isSelected = viewModel.currentColorHex == color.id
                    Button {
                        viewModel.currentColorHex = color.id
                        viewModel.applySelectionAction(.highlight)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color.nsColor.withAlphaComponent(1.0)))
                            .frame(width: metrics.colorDotSize, height: metrics.colorDotSize)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.white : Color.white.opacity(0.2),
                                        lineWidth: isSelected ? 2 : 0.5
                                    )
                            )
                            .scaleEffect(isSelected ? 1.12 : 1.0)
                                    .frame(width: metrics.colorButtonWidth, height: metrics.buttonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                }

                Spacer(minLength: 4)

                separator

                toolbarButton(icon: "trash", label: "关闭") {
                    saveNoteIfNeeded()
                    viewModel.clearStagedSelection()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.topRowHorizontalPadding)
            .padding(.vertical, metrics.topRowVerticalPadding)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, metrics.dividerHorizontalPadding)

            // Note section: inline editor (auto-saves on dismiss / trash click)
            RichNoteEditorView(
                markdown: $noteMarkdown,
                placeholder: "添加笔记…",
                autoFocus: false,
                onContentHeightChanged: { height in
                    editorContentHeight = height
                }
            )
            .frame(height: min(max(editorContentHeight, 36), metrics.selectionEditorMaxHeight))
            .clipShape(RoundedRectangle(cornerRadius: metrics.editorCornerRadius))
            .padding(.horizontal, metrics.editorHorizontalPadding)
            .padding(.top, metrics.editorTopPadding)
            .padding(.bottom, metrics.actionRowVerticalPadding)
        }
        .frame(width: metrics.toolbarWidth)
        .onAppear {
            capturedSelectionText = viewModel.stagedSelectionText
            capturedPageRects = viewModel.stagedSelectionPageRects
        }
        .onChange(of: viewModel.stagedSelectionText) { _, newValue in
            if !newValue.isEmpty {
                capturedSelectionText = newValue
                capturedPageRects = viewModel.stagedSelectionPageRects
            }
        }
        .onDisappear {
            saveNoteIfNeeded()
        }
        .background(bgColor, in: RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: metrics.separatorHeight)
            .padding(.horizontal, metrics.separatorHorizontalPadding)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: metrics.buttonIconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: metrics.buttonWidth, height: metrics.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NotionToolbarButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed
                          ? Color.white.opacity(0.18)
                          : (isHovered ? Color.white.opacity(0.10) : Color.clear))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Annotation Action Bar (for clicked existing highlights)

/// Toolbar shown when user clicks an existing highlight.
/// Provides: change color, edit note, delete.
struct AnnotationActionBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    let metrics: ReaderActionBarMetrics
    @State private var isEditingNote = false
    @State private var editingMarkdown = ""
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var editorContentHeight: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
            : Color(nsColor: NSColor(white: 0.13, alpha: 1))
    }

    var body: some View {
        if let annotation = viewModel.clickedAnnotationRecord {
            VStack(spacing: 0) {
                // Top row: color dots + actions
                HStack(spacing: metrics.topRowSpacing) {
                    ForEach(AnnotationColor.palette) { color in
                        let isSelected = annotation.color == color.id
                        Button {
                            viewModel.updateAnnotationColor(annotation, color: color.id)
                            if let updated = viewModel.annotations.first(where: { $0.id == annotation.id }) {
                                viewModel.clickedAnnotationRecord = updated
                            }
                        } label: {
                            Circle()
                                .fill(Color(nsColor: color.nsColor.withAlphaComponent(1.0)))
                                .frame(width: metrics.colorDotSize, height: metrics.colorDotSize)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? Color.white : Color.white.opacity(0.2),
                                            lineWidth: isSelected ? 2 : 0.5
                                        )
                                )
                                .scaleEffect(isSelected ? 1.12 : 1.0)
                                    .frame(width: metrics.colorButtonWidth, height: metrics.buttonHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(color.name)
                        .animation(.easeOut(duration: 0.12), value: isSelected)
                    }

                    Spacer(minLength: 4)

                    separator

                    Button {
                        viewModel.deleteAnnotation(annotation)
                        viewModel.dismissAnnotationToolbar()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: metrics.buttonIconSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: metrics.buttonWidth, height: metrics.buttonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
                    .help("删除标注")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.topRowHorizontalPadding)
                .padding(.vertical, metrics.topRowVerticalPadding)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.horizontal, metrics.dividerHorizontalPadding)

                // Note section: editor / placeholder
                if isEditingNote {
                    // WYSIWYG inline editor — auto-saves
                    RichNoteEditorView(
                        markdown: $editingMarkdown,
                        placeholder: "添加笔记…",
                        autoFocus: true,
                        onContentHeightChanged: { height in
                            // Animate so the height change doesn't trigger a synchronous
                            // layout pass that makes the PDF view jitter.
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                editorContentHeight = height
                            }
                        }
                    )
                    .frame(height: min(max(editorContentHeight, 36), metrics.annotationEditorMaxHeight))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.editorCornerRadius))
                    .padding(.horizontal, metrics.editorHorizontalPadding)
                    .padding(.vertical, metrics.editorVerticalPadding)
                } else {
                    // No note — placeholder to add
                    Button {
                        editingMarkdown = ""
                        isEditingNote = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: metrics.placeholderIconSize))
                            Text("添加笔记…")
                                .font(.system(size: metrics.placeholderFontSize))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, metrics.editorHorizontalPadding)
                        .padding(.vertical, metrics.editorVerticalPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: metrics.toolbarWidth)
            .background(bgColor, in: RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .onAppear {
                let noteText = annotation.noteText ?? ""
                editingMarkdown = noteText
                isEditingNote = !noteText.isEmpty
                // Pre-estimate height from line count to reduce the initial jump
                // when WKWebView reports its actual height.
                if !noteText.isEmpty {
                    let lines = noteText.components(separatedBy: "\n").count
                    let estimated = CGFloat(lines) * 22 + 24
                    editorContentHeight = min(max(estimated, 36), metrics.annotationEditorMaxHeight)
                }
            }
            .onChange(of: annotation.id) { _, _ in
                let noteText = annotation.noteText ?? ""
                editingMarkdown = noteText
                isEditingNote = !noteText.isEmpty
            }
            .onChange(of: editingMarkdown) { _, newValue in
                autoSaveTask?.cancel()
                autoSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    if let ann = viewModel.clickedAnnotationRecord {
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.updateAnnotationNote(ann, noteText: trimmed)
                    }
                }
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: metrics.separatorHeight)
            .padding(.horizontal, metrics.separatorHorizontalPadding)
    }
}

