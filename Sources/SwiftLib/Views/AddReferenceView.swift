import AppKit
import SwiftUI
import SwiftLibCore

struct AddReferenceView: View {
    let collections: [Collection]
    let allTags: [Tag]
    let onSave: (Reference) -> Void
    let onCreateTag: (Tag) -> Void
    let initialReferenceType: ReferenceType

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var authorsText = ""
    @State private var year: Int?
    @State private var journal = ""
    @State private var volume = ""
    @State private var issue = ""
    @State private var pages = ""
    @State private var doi = ""
    @State private var isbn = ""
    @State private var issn = ""
    @State private var url = ""
    @State private var publisher = ""
    @State private var publisherPlace = ""
    @State private var edition = ""
    @State private var language = ""
    @State private var numberOfPages = ""
    @State private var institution = ""
    @State private var genre = ""
    @State private var eventTitle = ""
    @State private var eventPlace = ""
    @State private var abstract = ""
    @State private var notes = ""
    @State private var referenceType: ReferenceType
    @State private var collectionId: Int64?
    @State private var pdfPath: String?

    init(
        collections: [Collection],
        allTags: [Tag],
        onSave: @escaping (Reference) -> Void,
        onCreateTag: @escaping (Tag) -> Void,
        initialReferenceType: ReferenceType = .journalArticle
    ) {
        self.collections = collections
        self.allTags = allTags
        self.onSave = onSave
        self.onCreateTag = onCreateTag
        self.initialReferenceType = initialReferenceType
        _referenceType = State(initialValue: initialReferenceType)
    }

    private var saveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SLSecondaryButtonStyle())
                Spacer()
                Text("手动新建")
                    .font(.headline)
                Spacer()
                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
                .buttonStyle(SLPrimaryButtonStyle())
            }
            .padding()

            Divider()

            Form {
                Section("类型") {
                    Picker("文献类型", selection: $referenceType) {
                        ForEach(ReferenceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("基本信息") {
                    TextField("标题 *", text: $title)
                    TextField("作者（逗号或分号分隔）", text: $authorsText)
                    TextField("年份", value: $year, format: .number)
                }

                Section("出版信息") {
                    TextField("期刊 / 书名", text: $journal)
                    HStack {
                        TextField("卷", text: $volume)
                        TextField("期", text: $issue)
                        TextField("页码", text: $pages)
                    }
                    TextField("出版社", text: $publisher)
                    HStack {
                        TextField("出版地", text: $publisherPlace)
                        TextField("版次", text: $edition)
                    }
                    if referenceType == .conferencePaper {
                        TextField("会议名称", text: $eventTitle)
                        TextField("会议地点", text: $eventPlace)
                    }
                    if referenceType == .thesis {
                        TextField("所属机构", text: $institution)
                        TextField("学位类型", text: $genre)
                    }
                }

                Section("标识符") {
                    TextField("DOI", text: $doi)
                    TextField("ISBN", text: $isbn)
                    TextField("ISSN", text: $issn)
                    TextField("URL", text: $url, prompt: Text("选填"))
                }

                Section("扩展信息") {
                    TextField("语言", text: $language)
                    TextField("总页数", text: $numberOfPages)
                }

                Section("分组") {
                    Picker("所属分组", selection: $collectionId) {
                        Text("无").tag(nil as Int64?)
                        ForEach(collections) { col in
                            Label(col.name, systemImage: col.icon).tag(col.id as Int64?)
                        }
                    }
                }

                Section("摘要") {
                    TextEditor(text: $abstract)
                        .frame(minHeight: 80)
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                Section("PDF") {
                    if pdfPath != nil {
                        HStack {
                            Label("已附加 PDF", systemImage: "doc.fill")
                            Spacer()
                            Button("移除") { pdfPath = nil }
                        }
                    } else {
                        Button("附加 PDF…") { attachPDF() }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 550, height: 650)
        .swiftLibElegantScrollersInSubtree()
    }

    private func save() {
        let urlTrimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.trimmingCharacters(in: .whitespaces)

        let ref = Reference(
            title: finalTitle,
            authors: AuthorName.parseList(authorsText),
            year: year,
            journal: journal.isEmpty ? nil : journal,
            volume: volume.isEmpty ? nil : volume,
            issue: issue.isEmpty ? nil : issue,
            pages: pages.isEmpty ? nil : pages,
            doi: doi.isEmpty ? nil : doi,
            url: urlTrimmed.isEmpty ? nil : urlTrimmed,
            abstract: abstract.isEmpty ? nil : abstract,
            pdfPath: pdfPath,
            notes: notes.isEmpty ? nil : notes,
            siteName: nil,
            referenceType: referenceType,
            collectionId: collectionId,
            publisher: publisher.isEmpty ? nil : publisher,
            publisherPlace: publisherPlace.isEmpty ? nil : publisherPlace,
            edition: edition.isEmpty ? nil : edition,
            isbn: isbn.isEmpty ? nil : isbn,
            issn: issn.isEmpty ? nil : issn,
            eventTitle: eventTitle.isEmpty ? nil : eventTitle,
            eventPlace: eventPlace.isEmpty ? nil : eventPlace,
            genre: genre.isEmpty ? nil : genre,
            institution: institution.isEmpty ? nil : institution,
            numberOfPages: numberOfPages.isEmpty ? nil : numberOfPages,
            language: language.isEmpty ? nil : language
        )
        onSave(ref)
        dismiss()
    }

    private func attachPDF() {
        guard let fileURL = OpenPanelPicker.pickPDFFile() else { return }
        pdfPath = try? PDFService.importPDF(from: fileURL)
    }
}
