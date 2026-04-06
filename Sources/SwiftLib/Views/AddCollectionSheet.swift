import SwiftUI
import SwiftLibCore

struct AddCollectionSheet: View {
    let onSave: (Collection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "folder"

    private let icons = [
        "folder", "folder.fill", "book.closed", "star",
        "heart", "flag", "bookmark", "tag",
        "archivebox", "tray.full", "graduationcap", "briefcase",
        "flask", "atom", "brain", "leaf"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("New Collection")
                .font(.headline)

            TextField("Collection Name", text: $name)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 8), spacing: 8) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    let col = Collection(name: name, icon: selectedIcon)
                    onSave(col)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
