import SwiftUI
import SwiftLibCore

struct SidebarView: View {
    let collections: [Collection]
    let tags: [Tag]
    let titleKeywords: [(word: String, count: Int)]
    @Binding var selection: SidebarItem
    let referenceCount: Int
    let onDeleteCollection: (Int64) -> Void
    let onDeleteTag: (Int64) -> Void
    let onAddCollection: () -> Void

    var body: some View {
        VStack(spacing: 0) {
        OverlayScrollView {
            VStack(spacing: 20) {
                sidebarSection {
                    SidebarRow(
                        icon: "books.vertical",
                        label: "全部文献",
                        isSelected: selection == .allReferences,
                        trailing: { countBadge(referenceCount) }
                    ) {
                        selection = .allReferences
                    }
                }

                sidebarSection {
                    HStack {
                        Text("收藏集")
                        Spacer()
                        Button(action: onAddCollection) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("新建收藏集")
                    }
                } content: {
                    if collections.isEmpty {
                        Text("暂无收藏集")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(collections) { collection in
                            SidebarRow(
                                icon: collection.icon,
                                label: collection.name,
                                isSelected: selection == .collection(collection.id!)
                            ) {
                                selection = .collection(collection.id!)
                            }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    onDeleteCollection(collection.id!)
                                }
                            }
                        }
                    }
                }

                sidebarSection {
                    Text("标签")
                } content: {
                    if tags.isEmpty {
                        Text("暂无标签")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(tags) { tag in
                            SidebarRow(
                                iconView: AnyView(
                                    Circle()
                                        .fill(Color(hex: tag.color))
                                        .frame(width: 9, height: 9)
                                ),
                                label: tag.name,
                                isSelected: selection == .tag(tag.id!)
                            ) {
                                selection = .tag(tag.id!)
                            }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    onDeleteTag(tag.id!)
                                }
                            }
                        }
                    }
                }

            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }

        if !titleKeywords.isEmpty {
            Divider()
                .padding(.horizontal, 10)
            sidebarSection {
                Text("智能合集")
            } content: {
                FlowLayout(spacing: 6) {
                    ForEach(titleKeywords, id: \.word) { item in
                        let isSelected = selection == .titleKeyword(item.word)
                        Button {
                            if isSelected {
                                selection = .allReferences
                            } else {
                                selection = .titleKeyword(item.word)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(item.word)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                Text("\(item.count)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("SwiftLib")
    }

    // MARK: - Building Blocks

    @ViewBuilder
    private func sidebarSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            content()
        }
    }

    @ViewBuilder
    private func sidebarSection<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            header()
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.none)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            content()
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

// MARK: - Sidebar Row

private struct SidebarRow<Trailing: View>: View {
    let icon: String?
    let iconView: AnyView?
    let label: String
    let isSelected: Bool
    let trailing: (() -> Trailing)?
    let action: () -> Void

    @State private var isHovered = false

    init(
        icon: String,
        label: String,
        isSelected: Bool,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconView = nil
        self.label = label
        self.isSelected = isSelected
        self.trailing = trailing
        self.action = action
    }

    init(
        iconView: AnyView,
        label: String,
        isSelected: Bool,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.icon = nil
        self.iconView = iconView
        self.label = label
        self.isSelected = isSelected
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let iconView {
                    iconView
                        .frame(width: 16, alignment: .center)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 16, alignment: .center)
                }

                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary.opacity(isSelected ? 1.0 : 0.82))
                    .lineLimit(1)

                Spacer(minLength: 0)

                trailing?()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.10)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300  // finite fallback — sidebar is never unbounded
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
