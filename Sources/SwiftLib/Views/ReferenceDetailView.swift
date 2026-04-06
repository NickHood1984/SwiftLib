import SwiftUI
import PDFKit
import SwiftLibCore

struct ReferenceDetailView: View {
    let reference: Reference
    let collections: [Collection]
    let allTags: [Tag]
    let db: AppDatabase
    let onSave: (Reference) -> Void
    let onDelete: () -> Void
    var onOpenPDFReader: ((Reference) -> Void)?
    var onOpenWebReader: ((Reference) -> Void)?

    @State private var isEditing = false
    @State private var editedRef: Reference
    @State private var previewWindow: NSWindow?
    @State private var previewWindowCloseObserver: NSObjectProtocol?
    @State private var referenceTags: [Tag] = []
    @State private var pdfAnnotationCount: Int = 0
    @State private var webAnnotationCount: Int = 0
    @State private var hasStoredWebContent = false
    @State private var isLoadingWebContent = false

    init(reference: Reference, collections: [Collection], allTags: [Tag], db: AppDatabase, onSave: @escaping (Reference) -> Void, onDelete: @escaping () -> Void, onOpenPDFReader: ((Reference) -> Void)? = nil, onOpenWebReader: ((Reference) -> Void)? = nil) {
        self.reference = reference
        self.collections = collections
        self.allTags = allTags
        self.db = db
        self.onSave = onSave
        self.onDelete = onDelete
        self.onOpenPDFReader = onOpenPDFReader
        self.onOpenWebReader = onOpenWebReader
        self._editedRef = State(initialValue: reference)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isEditing {
                    editView
                } else {
                    displayView
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            if !isEditing, reference.pdfPath != nil {
                quickPreviewShortcut
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "完成" : "编辑") {
                    Task {
                        if isEditing {
                            await saveEdits()
                        } else {
                            isEditing = true
                            await loadWebContentIfNeeded()
                        }
                    }
                }
            }
        }
        .onChange(of: reference) { oldRef, newRef in
            closeQuickPreviewWindow()
            editedRef = newRef
            isEditing = false
            guard oldRef.id != newRef.id else { return }
            referenceTags = []
            pdfAnnotationCount = 0
            webAnnotationCount = 0
            hasStoredWebContent = false
            isLoadingWebContent = false
        }
        .task(id: reference.id) {
            await loadSupplementaryData(for: reference.id)
        }
        .onDisappear { closeQuickPreviewWindow() }
    }

    // MARK: - Display View
    @ViewBuilder
    private var displayView: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header: badge / title / authors / publication line ──
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Label(reference.referenceType.rawValue, systemImage: reference.referenceType.icon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    if let source = reference.metadataSource {
                        Text(source.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Text(reference.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)

                if !reference.authors.isEmpty {
                    Text(reference.authors.displayString)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Publication line — only rendered when at least one field is present
                let pubParts: [String] = [
                    reference.journal.flatMap { $0.isEmpty ? nil : $0 },
                    reference.volume.map { "Vol. \($0)" },
                    reference.issue.map { "(\($0))" },
                    reference.pages.map { "pp. \($0)" },
                    reference.year.map { "(\(String($0)))" }
                ].compactMap { $0 }
                if !pubParts.isEmpty {
                    HStack(spacing: 8) {
                        if let journal = reference.journal, !journal.isEmpty {
                            Text(journal).italic()
                        }
                        if let vol = reference.volume { Text("Vol. \(vol)") }
                        if let issue = reference.issue { Text("(\(issue))") }
                        if let pages = reference.pages { Text("pp. \(pages)") }
                        if let year = reference.year { Text("(\(String(year)))") }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            // ── Identifiers card (DOI / URL) ──
            let hasDOI = reference.doi.map { !$0.isEmpty } ?? false
            let hasURL = (reference.url.map { !$0.isEmpty } ?? false)
            if hasDOI || hasURL {
                VStack(alignment: .leading, spacing: 8) {
                    if let doi = reference.doi, !doi.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Text("DOI")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                            Link(doi, destination: URL(string: "https://doi.org/\(doi)") ?? URL(string: "https://doi.org")!)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if let url = reference.url, !url.isEmpty, let u = URL(string: url) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("URL")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                            urlSection(url: u)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 10)
            }

            // ── Metadata + Tags card ──
            let metaRows = metadataRows(for: reference)
            let hasTags = !referenceTags.isEmpty
            if !metaRows.isEmpty || hasTags {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(metaRows, id: \.label) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                            Text(row.value)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if hasTags {
                        if !metaRows.isEmpty { Divider() }
                        HStack(alignment: .top, spacing: 10) {
                            Text("标签")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                            HStack(spacing: 4) {
                                ForEach(referenceTags) { tag in
                                    Text(tag.name)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: tag.color).opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 10)
            }

            // ── Web reader card ──
            if canOpenWebReader {
                let hasClip = hasStoredWebContent
                HStack(spacing: 10) {
                    Image(systemName: hasClip ? "doc.text.image" : "safari")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasClip ? "网页正文已就绪（剪藏）" : "可在线阅读原文")
                            .font(.callout)
                        if webAnnotationCount > 0 {
                            Text("\(webAnnotationCount) 条标注")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task {
                            guard let prepared = await prepareReferenceForWebReader() else { return }
                            onOpenWebReader?(prepared)
                        }
                    } label: {
                        Label("阅读网页", systemImage: "text.book.closed")
                    }
                    .buttonStyle(SLPrimaryButtonStyle())
                    .controlSize(.small)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 10)
            }

            // ── PDF card ──
            if reference.pdfPath != nil {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已附加 PDF")
                            .font(.callout)
                        if pdfAnnotationCount > 0 {
                            Text("\(pdfAnnotationCount) 条标注")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        onOpenPDFReader?(reference)
                    } label: {
                        Label("阅读 & 标注", systemImage: "book.pages")
                    }
                    .buttonStyle(SLPrimaryButtonStyle())
                    .controlSize(.small)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 10)
            }

            // ── Abstract ──
            if let abstract = reference.abstract, !abstract.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("摘要")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(abstract)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 14)
            }

            // ── Notes ──
            if let notes = reference.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reference.referenceType == .webpage ? "高亮与笔记" : "笔记")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 14)
            }

            // ── Footer ──
            HStack {
                Text("添加于 \(reference.dateAdded.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("删除文献", role: .destructive) {
                    onDelete()
                }
                .buttonStyle(SLDestructiveButtonStyle())
            }
            .font(.caption)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func urlSection(url: URL) -> some View {
        HStack(spacing: 6) {
            Link(destination: url) {
                Text(shortURLLabel(for: url))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)

            Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("在浏览器中打开")
        }
    }

    private var quickPreviewShortcut: some View {
        Button {
            openQuickPreviewWindow()
        } label: {
            EmptyView()
        }
        .keyboardShortcut(.space, modifiers: [])
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func openQuickPreviewWindow() {
        guard let path = reference.pdfPath else { return }
        let url = PDFService.pdfURL(for: path)
        let minimumSize = NSSize(width: 760, height: 900)
        let preferredSize = preferredQuickPreviewWindowSize(minimumSize: minimumSize)
        let autosaveName = "SwiftLibPDFQuickPreview"

        if let previewWindow {
            if previewWindow.isVisible && !previewWindow.isMiniaturized {
                closeQuickPreviewWindow()
                return
            }

            previewWindow.deminiaturize(nil)
            enforceQuickPreviewWindowSizeIfNeeded(previewWindow, minimumSize: minimumSize, preferredSize: preferredSize)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = quickPreviewWindowTitle(fallbackURL: url)
        window.isReleasedWhenClosed = false
        window.minSize = minimumSize
        window.setFrameAutosaveName(autosaveName)
        let restoredFrame = window.setFrameUsingName(autosaveName)
        enforceQuickPreviewWindowSizeIfNeeded(window, minimumSize: minimumSize, preferredSize: preferredSize)

        window.contentViewController = NSHostingController(
            rootView: PDFPreviewView(url: url) {
                window.close()
            }
        )
        if !restoredFrame {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        previewWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            previewWindow = nil
            if let observer = previewWindowCloseObserver {
                NotificationCenter.default.removeObserver(observer)
                previewWindowCloseObserver = nil
            }
        }

        previewWindow = window
    }

    private func quickPreviewWindowTitle(fallbackURL url: URL) -> String {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? url.lastPathComponent : title
    }

    private func preferredQuickPreviewWindowSize(minimumSize: NSSize) -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let width = min(max(minimumSize.width, 920), max(minimumSize.width, visibleFrame.width - 120))
        let height = min(max(minimumSize.height, 1100), max(minimumSize.height, visibleFrame.height - 120))
        return NSSize(width: width, height: height)
    }

    private func enforceQuickPreviewWindowSizeIfNeeded(_ window: NSWindow, minimumSize: NSSize, preferredSize: NSSize) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let currentFrame = window.frame

        guard currentFrame.width < minimumSize.width || currentFrame.height < minimumSize.height else {
            return
        }

        let safeWidth = min(max(preferredSize.width, minimumSize.width), visibleFrame.width - 40)
        let safeHeight = min(max(preferredSize.height, minimumSize.height), visibleFrame.height - 40)
        let origin = NSPoint(
            x: visibleFrame.midX - safeWidth / 2,
            y: visibleFrame.midY - safeHeight / 2
        )

        window.setFrame(NSRect(origin: origin, size: NSSize(width: safeWidth, height: safeHeight)), display: false)
    }

    private func closeQuickPreviewWindow() {
        previewWindow?.close()
        previewWindow = nil
        if let observer = previewWindowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            previewWindowCloseObserver = nil
        }
    }

    private func prettyURLTitle(for url: URL) -> String {
        let host = displayHost(for: url)
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || path == "/" {
            return host
        }
        let lastPath = path.split(separator: "/").last.map(String.init) ?? path
        if lastPath.isEmpty {
            return host
        }
        return "\(host)/\(lastPath)"
    }

    private func shortURLLabel(for url: URL) -> String {
        let host = displayHost(for: url)
        let components = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }

        guard !components.isEmpty else { return host }

        let summary: String
        if components.count == 1 {
            summary = components[0]
        } else {
            summary = components.suffix(2).joined(separator: "/")
        }

        return "\(host)/\(summary)"
    }

    private func compactURLSubtitle(for url: URL) -> String {
        var parts: [String] = [displayHost(for: url)]

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            parts.append("/" + path)
        }

        if let query = url.query, !query.isEmpty {
            parts.append("?" + abbreviatedQuery(query))
        }

        return parts.joined()
    }

    private func displayHost(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }

    private func abbreviatedQuery(_ query: String) -> String {
        let items = query.split(separator: "&").map(String.init)
        guard !items.isEmpty else { return query }
        if items.count == 1 {
            return abbreviateQueryItem(items[0])
        }
        return ([abbreviateQueryItem(items[0]), "\(items.count - 1) more"]).joined(separator: " · ")
    }

    private func abbreviateQueryItem(_ item: String) -> String {
        guard let equalsIndex = item.firstIndex(of: "=") else {
            return item
        }
        let key = String(item[..<equalsIndex])
        let value = String(item[item.index(after: equalsIndex)...])
        guard value.count > 18 else { return item }
        return "\(key)=\(value.prefix(8))...\(value.suffix(6))"
    }

    // MARK: - Edit View
    @ViewBuilder
    private var editView: some View {
        Form {
            Section("基本信息") {
                Picker("Type", selection: $editedRef.referenceType) {
                    ForEach(ReferenceType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                TextField("Title", text: $editedRef.title)
                TextField("Authors", text: Binding(
                    get: { editedRef.authors.displayString },
                    set: { editedRef.authors = AuthorName.parseList($0) }
                ))
                TextField("Year", value: $editedRef.year, format: .number)
            }

            Section("出版信息") {
                TextField("Journal / Book Title", text: Binding(
                    get: { editedRef.journal ?? "" },
                    set: { editedRef.journal = $0.isEmpty ? nil : $0 }
                ))
                if editedRef.referenceType == .webpage {
                    TextField("Site Name", text: Binding(
                        get: { editedRef.siteName ?? "" },
                        set: { editedRef.siteName = $0.isEmpty ? nil : $0 }
                    ))
                }
                HStack {
                    TextField("Volume", text: Binding(
                        get: { editedRef.volume ?? "" },
                        set: { editedRef.volume = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Issue", text: Binding(
                        get: { editedRef.issue ?? "" },
                        set: { editedRef.issue = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Pages", text: Binding(
                        get: { editedRef.pages ?? "" },
                        set: { editedRef.pages = $0.isEmpty ? nil : $0 }
                    ))
                }
                TextField("Publisher", text: Binding(
                    get: { editedRef.publisher ?? "" },
                    set: { editedRef.publisher = $0.isEmpty ? nil : $0 }
                ))
                HStack {
                    TextField("Publisher Place", text: Binding(
                        get: { editedRef.publisherPlace ?? "" },
                        set: { editedRef.publisherPlace = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Edition", text: Binding(
                        get: { editedRef.edition ?? "" },
                        set: { editedRef.edition = $0.isEmpty ? nil : $0 }
                    ))
                }
                if editedRef.referenceType == .conferencePaper {
                    TextField("Event Title", text: Binding(
                        get: { editedRef.eventTitle ?? "" },
                        set: { editedRef.eventTitle = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Event Place", text: Binding(
                        get: { editedRef.eventPlace ?? "" },
                        set: { editedRef.eventPlace = $0.isEmpty ? nil : $0 }
                    ))
                }
                if editedRef.referenceType == .thesis {
                    TextField("Institution", text: Binding(
                        get: { editedRef.institution ?? "" },
                        set: { editedRef.institution = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Genre / Thesis Type", text: Binding(
                        get: { editedRef.genre ?? "" },
                        set: { editedRef.genre = $0.isEmpty ? nil : $0 }
                    ))
                }
            }

            Section("标识符") {
                TextField("DOI", text: Binding(
                    get: { editedRef.doi ?? "" },
                    set: { editedRef.doi = $0.isEmpty ? nil : $0 }
                ))
                TextField("ISBN", text: Binding(
                    get: { editedRef.isbn ?? "" },
                    set: { editedRef.isbn = $0.isEmpty ? nil : $0 }
                ))
                TextField("ISSN", text: Binding(
                    get: { editedRef.issn ?? "" },
                    set: { editedRef.issn = $0.isEmpty ? nil : $0 }
                ))
                TextField("URL", text: Binding(
                    get: { editedRef.url ?? "" },
                    set: { editedRef.url = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("扩展信息") {
                TextField("Language", text: Binding(
                    get: { editedRef.language ?? "" },
                    set: { editedRef.language = $0.isEmpty ? nil : $0 }
                ))
                TextField("Number of Pages", text: Binding(
                    get: { editedRef.numberOfPages ?? "" },
                    set: { editedRef.numberOfPages = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("文献集") {
                Picker("Collection", selection: $editedRef.collectionId) {
                    Text("None").tag(nil as Int64?)
                    ForEach(collections) { col in
                        Label(col.name, systemImage: col.icon).tag(col.id as Int64?)
                    }
                }
            }

            Section("摘要") {
                TextEditor(text: Binding(
                    get: { editedRef.abstract ?? "" },
                    set: { editedRef.abstract = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 100)
            }

            Section("笔记") {
                TextEditor(text: Binding(
                    get: { editedRef.notes ?? "" },
                    set: { editedRef.notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
            }

            if editedRef.referenceType == .webpage {
                Section("文章内容") {
                    if isLoadingWebContent && editedRef.webContent == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在加载正文…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    TextEditor(text: Binding(
                        get: { editedRef.decodedWebContent?.body ?? "" },
                        set: { newValue in
                            let format = editedRef.decodedWebContent?.format ?? .markdown
                            editedRef.webContent = Reference.encodeWebContent(newValue, format: format)
                        }
                    ))
                    .frame(minHeight: 220)
                }
            }

            Section("PDF 附件") {
                if editedRef.pdfPath != nil {
                    HStack {
                        Label("已附加 PDF", systemImage: "doc.fill")
                        Spacer()
                        Button("Remove PDF") {
                            editedRef.pdfPath = nil
                        }
                    }
                } else {
                    Button("Attach PDF...") { attachPDF() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func attachPDF() {
        guard let url = OpenPanelPicker.pickPDFFile() else { return }
        if let path = try? PDFService.importPDF(from: url) {
            editedRef.pdfPath = path
        }
    }

    private var canOpenWebReader: Bool {
        reference.referenceType == .webpage && (hasStoredWebContent || resolvedWebReaderURLString != nil)
    }

    private var resolvedWebReaderURLString: String? {
        let value = reference.resolvedWebReaderURLString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func loadSupplementaryData(for referenceID: Int64?) async {
        guard let referenceID else {
            referenceTags = []
            pdfAnnotationCount = 0
            webAnnotationCount = 0
            hasStoredWebContent = false
            return
        }

        struct Payload: Sendable {
            var tags: [Tag]
            var pdfAnnotationCount: Int
            var webAnnotationCount: Int
            var hasStoredWebContent: Bool
        }

        let payload = await Task.detached(priority: .userInitiated) { [db] in
            Payload(
                tags: (try? db.fetchTags(forReference: referenceID)) ?? [],
                pdfAnnotationCount: (try? db.annotationCount(referenceId: referenceID)) ?? 0,
                webAnnotationCount: (try? db.webAnnotationCount(referenceId: referenceID)) ?? 0,
                hasStoredWebContent: (try? db.hasWebContent(id: referenceID)) ?? false
            )
        }.value

        guard !Task.isCancelled, reference.id == referenceID else { return }
        referenceTags = payload.tags
        pdfAnnotationCount = payload.pdfAnnotationCount
        webAnnotationCount = payload.webAnnotationCount
        hasStoredWebContent = payload.hasStoredWebContent
    }

    private func loadWebContentIfNeeded() async {
        guard hasStoredWebContent, editedRef.webContent == nil, let referenceID = reference.id else {
            return
        }

        isLoadingWebContent = true
        let webContent = await Task.detached(priority: .userInitiated) { [db] in
            try? db.fetchWebContent(id: referenceID)
        }.value

        guard !Task.isCancelled, reference.id == referenceID else { return }
        isLoadingWebContent = false
        if editedRef.id == referenceID, editedRef.webContent == nil {
            editedRef.webContent = webContent ?? editedRef.webContent
        }
    }

    private func prepareReferenceForWebReader() async -> Reference? {
        guard let referenceID = reference.id else { return nil }
        if !hasStoredWebContent {
            return reference
        }

        if editedRef.id == referenceID, let content = editedRef.webContent,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var prepared = reference
            prepared.webContent = content
            return prepared
        }

        let webContent = await Task.detached(priority: .userInitiated) { [db] in
            try? db.fetchWebContent(id: referenceID)
        }.value

        guard !Task.isCancelled, reference.id == referenceID else { return nil }
        var prepared = reference
        prepared.webContent = webContent
        if editedRef.id == referenceID, editedRef.webContent == nil {
            editedRef.webContent = webContent
        }
        return prepared
    }

    private func saveEdits() async {
        if hasStoredWebContent && editedRef.webContent == nil {
            await loadWebContentIfNeeded()
        }
        guard !Task.isCancelled else { return }
        hasStoredWebContent = !(editedRef.webContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        onSave(editedRef)
        isEditing = false
    }

    private func metadataRows(for reference: Reference) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []

        if let source = reference.metadataSource?.displayName {
            rows.append(("来源", source))
        }

        switch reference.referenceType {
        case .book, .bookSection:
            if let publisher = reference.publisher { rows.append(("出版社", publisher)) }
            if let place = reference.publisherPlace { rows.append(("出版地", place)) }
            if let edition = reference.edition { rows.append(("版次", edition)) }
            if let isbn = reference.isbn { rows.append(("ISBN", isbn)) }
            if let language = reference.language { rows.append(("语言", language)) }
            if let pages = reference.numberOfPages { rows.append(("页数", pages)) }
        case .thesis:
            if let institution = reference.institution { rows.append(("机构", institution)) }
            if let genre = reference.genre { rows.append(("类型", genre)) }
            if let year = reference.year { rows.append(("年份", String(year))) }
        case .conferencePaper:
            if let eventTitle = reference.eventTitle { rows.append(("会议", eventTitle)) }
            if let eventPlace = reference.eventPlace { rows.append(("地点", eventPlace)) }
            if let issn = reference.issn { rows.append(("ISSN", issn)) }
        case .journalArticle,
             .magazineArticle,
             .newspaperArticle,
             .preprint,
             .dataset,
             .software,
             .standard,
             .manuscript,
             .interview,
             .presentation,
             .blogPost,
             .forumPost,
             .legalCase,
             .legislation,
             .report,
             .webpage,
             .patent,
             .other:
            if let issn = reference.issn { rows.append(("ISSN", issn)) }
            if let publisher = reference.publisher { rows.append(("出版社", publisher)) }
        }

        return rows.filter { !$0.1.isEmpty }
    }
}
