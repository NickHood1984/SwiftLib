import SwiftUI
import SwiftLibCore

struct AddWorkspaceSheet: View {
    let onSave: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "square.stack.3d.up"

    private let icons = [
        "square.stack.3d.up", "books.vertical", "folder", "book.closed",
        "bookmark", "graduationcap", "briefcase", "brain",
        "flask", "atom", "doc.text.magnifyingglass", "tray.full",
        "star", "flag", "tag", "archivebox"
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("新建工作区")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("为一组文献和资料保存独立窗口布局")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                    workspaceNameField

                    iconGrid

                    HStack(spacing: 10) {
                        Button("取消") {
                            dismiss()
                        }
                        .buttonStyle(SLSecondaryButtonStyle())

                        Spacer()

                        Button("创建") {
                            createWorkspace()
                        }
                        .buttonStyle(SLPrimaryButtonStyle())
                        .disabled(trimmedName.isEmpty)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 42)
                .padding(.bottom, 34)
            }
            .frame(width: 520)
            .background(notionModalBackground)
            .overlay(notionModalBorder)
            .shadow(color: .black.opacity(0.34), radius: 30, x: 0, y: 20)
            .padding(28)
        }
        .frame(width: 580)
    }

    private var headerBar: some View {
        HStack {
            iconButton(systemName: "arrow.left", help: "返回") {
                dismiss()
            }

            Spacer()

            iconButton(systemName: "xmark", help: "关闭") {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var workspaceNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名称")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("例如：论文写作", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(controlBackground)
                .overlay(controlBorder)
                .onSubmit(createWorkspace)
        }
    }

    private var iconGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("图标")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 8), spacing: 8) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedIcon == icon ? Color.accentColor : Color.secondary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selectedIcon == icon
                                        ? Color.accentColor.opacity(0.14)
                                        : Color.primary.opacity(0.035))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selectedIcon == icon
                                        ? Color.accentColor.opacity(0.65)
                                        : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notionModalBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0.98),
                        Color(nsColor: .controlBackgroundColor).opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var notionModalBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.035))
    }

    private var controlBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func createWorkspace() {
        guard !trimmedName.isEmpty else { return }
        let workspace = Workspace(
            name: trimmedName,
            icon: selectedIcon,
            kind: .manual
        )
        onSave(workspace)
        dismiss()
    }
}
