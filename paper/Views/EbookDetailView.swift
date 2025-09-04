import SwiftUI
import SwiftData

struct EbookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var titleText: String
    @State private var authorText: String
    @State private var genreText: String

    @Bindable var book: Ebook

    init(book: Ebook) {
        self.book = book
        _titleText = State(initialValue: book.title)
        _authorText = State(initialValue: book.author)
        _genreText = State(initialValue: book.genre)
    }

    var body: some View {
        Form {
            Section(header: Text("Details")) {
                LabeledContent("Title") { Text(book.title) }
                LabeledContent("Author") { Text(book.author) }
                LabeledContent("Genre") { Text(book.genre) }
                LabeledContent("Added") { Text(book.dateAdded.formatted()) }
            }
            Section(header: Text("File")) {
                LabeledContent("File name") { Text(book.fileName).textSelection(.enabled) }
            }
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { saveEdits() }
                    isEditing.toggle()
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                Form {
                    TextField("Title", text: $titleText)
                    TextField("Author", text: $authorText)
                    TextField("Genre", text: $genreText)
                }
                .navigationTitle("Edit Book")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isEditing = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { saveEdits(); isEditing = false } }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func saveEdits() {
        book.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = authorText.trimmingCharacters(in: .whitespacesAndNewlines)
        book.genre = genreText.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
    }
}
