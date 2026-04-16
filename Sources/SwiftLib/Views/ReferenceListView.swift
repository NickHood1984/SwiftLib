import SwiftUI
import SwiftLibCore

// MARK: - ReferenceListView

struct ReferenceListView: View {
    let references: [ReferenceListRow]
    let collections: [Collection]
    let selectedId: Int64?
    let onSelect: (Int64) -> Void
    let onDelete: (Set<Int64>) -> Void
    let onMove: (Set<Int64>, Int64?) -> Void
    let onRefreshMetadata: (Set<Int64>) -> Void
    var isRefreshingMetadata = false
    var onDoubleClick: ((Int64) -> Void)? = nil
    var onLoadMore: ((ReferenceListRow) -> Void)? = nil

    // Multi-selection state
    @State private var multiSelection: Set<Int64> = []
    @State private var lastSingleClickedId: Int64? = nil
    @State private var isMultiSelectMode = false

    // Batch action sheet
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if references.isEmpty {
                emptyState
            } else {
                listContent
                if isMultiSelectMode && !multiSelection.isEmpty {
                    batchToolbar
                }
            }
        }
        .navigationTitle("文献")
        .navigationSubtitle(subtitleText)
        // ⌘A: select all
        .onKeyPress(.init("a"), phases: .down) { event in
            if event.modifiers.contains(.command) {
                selectAll()
                return .handled
            }
            return .ignored
        }
        // Escape: clear multi-selection
        .onKeyPress(.escape) {
            if isMultiSelectMode {
                clearMultiSelection()
                return .handled
            }
            return .ignored
        }
        .confirmationDialog(
            "删除 \(multiSelection.count) 条文献？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { batchDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销。")
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("暂无文献")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("点击工具栏 + 按钮添加\n或导入 .bib / .ris 文件")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(references) { ref in
                    let refId = ref.id ?? -1
                    let isSelected = selectedId == ref.id && !isMultiSelectMode
                    let isMultiSelected = multiSelection.contains(refId)

                    Button {
                        handlePrimaryClick(refId: refId, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
                    } label: {
                        ReferenceRow(
                            reference: ref,
                            isSelected: isSelected,
                            isMultiSelected: isMultiSelected
                        )
                        .equatable()
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            guard refId >= 0 else { return }
                            onDoubleClick?(refId)
                        }
                    )
                    .contextMenu {
                        if isMultiSelected && multiSelection.count > 1 {
                            Button("刷新所选 \(multiSelection.count) 条元数据") {
                                batchRefreshMetadata()
                            }
                            .disabled(isRefreshingMetadata)
                            Divider()
                            moveToCollectionMenu(forBatch: true)
                            Divider()
                            Button("删除所选 \(multiSelection.count) 条", role: .destructive) {
                                showDeleteConfirm = true
                            }
                            Divider()
                            Button("取消多选") { clearMultiSelection() }
                        } else {
                            Button("刷新元数据") {
                                if let id = ref.id { onRefreshMetadata(Set([id])) }
                            }
                            .disabled(isRefreshingMetadata)
                            Divider()
                            moveToCollectionMenu(forRefId: refId)
                            Divider()
                            Button("删除", role: .destructive) {
                                if let id = ref.id { onDelete(Set([id])) }
                            }
                            Divider()
                            Button("⌘+点击可多选") {}
                                .disabled(true)
                        }
                    }
                    .onAppear { onLoadMore?(ref) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var batchToolbar: some View {
        HStack(spacing: 10) {
            Text("\(multiSelection.count) 条已选")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            let allSelected = !references.isEmpty && multiSelection.count == references.count
            Button {
                if allSelected {
                    withAnimation(.easeInOut(duration: 0.15)) { clearMultiSelection() }
                } else {
                    selectAll()
                }
            } label: {
                Text(allSelected ? "全不选" : "全选")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Divider().frame(height: 16)
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            Divider().frame(height: 16)
            Button {
                batchRefreshMetadata()
            } label: {
                Label("刷新元数据", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isRefreshingMetadata)
            Divider().frame(height: 16)
            Menu {
                Menu {
                    Button("移出分组（无分组）") {
                        batchMove(toCollectionId: nil)
                    }
                    if !collections.isEmpty { Divider() }
                    ForEach(collections) { col in
                        Button(col.name) {
                            batchMove(toCollectionId: col.id)
                        }
                    }
                } label: {
                    Label("移动到…", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Divider().frame(height: 16)
            Button {
                clearMultiSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.18), value: multiSelection.count)
    }

    // MARK: - Move-to-collection context menus

    /// Batch move: applies to all selected items
    @ViewBuilder
    private func moveToCollectionMenu(forBatch: Bool) -> some View {
        Menu("移动到…") {
            Button("移出分组（无分组）") {
                batchMove(toCollectionId: nil)
            }
            if !collections.isEmpty { Divider() }
            ForEach(collections) { col in
                Button(col.name) {
                    batchMove(toCollectionId: col.id)
                }
            }
        }
    }

    /// Single-item move
    @ViewBuilder
    private func moveToCollectionMenu(forRefId refId: Int64) -> some View {
        Menu("移动到…") {
            Button("移出分组（无分组）") {
                onMove(Set([refId]), nil)
            }
            if !collections.isEmpty { Divider() }
            ForEach(collections) { col in
                Button(col.name) {
                    onMove(Set([refId]), col.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private var subtitleText: String {
        if isMultiSelectMode && !multiSelection.isEmpty {
            return "已选 \(multiSelection.count) / \(references.count) 条"
        }
        return "\(references.count) 条"
    }

    // MARK: - Interaction

    private func handlePrimaryClick(refId: Int64, modifiers: NSEvent.ModifierFlags) {
        guard refId >= 0 else { return }
        if modifiers.contains(.command) {
            // ⌘+click: toggle individual item
            if multiSelection.contains(refId) {
                multiSelection.remove(refId)
                if multiSelection.isEmpty { isMultiSelectMode = false }
            } else {
                multiSelection.insert(refId)
                isMultiSelectMode = true
                lastSingleClickedId = refId
            }
        } else if modifiers.contains(.shift) && isMultiSelectMode {
            // ⇧+click: range select from last clicked to this item
            if let anchorId = lastSingleClickedId,
               let anchorIdx = references.firstIndex(where: { $0.id == anchorId }),
               let targetIdx = references.firstIndex(where: { $0.id == refId }) {
                let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
                for i in range {
                    if let id = references[i].id {
                        multiSelection.insert(id)
                    }
                }
                isMultiSelectMode = true
            }
        } else {
            // Normal click: single selection, clear multi-select
            if isMultiSelectMode {
                clearMultiSelection()
            }
            onSelect(refId)
            lastSingleClickedId = refId
        }
    }

    private func selectAll() {
        withAnimation(.easeInOut(duration: 0.15)) {
            multiSelection = Set(references.compactMap(\.id))
            isMultiSelectMode = true
        }
    }

    private func clearMultiSelection() {
        multiSelection.removeAll()
        isMultiSelectMode = false
    }

    private func batchDelete() {
        let ids = multiSelection
        clearMultiSelection()
        onDelete(ids)
    }

    private func batchMove(toCollectionId: Int64?) {
        let ids = multiSelection
        clearMultiSelection()
        onMove(ids, toCollectionId)
    }

    private func batchRefreshMetadata() {
        guard !multiSelection.isEmpty else { return }
        onRefreshMetadata(multiSelection)
    }
}

// MARK: - ReferenceRow

struct ReferenceRow: View, Equatable {
    let reference: ReferenceListRow
    let isSelected: Bool
    var isMultiSelected: Bool = false

    @State private var isHovered = false

    static func == (lhs: ReferenceRow, rhs: ReferenceRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.isMultiSelected == rhs.isMultiSelected &&
        lhs.reference.id == rhs.reference.id &&
        lhs.reference.title == rhs.reference.title &&
        lhs.reference.authors == rhs.reference.authors &&
        lhs.reference.year == rhs.reference.year &&
        lhs.reference.journal == rhs.reference.journal &&
        lhs.reference.pdfPath == rhs.reference.pdfPath &&
        lhs.reference.referenceType == rhs.reference.referenceType
    }

    private var metaLine: String {
        var parts: [String] = []
        if !reference.authors.isEmpty {
            let first = reference.authors.first!.family
            parts.append(reference.authors.count > 1 ? "\(first) et al." : first)
        }
        if let year = reference.year {
            parts.append(String(year))
        }
        if let journal = reference.journal, !journal.isEmpty {
            parts.append(journal)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Multi-select checkbox indicator
            ZStack {
                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: reference.referenceType.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(width: 22, height: 22)
            .animation(.easeInOut(duration: 0.15), value: isMultiSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(reference.title)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(metaLine.isEmpty ? " " : metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if reference.pdfPath != nil {
                Image(systemName: "paperclip")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 52)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isMultiSelected {
            return Color.accentColor.opacity(0.14)
        } else if isSelected {
            return Color.primary.opacity(0.12)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        } else {
            return Color.clear
        }
    }
}
