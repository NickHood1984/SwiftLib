import SwiftUI
import SwiftLibCore

struct SearchOverlay: View {
    let db: AppDatabase
    let scope: ReferenceScope
    let collections: [Collection]
    @Binding var isPresented: Bool
    let onSelect: (Reference) -> Void
    var onDeleteMultiple: (([Reference]) -> Void)? = nil

    @State private var query = ""
    @FocusState private var isFocused: Bool
    @State private var selectedIndex: Int?

    // Filters
    @State private var titleOnly = false
    @State private var selectedType: ReferenceType?
    @State private var selectedCollectionId: Int64?
    @State private var hasPDF: Bool?
    @State private var yearFrom = ""
    @State private var yearTo = ""
    @State private var showFilters = false
    @State private var results: [Reference] = []
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    // Multi-selection
    @State private var multiSelection: Set<Int64> = []
    @State private var isMultiSelectMode = false
    @State private var showDeleteConfirm = false
    
    // Auto-scroll suppression flag
    @State private var keyboardNavigated = false

    private var hasActiveFilters: Bool {
        titleOnly || selectedType != nil || selectedCollectionId != nil ||
        hasPDF != nil || !yearFrom.isEmpty || !yearTo.isEmpty
    }

    private var activeFilterCount: Int {
        var c = 0
        if titleOnly { c += 1 }
        if selectedType != nil { c += 1 }
        if selectedCollectionId != nil { c += 1 }
        if hasPDF != nil { c += 1 }
        if !yearFrom.isEmpty || !yearTo.isEmpty { c += 1 }
        return c
    }

    private struct FilterState: Equatable {
        var query: String
        var selectedType: ReferenceType?
        var selectedCollectionId: Int64?
        var hasPDF: Bool?
        var titleOnly: Bool
        var yearFrom: String
        var yearTo: String
    }

