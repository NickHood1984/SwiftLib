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
                Spacer()
                Text("手动新建")
                    .font(.headline)
                Spacer()
                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
            }
            .padding()

            Divider()

            Form {
                Section("Type") {
                    Picker("Reference Type", selection: $referenceType) {
                        ForEach(ReferenceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("Basic Info") {
                    TextField("Title *", text: $title)
                    TextField("Authors (comma or semicolon separated)", text: $authorsText)
                    TextField("Year", value: $year, format: .number)
                }

                Section("Publication") {
                    TextField("Journal / Book Title", text: $journal)
                    HStack {
                        TextField("Volume", text: $volume)
                        TextField("Issue", text: $issue)
                        TextField("Pages", text: $pages)
                    }
                    TextField("Publisher", text: $publisher)
                    HStack {
                        TextField("Publisher Place", text: $publisherPlace)
                        TextField("Edition", text: $edition)
                    }
                    if referenceType == .conferencePaper {
                        TextField("Conference / Event", text: $eventTitle)
                        TextField("Event Place", text: $eventPlace)
                    }
                    if referenceType == .thesis {
                        TextField("Institution", text: $institution)
                        TextField("Thesis Type / Genre", text: $genre)
                    }
                }

                Section("Identifiers") {
                    TextField("DOI", text: $doi)
                    TextField("ISBN", text: $isbn)
                    TextField("ISSN", text: $issn)
                    TextField("URL", text: $url, prompt: Text("Optional"))
                }

                Section("Extended") {
                    TextField("Language", text: $language)
                    TextField("Number of Pages", text: $numberOfPages)
                }

                Section("Collection") {
                    Picker("Collection", selection: $collectionId) {
                        Text("None").tag(nil as Int64?)
                        ForEach(collections) { col in
                            Label(col.name, systemImage: col.icon).tag(col.id as Int64?)
                        }
                    }
                }

                Section("Abstract") {
                    TextEditor(text: $abstract)
                        .frame(minHeight: 80)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                Section("PDF") {
                    if pdfPath != nil {
                        HStack {
                            Label("PDF Attached", systemImage: "doc.fill")
                            Spacer()
                            Button("Remove") { pdfPath = nil }
                        }
                    } else {
                        Button("Attach PDF...") { attachPDF() }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 550, height: 650)
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
