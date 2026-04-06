import SwiftUI

/// A popover panel for adding/editing annotation notes with a WYSIWYG Markdown editor.
/// Designed to be shown inline near the selection toolbar or highlight.
struct NotePopoverView: View {
    @Binding var markdown: String
    var selectedText: String?
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var editingMarkdown: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Selected text preview
            if let text = selectedText, !text.isEmpty {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 3)

                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 8)
                        .padding(.vertical, 6)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            // WYSIWYG Markdown editor (pre-warmed via NoteEditorPool)
            RichNoteEditorView(
                markdown: $editingMarkdown,
                placeholder: "添加笔记…",
                autoFocus: true
            )
            .frame(minHeight: 80, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 8)
            .padding(.top, 6)

            // Action bar
            HStack(spacing: 8) {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    onSave(editingMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.caption)
                .keyboardShortcut(.defaultAction)
                .disabled(editingMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark
                    ? Color(nsColor: NSColor(white: 0.18, alpha: 1))
                    : Color(nsColor: .controlBackgroundColor)
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .onAppear {
            editingMarkdown = markdown
        }
    }
}
