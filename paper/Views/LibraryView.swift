import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ebook.dateAdded, order: .reverse) private var ebooks: [Ebook]

    @State private var showingImporter = false
    @State private var importError: String?
    @State private var searchText = ""
    @State private var sort: Sort = .date
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var presentedBook: Ebook?

    private var epubType: UTType { UTType(filenameExtension: "epub") ?? .data }

    var body: some View {
        NavigationStack {
            Group {
                if filteredSorted.isEmpty {
                    ContentUnavailableView("No eBooks yet", systemImage: "books.vertical", description: Text("Tap + to import .epub files"))
                } else {
                    ScrollView {
                        if let cont = continueCandidate {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    presentedBook = cont
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Continue \(cont.title)")
                                        Spacer()
                                        Text("Chapter \((cont.lastReadIndex)+1)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                        let cols = [GridItem(.adaptive(minimum: 160), spacing: 16)]
                        LazyVGrid(columns: cols, spacing: 16) {
                            ForEach(filteredSorted) { book in
                                if editMode == .active {
                                    BookCell(book: book, isSelected: selection.contains(book.id))
                                        .onTapGesture { toggleSelection(for: book) }
                                        .contextMenu { Button("Delete", role: .destructive) { delete(book) } }
                                } else {
                                    Button { presentedBook = book } label: { BookCell(book: book, isSelected: false) }
                                        .buttonStyle(.plain)
                                        .contextMenu { Button("Delete", role: .destructive) { delete(book) } }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .navigationBarTrailing) { Button { showingImporter = true } label: { Label("Add", systemImage: "plus") } }
                ToolbarItem(placement: .bottomBar) {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { s in
                            Text(s.title).tag(s)
                        }
                    }.pickerStyle(.segmented)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection.isEmpty)
                }
            }
            .environment(\.editMode, $editMode)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [epubType], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    importBooks(from: urls)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import Failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "Unknown error")
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
            .fullScreenCover(item: $presentedBook) { ReaderView(book: $0) }
        }
    }

    private func importBooks(from urls: [URL]) {
        for url in urls {
            do {
                let fileName = try FileStore.saveImportedFile(originalURL: url)
                let localURL = FileStore.ebooksFolderURL.appendingPathComponent(fileName)
                var title = ""
                var author = ""
                var subjects: [String] = []
                var coverName: String? = nil
                if let meta = try? EPUBParser().parseMetadata(fromEpubAt: localURL) {
                    title = meta.title ?? ""
                    author = meta.author ?? ""
                    subjects = meta.subjects
                    if let cover = meta.coverData {
                        coverName = FileStore.saveCover(cover, preferredExt: meta.coverExt)
                    }
                }
                if title.isEmpty || author.isEmpty {
                    let guessed = Ebook.guessMetadata(fromFileName: fileName)
                    if title.isEmpty { title = guessed.title }
                    if author.isEmpty { author = guessed.author }
                }
                let genre = subjects.first ?? "Unsorted"
                let newBook = Ebook(title: title, author: author, genre: genre, fileName: fileName, coverFileName: coverName)
                modelContext.insert(newBook)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func delete(_ book: Ebook) {
        FileStore.deleteFile(named: book.fileName)
        EpubExtractor.deleteExtracted(book: book)
        modelContext.delete(book)
    }

    private func deleteSelected() {
        let toDelete = ebooks.filter { selection.contains($0.id) }
        toDelete.forEach { delete($0) }
        selection.removeAll()
    }

    private func toggleSelection(for book: Ebook) { if selection.contains(book.id) { selection.remove(book.id) } else { selection.insert(book.id) } }

    private var filteredSorted: [Ebook] {
        var arr = ebooks
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            arr = arr.filter { $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q) || $0.genre.lowercased().contains(q) }
        }
        switch sort {
        case .date: arr.sort { $0.dateAdded > $1.dateAdded }
        case .title: arr.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author: arr.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        }
        return arr
    }

    private var continueCandidate: Ebook? {
        return ebooks.filter { $0.lastReadAt != nil }.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.first
    }

    enum Sort: CaseIterable { case date, title, author
        var title: String { switch self { case .date: return "Recent"; case .title: return "Title"; case .author: return "Author" } }
    }
}

private struct BookCell: View {
    @Environment(\.editMode) private var editMode
    let book: Ebook
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                cover
                    .resizable()
                    .aspectRatio(3/4, contentMode: .fill)
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3))
                if editMode?.wrappedValue == .active {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .padding(8)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            Text(book.title).font(.headline).lineLimit(2)
            Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var cover: Image {
        if let url = book.coverURL, let data = try? Data(contentsOf: url) {
            #if canImport(UIKit)
            if let ui = UIImage(data: data) { return Image(uiImage: ui) }
            #endif
        }
        return Image(systemName: "book")
    }
}