    private var filterState: FilterState {
        FilterState(query: query, selectedType: selectedType, selectedCollectionId: selectedCollectionId, hasPDF: hasPDF, titleOnly: titleOnly, yearFrom: yearFrom, yearTo: yearTo)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    TextField("搜索文献…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($isFocused)
                        .onSubmit {
                            if isMultiSelectMode {
                                // In multi-select mode, Enter confirms batch open
                                openMultiSelected()
                            } else if let idx = selectedIndex, idx < results.count {
                                select(results[idx])
                            } else if let first = results.first {
                                select(first)
                            }
                        }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    // Multi-select mode indicator
                    if isMultiSelectMode {
                        HStack(spacing: 4) {
                            Text("\(multiSelection.count) 条已选")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                            Button {
                                clearMultiSelection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Filter bar
                Divider()
                filterBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                // Expanded filters
                if showFilters {
                    Divider()
                    expandedFilters
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }

                Divider()

                // Results
                if results.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("无匹配结果")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                if query.isEmpty && !hasActiveFilters {
                                    Text("最近文献")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                }
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, ref in
                                    let refId = ref.id ?? -1
                                    let isMultiSelected = multiSelection.contains(refId)

                                    SearchResultRow(
                                        reference: ref,
                                        isHighlighted: !isMultiSelectMode && selectedIndex == index,
                                        isMultiSelected: isMultiSelected
                                    )
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleSearchTap(ref: ref, index: index,
                                            modifiers: NSApp.currentEvent?.modifierFlags ?? [])
                                    }
                                    .onHover { hovering in
                                        if hovering && !isMultiSelectMode { selectedIndex = index }
                                    }
                                    .contextMenu {
                                        if isMultiSelected && multiSelection.count > 1 {
                                            Button("打开所选 \(multiSelection.count) 条") { openMultiSelected() }
                                            if onDeleteMultiple != nil {
                                                Button("删除所选 \(multiSelection.count) 条", role: .destructive) {
                                                    showDeleteConfirm = true
                                                }
                                            }
                                            Divider()
                                            Button("取消多选") { clearMultiSelection() }
                                        } else {
                                            Button("打开") { select(ref) }
                                            if onDeleteMultiple != nil {
                                                Button("删除", role: .destructive) {
                                                    onDeleteMultiple?([ref])
                                                }
                                            }
                                            Divider()
                                            Button("⌘+点击可多选") {}.disabled(true)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 360)
                        .onChange(of: selectedIndex) { _, newValue in
                            if keyboardNavigated, let idx = newValue {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo(idx, anchor: .center)
                                }
                                DispatchQueue.main.async { keyboardNavigated = false }
                            }
                        }
                    }
                }

                // Batch action bar (shown when multi-select is active)
                if isMultiSelectMode && !multiSelection.isEmpty {
                    Divider()
                    batchActionBar
                }

                // Footer
                Divider()
                footer
            }
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            isFocused = true
            selectedIndex = 0
            scheduleSearch(immediate: true)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onKeyPress(.upArrow) {
            if !isMultiSelectMode { moveSelection(-1) }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !isMultiSelectMode { moveSelection(1) }
            return .handled
        }
        .onKeyPress(.escape) {
            if isMultiSelectMode {
                clearMultiSelection()
            } else {
                close()
            }
            return .handled
        }
        .onChange(of: filterState) { oldState, newState in
            selectedIndex = 0
            if oldState.query != newState.query || 
               oldState.selectedType != newState.selectedType ||
               oldState.selectedCollectionId != newState.selectedCollectionId ||
               oldState.hasPDF != newState.hasPDF ||
               oldState.titleOnly != newState.titleOnly {
                clearMultiSelection()
            }
            scheduleSearch()
        }
        .animation(.easeInOut(duration: 0.18), value: isMultiSelectMode)
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

    // MARK: - Batch action bar

    private var batchActionBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(multiSelection.count) 条")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                selectAllResults()
            } label: {
                Text("全选 \(results.count) 条结果")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Divider().frame(height: 16)

            Button {
                openMultiSelected()
            } label: {
                Label("打开所选", systemImage: "arrow.right.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            if onDeleteMultiple != nil {
                Divider().frame(height: 16)
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            if !isMultiSelectMode {
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["↑", "↓"])
                    Text("选择")
                }
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["↩"])
                    Text("打开")
                }
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["⌘", "点击"])
                    Text("多选")
                }
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["esc"])
                    Text("关闭")
                }
            } else {
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["⌘", "A"])
                    Text("全选结果")
                }
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["↩"])
                    Text("打开所选")
                }
                HStack(spacing: 4) {
                    KeyboardHint(symbols: ["esc"])
                    Text("取消多选")
                }
            }
            Spacer()
            if !results.isEmpty {
                Text("\(results.count) 条结果")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            FilterPill(
                icon: "character.cursor.ibeam",
                label: "仅标题",
                isActive: titleOnly
            ) {
                titleOnly.toggle()
            }

            FilterPillMenu(icon: "doc.on.doc", label: typeLabel) {
                Button("全部类型") { selectedType = nil }
                Divider()
                ForEach(ReferenceType.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        Label(type.rawValue, systemImage: type.icon)
                    }
                }
            }

            if !collections.isEmpty {
                FilterPillMenu(icon: "folder", label: collectionLabel) {
                    Button("全部分组") { selectedCollectionId = nil }
                    Divider()
                    ForEach(collections) { col in
                        Button {
                            selectedCollectionId = col.id
                        } label: {
                            Label(col.name, systemImage: col.icon)
                        }
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFilters.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("筛选")
                    if activeFilterCount > 0 {
                        Text("(\(activeFilterCount))")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(showFilters ? .primary : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(showFilters ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            if hasActiveFilters {
                Button {
                    clearFilters()
                } label: {
                    Text("清除")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Expanded filters

    private var expandedFilters: some View {
        VStack(spacing: 10) {
            // Has PDF
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .font(.caption)
                Picker("PDF", selection: $hasPDF) {
                    Text("不限").tag(nil as Bool?)
                    Text("有 PDF").tag(true as Bool?)
                    Text("无 PDF").tag(false as Bool?)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Spacer()
            }

            // Year range
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .font(.caption)
                TextField("起始年份", text: $yearFrom)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("—")
                    .foregroundStyle(.tertiary)
                TextField("结束年份", text: $yearTo)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var typeLabel: String {
        selectedType?.rawValue ?? "类型"
    }

    private var collectionLabel: String {
        if let id = selectedCollectionId,
           let col = collections.first(where: { $0.id == id }) {
            return col.name
        }
        return "分组"
    }

    private func clearFilters() {
        titleOnly = false
        selectedType = nil
        selectedCollectionId = nil
        hasPDF = nil
        yearFrom = ""
        yearTo = ""
        scheduleSearch(immediate: true)
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    @MainActor
    private func runSearch() async {
        let limit = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasActiveFilters ? 20 : 0
        let filter = buildFilter()
        let db = self.db
        let scope = self.scope

        do {
            let fetched: [Reference] = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let refs = try db.fetchReferences(scope: scope, filter: filter, limit: limit)
                        continuation.resume(returning: refs)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            results = fetched
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func buildFilter() -> ReferenceFilter {
        var filter = ReferenceFilter()
        filter.keyword = query
        filter.referenceType = selectedType
        filter.hasPDF = hasPDF
        filter.collectionId = selectedCollectionId
        filter.titleOnly = titleOnly
        filter.yearFrom = Int(yearFrom)
        filter.yearTo = Int(yearTo)
        return filter
    }

    private func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        keyboardNavigated = true
        if let current = selectedIndex {
            selectedIndex = max(0, min(count - 1, current + delta))
        } else {
            selectedIndex = delta > 0 ? 0 : count - 1
        }
    }

    private func handleSearchTap(ref: Reference, index: Int, modifiers: NSEvent.ModifierFlags) {
        guard let refId = ref.id else { return }

        if modifiers.contains(.command) {
            withAnimation(.easeInOut(duration: 0.12)) {
                if multiSelection.contains(refId) {
                    multiSelection.remove(refId)
                    if multiSelection.isEmpty { isMultiSelectMode = false }
                } else {
                    multiSelection.insert(refId)
                    isMultiSelectMode = true
                }
            }
        } else if isMultiSelectMode {
            // In multi-select mode, normal click toggles
            withAnimation(.easeInOut(duration: 0.12)) {
                if multiSelection.contains(refId) {
                    multiSelection.remove(refId)
                    if multiSelection.isEmpty { isMultiSelectMode = false }
                } else {
                    multiSelection.insert(refId)
                }
            }
        } else {
            select(ref)
        }
    }

    private func selectAllResults() {
        withAnimation(.easeInOut(duration: 0.15)) {
            multiSelection = Set(results.compactMap(\.id))
            isMultiSelectMode = true
        }
    }

    private func clearMultiSelection() {
        withAnimation(.easeInOut(duration: 0.15)) {
            multiSelection.removeAll()
            isMultiSelectMode = false
        }
    }

    private func openMultiSelected() {
        // Open the first selected item and navigate to it;
        // for multi-open, select the first and close overlay
        let selected = results.filter { multiSelection.contains($0.id ?? -1) }
        guard let first = selected.first else { return }
        onSelect(first)
        close()
    }

    private func batchDelete() {
        let toDelete = results.filter { multiSelection.contains($0.id ?? -1) }
        clearMultiSelection()
        onDeleteMultiple?(toDelete)
        close()
    }

    private func select(_ ref: Reference) {
        onSelect(ref)
        close()
    }

    private func close() {
        isPresented = false
    }
}

// MARK: - Filter pill components

private struct FilterPill: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            pillContent
        }
        .buttonStyle(.plain)
    }

    private var pillContent: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
        }
        .font(.system(size: 12))
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct FilterPillMenu<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - SearchResultRow

private struct SearchResultRow: View {
    let reference: Reference
    let isHighlighted: Bool
    var isMultiSelected: Bool = false

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

            VStack(alignment: .leading, spacing: 2) {
                Text(reference.title)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if reference.pdfPath != nil {
                Image(systemName: "paperclip")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isMultiSelected)
    }

    private var rowBackground: Color {
        if isMultiSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHighlighted {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - KeyboardHint

private struct KeyboardHint: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
    }
}
