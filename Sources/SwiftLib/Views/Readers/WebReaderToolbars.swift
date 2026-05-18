import SwiftUI
import AppKit
import SwiftLibCore

struct WebSelectionActionBar: View {
    @ObservedObject var viewModel: WebReaderViewModel
    let metrics: ReaderActionBarMetrics
    @ObservedObject private var aiChat = AIChatWindowManager.shared
    @State private var noteMarkdown = ""
    @State private var editorContentHeight: CGFloat = 36
    @State private var capturedSelection: WebSelectionSnapshot? = nil
    @Environment(\.colorScheme) private var colorScheme

    private func saveNoteIfNeeded() {
        let md = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !md.isEmpty, let selection = capturedSelection else { return }
        viewModel.addAnnotation(type: .note, selection: selection, noteText: md)
        noteMarkdown = ""
    }

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
            : Color(nsColor: NSColor(white: 0.13, alpha: 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.topRowSpacing) {
                toolbarButton(icon: "highlighter", label: "高亮") {
                    viewModel.applySelectionAction(.highlight)
                }

                toolbarButton(icon: "doc.on.doc", label: "复制") {
                    if let text = viewModel.pendingSelection?.text, !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }

                AISparklesHoverButton(
                    metrics: metrics,
                    isLoading: aiChat.isLoading,
                    onTranslate: {
                        guard let text = viewModel.pendingSelection?.text, !text.isEmpty else { return }
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
                        guard let text = viewModel.pendingSelection?.text, !text.isEmpty else { return }
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
                    viewModel.clearSelection()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.topRowHorizontalPadding)
            .padding(.vertical, metrics.topRowVerticalPadding)

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
            capturedSelection = viewModel.pendingSelection
        }
        .onChange(of: viewModel.pendingSelection) { _, newValue in
            if let newValue {
                capturedSelection = newValue
            }
        }
        .onDisappear {
            saveNoteIfNeeded()
        }
        .background(bgColor, in: RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12),
            radius: colorScheme == .dark ? 16 : 10,
            y: colorScheme == .dark ? 6 : 3
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.12 : 0.06),
            radius: 3,
            y: 1
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12))
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
        .buttonStyle(WebNotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct WebNotionToolbarButtonStyle: ButtonStyle {
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

// MARK: - Web Annotation Action Bar (for clicked existing highlights)

struct WebAnnotationActionBar: View {
    @ObservedObject var viewModel: WebReaderViewModel
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
                    .buttonStyle(WebNotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
                    .help("删除标注")
                }
                .padding(.horizontal, metrics.topRowHorizontalPadding)
                .padding(.vertical, metrics.topRowVerticalPadding)

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
                            editorContentHeight = height
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

