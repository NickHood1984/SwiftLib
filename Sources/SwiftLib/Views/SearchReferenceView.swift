import SwiftUI
import SwiftLibCore

struct SearchOverlay: View {
    let onSearch: (ReferenceScope, ReferenceFilter, Int) async throws -> [Reference]
    let scope: ReferenceScope
    let workspaceId: Int64?
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
        GeometryReader { geometry in
            // Scale the search panel proportionally to the window size while
            // keeping it comfortably smaller than before.
            let widthRatio: CGFloat = 0.62
            let heightRatio: CGFloat = 0.58
            let panelWidth = min(820, max(460, geometry.size.width * widthRatio))
            let panelHeight = min(560, max(380, geometry.size.height * heightRatio))

            ZStack(alignment: .top) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                searchPanel
                    .frame(width: panelWidth, height: panelHeight)
                    .padding(.top, max(20, geometry.size.height * 0.07))
            }
        }
        .onAppear {
            selectedIndex = 0
            scheduleSearch(immediate: true)
            // Defer focus to ensure the TextField is fully presented before
            // requesting first responder; setting @FocusState directly inside
            // onAppear can be ignored when the overlay is presented as a sheet
            // or transition.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
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

    private var searchPanel: some View {
        VStack(spacing: 0) {
            topSearchBar

            Divider()
                .opacity(0.55)

            filterBar

            Divider()
                .opacity(0.45)

            resultsSection

            if isMultiSelectMode && !multiSelection.isEmpty {
                Divider()
                    .opacity(0.45)
                batchActionBar
            }

            Divider()
                .opacity(0.55)

            footer
        }
        .background(notionSearchBackground)
        .overlay(notionSearchBorder)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 34, x: 0, y: 22)
    }

    private var topSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            TextField("在当前工作区中搜索文献…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .focused($isFocused)
                .onSubmit {
                    if isMultiSelectMode {
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
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }

            if isMultiSelectMode {
                HStack(spacing: 6) {
                    Text("\(multiSelection.count) 条已选")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Button {
                        clearMultiSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    @ViewBuilder
    private var resultsSection: some View {
        if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text("无匹配结果")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if query.isEmpty && !hasActiveFilters {
                            Text("最近文献")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
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
                                handleSearchTap(
                                    ref: ref,
                                    index: index,
                                    modifiers: NSApp.currentEvent?.modifierFlags ?? []
                                )
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
                .swiftLibElegantScrollers()
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
    }

    private var notionSearchBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThickMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
            )
    }

    private var notionSearchBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
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
        .background(Color.accentColor.opacity(0.08))
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
        .frame(height: 38)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterPill(
                    icon: "textformat",
                    label: "仅搜索标题",
                    isActive: titleOnly
                ) {
                    titleOnly.toggle()
                }

                FilterPillMenu(icon: "doc.text", label: typeLabel) {
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

                FilterPill(
                    icon: "paperclip",
                    label: pdfLabel,
                    isActive: hasPDF != nil
                ) {
                    hasPDF = hasPDF == true ? nil : true
                }

                YearRangePill(
                    yearFrom: $yearFrom,
                    yearTo: $yearTo,
                    label: yearLabel
                )

                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        Text("清除")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.primary.opacity(0.045), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(height: 48)
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
        return "在分组中"
    }

    private var pdfLabel: String {
        switch hasPDF {
        case true:
            return "有 PDF"
        case false:
            return "无 PDF"
        case nil:
            return "PDF"
        }
    }

    private var yearLabel: String {
        if yearFrom.isEmpty && yearTo.isEmpty {
            return "年份"
        }
        let from = yearFrom.isEmpty ? "…" : yearFrom
        let to = yearTo.isEmpty ? "…" : yearTo
        if from == to { return from }
        return "\(from) – \(to)"
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
        let scope = self.scope

        do {
            let fetched = try await onSearch(scope, filter, limit)
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
        filter.workspaceId = workspaceId
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
                .font(.system(size: 12, weight: .medium))
            Text(label)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045), in: Capsule())
        .contentShape(Capsule())
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
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Year range pill (modern web-style)

private struct YearRangePill: View {
    @Binding var yearFrom: String
    @Binding var yearTo: String
    let label: String

    @State private var isPresented = false

    private var isActive: Bool {
        !yearFrom.isEmpty || !yearTo.isEmpty
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            YearRangePopover(
                yearFrom: $yearFrom,
                yearTo: $yearTo
            )
        }
    }
}

private struct YearRangePopover: View {
    @Binding var yearFrom: String
    @Binding var yearTo: String

    @FocusState private var focusedField: Field?

    private enum Field { case from, to }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var presets: [(label: String, from: Int, to: Int)] {
        [
            ("今年", currentYear, currentYear),
            ("近 3 年", currentYear - 2, currentYear),
            ("近 5 年", currentYear - 4, currentYear),
            ("近 10 年", currentYear - 9, currentYear),
            ("近 20 年", currentYear - 19, currentYear)
        ]
    }

    private var hasValue: Bool {
        !yearFrom.isEmpty || !yearTo.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("发表年份")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if hasValue {
                    Button {
                        yearFrom = ""
                        yearTo = ""
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("重置")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom inputs
            HStack(spacing: 10) {
                yearField(text: $yearFrom, placeholder: "起始", field: .from)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                yearField(text: $yearTo, placeholder: "结束", field: .to)
            }

            // Quick presets
            VStack(alignment: .leading, spacing: 6) {
                Text("快捷选项")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                HStack(spacing: 6) {
                    ForEach(presets.indices, id: \.self) { i in
                        let preset = presets[i]
                        let selected = yearFrom == String(preset.from) && yearTo == String(preset.to)
                        Button {
                            yearFrom = String(preset.from)
                            yearTo = String(preset.to)
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selected ? Color.accentColor : .primary.opacity(0.85))
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(
                                    Capsule()
                                        .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(selected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        }
        .padding(16)
        .frame(width: 340)
    }

    private func yearField(text: Binding<String>, placeholder: String, field: Field) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: field)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(focusedField == field ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: focusedField)
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
        HStack(spacing: 12) {
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
            .frame(width: 24, height: 24)
            .animation(.easeInOut(duration: 0.15), value: isMultiSelected)

            VStack(alignment: .leading, spacing: 2) {
                Text(reference.title.decodingHTMLEntities())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 12))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        )
        .padding(.horizontal, 10)
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
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(Color.primary.opacity(0.075))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}
