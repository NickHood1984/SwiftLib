import SwiftUI
import SwiftLibCore

// MARK: - ReferenceListView
//
// 信息密度优先的表格视图：基于真实用户反馈（Zotero 论坛、Reddit、中文
// 社区等对「列表信息密度低 / 无法自定义列」的广泛抱怨）重构而成。
// 默认展示 5 列：标题（含类型图标）/ 作者 / 年份 / 期刊 / 验证状态圆点。
// 其余列（类型文字、添加时间）可通过列头右键菜单开启并自动持久化。

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
    var onTranslateAbstract: ((Int64) -> Void)? = nil

    // Table-native selection. Optional Int64 because ReferenceListRow.id is Int64?.
    @State private var tableSelection: Set<Int64?> = []

    // Sort order persisted in the scene. Defaults to most-recently-added first.
    @State private var sortOrder: [KeyPathComparator<ReferenceListRow>] = [
        KeyPathComparator(\ReferenceListRow.dateAdded, order: .reverse)
    ]

    // Column visibility / ordering / width. Stored per-scene so it persists
    // across relaunches but doesn't leak between different windows.
    @SceneStorage("ReferenceListView.tableColumnCustomization")
    private var tableCustomization: TableColumnCustomization<ReferenceListRow>

    // Delete confirmation
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteIDs: Set<Int64> = []

    // Computed helpers
    private var selectedIDs: Set<Int64> { Set(tableSelection.compactMap { $0 }) }
    private var isMultiSelectMode: Bool { selectedIDs.count > 1 }

    private var displayedReferences: [ReferenceListRow] {
        sortOrder.isEmpty ? references : references.sorted(using: sortOrder)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if references.isEmpty {
                emptyState
            } else {
                tableContent
                if isMultiSelectMode {
                    batchToolbar
                }
            }
        }
        .navigationTitle("文献")
        .navigationSubtitle(subtitleText)
        // ⌘A: select all
        .onKeyPress(.init("a"), phases: .down) { event in
            if event.modifiers.contains(.command) {
                tableSelection = Set(references.map { $0.id })
                return .handled
            }
            return .ignored
        }
        // Esc: clear selection
        .onKeyPress(.escape) {
            if !tableSelection.isEmpty {
                tableSelection.removeAll()
                return .handled
            }
            return .ignored
        }
        // Inner -> outer: propagate single-selection to parent detail pane.
        .onChange(of: tableSelection) { _, newValue in
            let ids = newValue.compactMap { $0 }
            if ids.count == 1, let only = ids.first, only != selectedId {
                onSelect(only)
            }
        }
        // Outer -> inner: keep table selection aligned with external single-select
        // (e.g. after add/clip/import sets `selectedId` programmatically).
        .onChange(of: selectedId) { _, newId in
            guard let id = newId else { return }
            if selectedIDs.count <= 1 && !tableSelection.contains(id) {
                tableSelection = [id]
            }
        }
        .confirmationDialog(
            "删除 \(pendingDeleteIDs.count) 条文献？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                let ids = pendingDeleteIDs
                pendingDeleteIDs.removeAll()
                tableSelection.removeAll()
                onDelete(ids)
            }
            Button("取消", role: .cancel) { pendingDeleteIDs.removeAll() }
        } message: {
            Text("此操作不可撤销。")
        }
    }

    // MARK: - Empty state

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

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        Table(
            displayedReferences,
            selection: $tableSelection,
            sortOrder: $sortOrder,
            columnCustomization: $tableCustomization
        ) {
            // 标题（含类型图标、PDF 徽章、期刊分区徽章）
            TableColumn("标题", value: \.title) { ref in
                HStack(spacing: 6) {
                    Image(systemName: ref.referenceType.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .center)
                        .help(ref.referenceType.rawValue)

                    Text(ref.title)
                        .font(.system(.callout, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .onAppear { onLoadMore?(ref) }
            }
            .width(min: 180, ideal: 260)
            .customizationID("title")

            // 作者
            TableColumn("作者", value: \.primaryAuthorFamily) { ref in
                Text(ref.authorsSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120, max: 200)
            .customizationID("authors")

            // 年份
            TableColumn("年份", value: \.year, comparator: OptionalComparator()) { ref in
                Text(ref.year.map(String.init) ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 72)
            .customizationID("year")

            // 期刊 / 来源
            TableColumn("期刊 / 来源", value: \.journal, comparator: OptionalComparator()) { ref in
                Text(ref.journal ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 100, ideal: 160, max: 280)
            .customizationID("journal")

            // 验证状态（彩色圆点 + tooltip）
            TableColumn("状态", value: \.verificationStatus.sortRank) { ref in
                VerificationDot(row: ref)
            }
            .width(40)
            .customizationID("status")

            // 可选列：类型文字（默认隐藏，用户可通过列头右键开启）
            TableColumn("类型", value: \.referenceType.rawValue) { ref in
                Text(ref.referenceType.rawValue)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 110, max: 180)
            .customizationID("type")
            .defaultVisibility(.hidden)

            // 可选列：添加时间（默认隐藏）
            TableColumn("添加时间", value: \.dateAdded) { ref in
                Text(ref.dateAdded, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 140)
            .customizationID("dateAdded")
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: Int64?.self) { ids in
            contextMenuContents(for: Set(ids.compactMap { $0 }))
        } primaryAction: { ids in
            if let only = ids.compactMap({ $0 }).first {
                onDoubleClick?(only)
            }
        }
        .swiftLibElegantScrollers()
    }

    // MARK: - Context Menu Builder

    @ViewBuilder
    private func contextMenuContents(for ids: Set<Int64>) -> some View {
        if ids.count > 1 {
            Button("刷新所选 \(ids.count) 条元数据") {
                onRefreshMetadata(ids)
            }
            .disabled(isRefreshingMetadata)
            Divider()
            moveToCollectionMenu(ids: ids)
            Divider()
            Button("删除所选 \(ids.count) 条", role: .destructive) {
                pendingDeleteIDs = ids
                showDeleteConfirm = true
            }
        } else if let only = ids.first {
            Button("刷新元数据") { onRefreshMetadata([only]) }
                .disabled(isRefreshingMetadata)
            if let onTranslateAbstract {
                Divider()
                Button("翻译摘要") {
                    onTranslateAbstract(only)
                }
            }
            Divider()
            moveToCollectionMenu(ids: [only])
            Divider()
            Button("删除", role: .destructive) {
                pendingDeleteIDs = [only]
                showDeleteConfirm = true
            }
            Divider()
            Button("⌘+点击可多选") {}.disabled(true)
        }
    }

    @ViewBuilder
    private func moveToCollectionMenu(ids: Set<Int64>) -> some View {
        Menu("移动到…") {
            Button("移出分组（无分组）") { onMove(ids, nil) }
            if !collections.isEmpty { Divider() }
            ForEach(collections) { col in
                Button(col.name) { onMove(ids, col.id) }
            }
        }
    }

    // MARK: - Batch toolbar (shown only when >1 items selected)

    private var batchToolbar: some View {
        HStack(spacing: 10) {
            Text("\(selectedIDs.count) 条已选")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()

            let allSelected = !references.isEmpty && selectedIDs.count == references.count
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if allSelected {
                        tableSelection.removeAll()
                    } else {
                        tableSelection = Set(references.map { $0.id })
                    }
                }
            } label: {
                Text(allSelected ? "全不选" : "全选")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            Button(role: .destructive) {
                pendingDeleteIDs = selectedIDs
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)

            Divider().frame(height: 16)

            Button {
                onRefreshMetadata(selectedIDs)
            } label: {
                Label("刷新元数据", systemImage: "arrow.clockwise").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isRefreshingMetadata)

            Divider().frame(height: 16)

            Menu {
                Button("移出分组（无分组）") { onMove(selectedIDs, nil) }
                if !collections.isEmpty { Divider() }
                ForEach(collections) { col in
                    Button(col.name) { onMove(selectedIDs, col.id) }
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
                tableSelection.removeAll()
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.18), value: selectedIDs.count)
    }

    // MARK: - Derived helpers

    private var subtitleText: String {
        if isMultiSelectMode {
            return "已选 \(selectedIDs.count) / \(references.count) 条"
        }
        return "\(references.count) 条"
    }

    // journalRankJSON is available on ReferenceListRow but kept off the
    // title column to avoid visual noise. Rank badges appear in the detail
    // panel instead.
}

// MARK: - VerificationDot

private struct VerificationDot: View {
    let row: ReferenceListRow

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .help(tooltip)
    }

    // 颜色判定：只根据「事实」，不依赖可能过期的 verificationStatus。
    // - 绿色：有 metadataSource（走过权威数据源管线）/ 有 DOI / 被手动验证
    // - 黄色：队列中的候选、无来源无 DOI 的条目
    private var color: Color {
        // 1. 队列中等待确认 → 黄色（哪怕已有来源也要用户先确认）
        if row.verificationStatus == .candidate || row.verificationStatus == .blocked {
            return .yellow
        }
        // 2. 显式手动验证 → 绿色
        if row.verificationStatus == .verifiedAuto || row.verificationStatus == .verifiedManual {
            return .green
        }
        // 3. 事实判定：有来源 或 有 DOI → 认为是验证过
        let hasSource = row.metadataSource != nil
        let hasDOI = !(row.doi?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        return (hasSource || hasDOI) ? .green : .yellow
    }

    private var tooltip: String {
        color == .green ? "已验证" : "未验证"
    }
}

// MARK: - OptionalComparator
//
// Lets TableColumn sort on optional values (year, journal, …). Nil values
// always sink to the bottom regardless of sort direction, which matches how
// Finder and most spreadsheet apps behave.

private struct OptionalComparator<Value: Comparable>: SortComparator {
    typealias Compared = Value?
    var order: SortOrder = .forward

    func compare(_ lhs: Value?, _ rhs: Value?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (l?, r?):
            let ascending: ComparisonResult = l < r ? .orderedAscending
                                            : l > r ? .orderedDescending
                                            : .orderedSame
            if order == .reverse {
                switch ascending {
                case .orderedAscending: return .orderedDescending
                case .orderedDescending: return .orderedAscending
                case .orderedSame: return .orderedSame
                }
            }
            return ascending
        }
    }
}

// MARK: - Row / status sort helpers

private extension ReferenceListRow {
    /// 作者列显示：
    /// - 优先用 family；若 family 看起来是「缩写」（如单字母 / 全大写 ≤4 字符），
    ///   说明数据被错误地解析为 family，回退用 given。
    /// - 多作者时，中文用「等」，英文用「et al.」。
    var authorsSummary: String {
        guard !authors.isEmpty else { return "—" }
        let name = primaryAuthorDisplayName
        guard authors.count > 1 else { return name }
        let isChinese = name.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        return isChinese ? "\(name) 等" : "\(name) et al."
    }

    /// Sort key / 显示基础名。当 family 显然是缩写时，回退到 given。
    var primaryAuthorDisplayName: String {
        guard let first = authors.first else { return "" }
        let family = first.family.trimmingCharacters(in: .whitespaces)
        let given = first.given.trimmingCharacters(in: .whitespaces)
        if Self.looksLikeInitials(family), !given.isEmpty {
            return given
        }
        return family.isEmpty ? given : family
    }

    /// Sort key 专用：无作者时返回空串，交给 OptionalComparator 逻辑之外的正常比较。
    var primaryAuthorFamily: String { primaryAuthorDisplayName }

    /// 判断是否像「缩写 / 首字母」：全大写、带点或短横，且长度 ≤ 4。
    static func looksLikeInitials(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 4 else { return false }
        let allowed: Set<Character> = [".", "-", " "]
        return s.allSatisfy { $0.isUppercase || allowed.contains($0) }
    }
}

private extension VerificationStatus {
    /// Stable sort rank: verified first, then processing, then issues, legacy last.
    var sortRank: Int {
        switch self {
        case .verifiedAuto, .verifiedManual: return 0
        case .metadataEnriching: return 1
        case .candidate, .blocked: return 2
        case .seedOnly, .rejectedAmbiguous: return 3
        case .legacy: return 4
        }
    }
}
