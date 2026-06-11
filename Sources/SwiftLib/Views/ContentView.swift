import SwiftUI
import SwiftLibCore

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) var openWindow
    @StateObject var viewModel: LibraryViewModel
    @StateObject var cnkiMetadataProvider = CNKIMetadataProvider()
    @ObservedObject var baiduScholarEngine = BaiduScholarWebEngine.shared
    @AppStorage("hasPromptedCLIInstallation") private var hasPromptedCLIInstallation = false
    @State private var showCLIInstallPrompt = false
    @State private var cliInstallResult: CLIInstallResult?
    @State private var showSearch = false
    @State private var showAddReference = false
    @State private var addReferenceInitialType: ReferenceType = .journalArticle
    @State private var showWebImport = false
    @State private var showLibraryHealth = false
    @State private var showAddCollection = false
    @State private var showAddWorkspace = false
    @State private var showAddByIdentifier = false
    @State private var showBatchImport = false
    @State var pendingQueueNotice: PendingQueueNotice?
    @State var cslImportMessage: String?
    @State var columnVisibility = NavigationSplitViewVisibility.all
    @State var selectedId: Int64?
    @State var restoredWorkspaceSnapshots: Set<Int64> = []
    @State var workspaceLayoutAutosaveTask: Task<Void, Never>?
    @State var refreshTask: Task<Void, Never>?

    struct PendingQueueNotice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    var metadataResolver: MetadataResolver {
        MetadataResolver(cnkiProvider: cnkiMetadataProvider)
    }

    @State var selectedReference: Reference?

    init(initialWorkspaceID: Int64? = nil) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(initialWorkspaceID: initialWorkspaceID))
    }

    private var sidebarColumn: some View {
        SidebarView(
            workspaces: viewModel.workspaces,
            selectedWorkspaceID: viewModel.selectedWorkspaceID,
            collections: viewModel.collections,
            tags: viewModel.tags,
            titleKeywords: viewModel.titleKeywords,
            selection: $viewModel.selectedSidebar,
            referenceCount: viewModel.totalReferenceCount,
            onSelectWorkspace: { workspace in
                switchWorkspace(to: workspace)
            },
            onOpenWorkspaceInNewWindow: { workspace in
                saveCurrentWorkspaceLayoutSnapshot()
                if let id = workspace.id {
                    openWindow(value: id)
                }
            },
            onAddWorkspace: { showAddWorkspace = true },
            onDeleteCollection: { viewModel.deleteCollection(id: $0) },
            onDeleteTag: { viewModel.deleteTag(id: $0) },
            onAddCollection: { showAddCollection = true },
            onRenameCollection: { collection, newName in
                var c = collection
                c.name = newName
                viewModel.saveCollection(&c)
            }
        )
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
    }

    private var referenceListColumn: some View {
        ReferenceListView(
            references: viewModel.filteredReferences,
            collections: viewModel.collections,
            workspaces: viewModel.workspaces,
            currentWorkspaceID: viewModel.selectedWorkspaceID,
            selectedId: selectedId,
            onSelect: { selectedId = $0 },
            onDelete: { ids in deleteReferences(ids: ids) },
            onMove: { ids, colId in viewModel.moveReferences(ids: ids, toCollectionId: colId) },
            onAddToWorkspace: { ids, workspaceId in
                viewModel.addReferences(ids: ids, toWorkspaceId: workspaceId)
            },
            onRemoveFromWorkspace: { ids, workspaceId in
                viewModel.removeReferences(ids: ids, fromWorkspaceId: workspaceId)
            },
            onRefreshMetadata: { ids in refreshMetadataForIDs(ids) },
            isRefreshingMetadata: viewModel.isImporting,
            onDoubleClick: { refId in
                openReader(for: refId)
            },
            onLoadMore: { item in viewModel.loadMoreIfNeeded(currentItem: item) },
            onTranslateAbstract: { refId in
                translateAbstractForID(refId)
            }
        )
        .navigationSplitViewColumnWidth(min: 420, ideal: 640)
    }

    var body: some View {
        contentWithLifecycle
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            referenceListColumn
        } detail: {
            detailSection
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
        }
        .onChange(of: viewModel.selectedWorkspaceID) { _, newValue in
            guard let id = newValue,
                  !restoredWorkspaceSnapshots.contains(id),
                  let workspace = viewModel.workspaces.first(where: { $0.id == id }) else {
                return
            }
            applyLayoutSnapshot(from: workspace)
            restoredWorkspaceSnapshots.insert(id)
        }
        .onDisappear {
            saveCurrentWorkspaceLayoutSnapshot()
        }
        .toolbar { primaryToolbar }
    }

    @ToolbarContentBuilder
    private var primaryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showSearch = true
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .help("搜索文献")
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("搜索文献")

            Button(action: {
                addReferenceInitialType = .journalArticle
                showAddReference = true
            }) {
                Label("手动新建", systemImage: "square.and.pencil")
            }
            .help("新建一个空白条目并手动填写信息")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityLabel("手动新建文献")

            importMenu

            Button(action: { openPendingMetadataQueueWindow() }) {
                pendingQueueToolbarLabel
            }
            .help("打开待确认元数据队列，继续选候选、处理验证码或人工确认")
            .disabled(viewModel.pendingMetadataIntakes.isEmpty)
            .accessibilityLabel("待确认元数据队列")

            Button(action: { showLibraryHealth = true }) {
                Label("库体检", systemImage: "stethoscope")
            }
            .help("查看文献库健康度：验证状态、CSL 字段完整度、来源分布")
            .accessibilityLabel("文献库体检")

            Button(action: { openSettings() }) {
                Label("设置", systemImage: "gearshape")
            }
            .help("打开设置 (⌘,)")
            .accessibilityLabel("打开设置")
        }
    }

    private var importMenu: some View {
        Menu {
            Button(action: { showWebImport = true }) {
                Label("网页剪藏", systemImage: "globe")
            }
            Button(action: { showAddByIdentifier = true }) {
                Label("按标识导入…", systemImage: "text.magnifyingglass")
            }
            Button(action: { importPDFWithMetadata() }) {
                Label("导入 PDF…", systemImage: "doc.badge.plus")
            }
            Divider()
            Button("批量按标识导入…") { showBatchImport = true }
            Button("导入 BibTeX (.bib)…") { importBibTeX() }
            Button("导入 RIS (.ris)…") { importRIS() }
            Divider()
            Button("导入引文样式 (.csl)…") { importCitationStyles() }
        } label: {
            Label("导入", systemImage: "tray.and.arrow.down")
        }
        .help("导入文献或文件")
        .disabled(viewModel.isImporting)
    }

    private var pendingQueueToolbarLabel: some View {
        HStack(spacing: 6) {
            Label("待确认队列", systemImage: "clock.badge.exclamationmark")
            if !viewModel.pendingMetadataIntakes.isEmpty {
                Text("\(viewModel.pendingMetadataIntakes.count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var contentWithSheets: some View {
        splitView
        .sheet(isPresented: $showAddReference) {
            AddReferenceView(
                collections: viewModel.collections,
                allTags: viewModel.tags,
                onSave: { ref in
                    var r = ref
                    viewModel.saveManualReference(&r)
                },
                onCreateTag: { tag in
                    var t = tag
                    viewModel.saveTag(&t)
                },
                initialReferenceType: addReferenceInitialType
            )
            .swiftLibElegantScrollersInSubtree()
        }
        .sheet(isPresented: $showWebImport) {
            WebImportView(
                collections: viewModel.collections,
                onSave: { ref in
                    var r = ref
                    viewModel.saveManualReference(&r, reviewedBy: "web-import")
                }
            )
            .swiftLibElegantScrollersInSubtree()
        }
        .sheet(isPresented: $showBatchImport) {
            BatchImportView(
                resolver: metadataResolver,
                onImport: { refs in
                    viewModel.batchImportReferences(refs)
                },
                onQueueResult: { result, input in
                    queueResolutionResult(
                        result,
                        options: MetadataPersistenceOptions(
                            sourceKind: .batchIdentifier,
                            originalInput: input
                        ),
                        successMessage: "已加入待确认队列"
                    )
                }
            )
            .swiftLibElegantScrollersInSubtree()
        }
        .sheet(isPresented: $showAddByIdentifier) {
            AddByIdentifierView(
                resolver: metadataResolver,
                onSave: { ref in
                    var r = ref
                    viewModel.saveReference(&r)
                },
                onQueueResult: { result, input in
                    queueResolutionResult(
                        result,
                        options: MetadataPersistenceOptions(
                            sourceKind: .manualEntry,
                            originalInput: input
                        ),
                        successMessage: "已加入待确认队列"
                    )
                }
            )
            .swiftLibElegantScrollersInSubtree()
        }
        .sheet(isPresented: $showAddCollection) {
            AddCollectionSheet { col in
                var c = col
                viewModel.saveCollection(&c)
            }
            .swiftLibElegantScrollersInSubtree()
        }
        .sheet(isPresented: $showAddWorkspace) {
            AddWorkspaceSheet { workspace in
                var item = workspace
                viewModel.saveWorkspace(&item)
                if let id = item.id {
                    switchWorkspace(to: item)
                    restoredWorkspaceSnapshots.insert(id)
                }
            }
            .swiftLibElegantScrollersInSubtree()
        }
        .sheet(isPresented: $showLibraryHealth) {
            NavigationStack {
                LibraryHealthView()
            }
            .frame(minWidth: 500, minHeight: 460)
        }
    }

    private var contentWithLifecycle: some View {
        let base = contentWithSheets
            .overlay { searchOverlay }
            .overlay(alignment: .top) { importProgressOverlay }
            .overlay(alignment: .bottom) { cslMessageOverlay }
            .overlay(alignment: .bottomTrailing) { pendingQueueNoticeOverlay }

        return base
            .animation(.easeInOut(duration: 0.2), value: cslImportMessage)
            .animation(.easeInOut(duration: 0.2), value: pendingQueueNotice)
            .onChange(of: viewModel.references) { _, newRefs in
                syncSelectedReference(visibleRows: newRefs)
            }
            .onChange(of: selectedId) { _, newId in
                loadSelectedReference(for: newId)
                scheduleWorkspaceLayoutAutosave()
            }
            .onChange(of: viewModel.selectedSidebar) { _, _ in
                scheduleWorkspaceLayoutAutosave()
            }
            .onChange(of: viewModel.searchText) { _, _ in
                scheduleWorkspaceLayoutAutosave()
            }
            .onChange(of: columnVisibility) { _, _ in
                scheduleWorkspaceLayoutAutosave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .swiftLibClipImported)) { note in
                guard let id = note.userInfo?[SwiftLibClipImportedKeys.id] as? Int64 else { return }
                selectedId = id
                columnVisibility = .all
            }
            .alert("操作失败", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            if !hasPromptedCLIInstallation && !CLIInstaller.isInstalled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCLIInstallPrompt = true
                }
            }

            syncVerificationPanels()
        }
        .onChange(of: cnkiMetadataProvider.verificationSession) { _, session in
            presentCNKIVerificationIfNeeded(session)
        }
        .onChange(of: baiduScholarEngine.verificationSession) { _, session in
            presentBaiduVerificationIfNeeded(session)
        }
        .onDisappear {
            workspaceLayoutAutosaveTask?.cancel()
            saveCurrentWorkspaceLayoutSnapshot()
            MetadataVerificationPanels.cnki.dismiss()
            MetadataVerificationPanels.baidu.dismiss()
        }
        .alert("安装命令行工具", isPresented: $showCLIInstallPrompt) {
            Button("安装") {
                hasPromptedCLIInstallation = true
                do {
                    try CLIInstaller.install()
                    cliInstallResult = .success
                } catch {
                    cliInstallResult = .failure(error.localizedDescription)
                }
            }
            Button("暂不安装", role: .cancel) {
                hasPromptedCLIInstallation = true
            }
        } message: {
            Text("SwiftLib 提供配套的命令行工具 swiftlib-cli，可在终端中快速搜索、添加和导出文献。\n\n是否将其安装到 /usr/local/bin？安装时 macOS 可能会弹出管理员密码窗口。\n（你也可以稍后在菜单栏「CLI 工具」中安装）")
        }
        .alert(
            cliInstallResult?.isSuccess == true ? "安装成功" : "安装失败",
            isPresented: Binding(
                get: { cliInstallResult != nil },
                set: { if !$0 { cliInstallResult = nil } }
            )
        ) {
            Button("好") { cliInstallResult = nil }
        } message: {
            Text(cliInstallResult?.message ?? "")
        }
        .background(cnkiHiddenWebViewIfNeeded)
    }

    @ViewBuilder
    private var searchOverlay: some View {
        if showSearch {
            SearchOverlay(
                onSearch: { [viewModel] scope, filter, limit in
                    try viewModel.fetchReferences(scope: scope, filter: filter, limit: limit)
                },
                scope: viewModel.currentReferenceScope,
                workspaceId: viewModel.selectedWorkspaceID,
                collections: viewModel.collections,
                isPresented: $showSearch,
                onSelect: { ref in
                    selectedId = ref.id
                },
                onDeleteMultiple: { refs in
                    let ids = Set(refs.compactMap(\.id))
                    deleteReferences(ids: ids)
                }
            )
        }
    }

    @ViewBuilder
    private var importProgressOverlay: some View {
        let message = viewModel.importProgress ?? viewModel.mergeBannerMessage
        if let progress = message {
            FloatingProgressToast(
                message: progress,
                isSpinning: viewModel.isImporting,
                onCancel: viewModel.isImporting ? cancelRefresh : nil
            )
            .padding(.top, 34)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(10)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progress)
        }
    }

    @ViewBuilder
    private var cslMessageOverlay: some View {
        if let msg = cslImportMessage {
            Text(msg)
                .font(.slBodyMedium)
                .foregroundStyle(.primary)
                .padding(.horizontal, SLDesign.Spacing.xl)
                .padding(.vertical, SLDesign.Spacing.lg)
                .slOverlaySurface()
                .padding(.bottom, SLDesign.Spacing.xxxl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var pendingQueueNoticeOverlay: some View {
        if let notice = pendingQueueNotice {
            VStack(alignment: .leading, spacing: SLDesign.Spacing.lg) {
                HStack(alignment: .top, spacing: SLDesign.Spacing.lg) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: SLDesign.Spacing.xs) {
                        Text(notice.title)
                            .font(.slSubheadline)
                        Text(notice.message)
                            .font(.slBody)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        pendingQueueNotice = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Button("打开待确认队列") {
                        pendingQueueNotice = nil
                        openPendingMetadataQueueWindow()
                    }
                    .buttonStyle(SLPrimaryButtonStyle())

                    Button("稍后处理") {
                        pendingQueueNotice = nil
                    }
                    .buttonStyle(SLSecondaryButtonStyle())
                }
            }
            .padding(14)
            .frame(maxWidth: 360, alignment: .leading)
            .slOverlaySurface()
            .padding(.trailing, SLDesign.Spacing.xxxl)
            .padding(.bottom, SLDesign.Spacing.xxxl)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var cnkiHiddenWebViewIfNeeded: some View {
        if cnkiMetadataProvider.needsWebView {
            HiddenWKWebViewHost(
                configure: cnkiMetadataProvider.configureWebView(_:),
                onCreate: { webView in
                    cnkiMetadataProvider.registerWebView(webView)
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
        }
    }

    private func syncVerificationPanels() {
        presentCNKIVerificationIfNeeded(cnkiMetadataProvider.verificationSession)
        presentBaiduVerificationIfNeeded(baiduScholarEngine.verificationSession)
    }

    private func presentBaiduVerificationIfNeeded(_ session: BaiduScholarWebEngine.VerificationSession?) {
        guard let session else {
            MetadataVerificationPanels.baidu.dismiss()
            return
        }

        MetadataVerificationPanels.baidu.present(title: session.title, onClose: {
            baiduScholarEngine.cancelVerification()
        }) {
            BaiduScholarVerificationSheet(
                provider: baiduScholarEngine,
                session: session
            )
        }
    }

    private func presentCNKIVerificationIfNeeded(_ session: CNKIMetadataProvider.VerificationSession?) {
        guard let session else {
            MetadataVerificationPanels.cnki.dismiss()
            return
        }

        MetadataVerificationPanels.cnki.present(title: session.title, onClose: {
            cnkiMetadataProvider.cancelVerification()
        }) {
            CNKIVerificationSheet(
                provider: cnkiMetadataProvider,
                session: session
            )
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        if let ref = selectedReference {
            ReferenceDetailView(
                reference: ref,
                collections: viewModel.collections,
                allTags: viewModel.tags,
                onLoadSupplementary: { [viewModel] (id: Int64) in
                    guard let tags = try? viewModel.fetchTags(forReference: id) else { return nil }
                    let pdfCount = (try? viewModel.annotationCount(referenceId: id)) ?? 0
                    let webCount = (try? viewModel.webAnnotationCount(referenceId: id)) ?? 0
                    let hasStored = (try? viewModel.hasWebContent(id: id)) ?? false
                    return ReferenceDetailSupplementaryData(
                        tags: tags,
                        pdfAnnotationCount: pdfCount,
                        webAnnotationCount: webCount,
                        hasStoredWebContent: hasStored
                    )
                },
                onLoadWebContent: { [viewModel] (id: Int64) in
                    try? viewModel.fetchWebContent(id: id)
                },
                onSave: { updated in
                    var r = updated
                    viewModel.saveReference(&r)
                    selectedReference = r
                },
                onDelete: {
                    if let id = ref.id {
                        deleteReferences(ids: Set([id]))
                    }
                },
                onOpenPDFReader: { r in
                    ReaderWindowManager.shared.openPDFReader(for: r)
                },
                onOpenWebReader: { r in
                    ReaderWindowManager.shared.openWebReader(for: r)
                }
            )
            .swiftLibElegantScrollersInSubtree()
        } else if selectedId != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("选择一篇文献")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("共 \(viewModel.totalReferenceCount) 篇文献")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

}

// MARK: - CLI Install Result

private enum CLIInstallResult {
    case success
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .success:
            return "命令行工具已安装到 \(CLIInstaller.installURL.path)\n\n你现在可以在终端中使用 swiftlib-cli 命令了。"
        case .failure(let reason):
            return "安装失败：\(reason)\n\n你可以稍后在菜单栏「CLI 工具」中重试，或手动复制。"
        }
    }
}
