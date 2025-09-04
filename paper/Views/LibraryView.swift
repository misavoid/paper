import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(PDFKit)
import PDFKit
#endif
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
    private var pdfType: UTType { .pdf }

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
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [epubType, pdfType], allowsMultipleSelection: true) { result in
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
            .fullScreenCover(item: $presentedBook) { book in
                if book.isPDF {
                    PDFReaderView(book: book)
                } else {
                    ReaderView(book: book)
                }
            }
        }
    }

    private func importBooks(from urls: [URL]) {
        for url in urls {
            do {
                let fileName = try FileStore.saveImportedFile(originalURL: url)
                let localURL = FileStore.ebooksFolderURL.appendingPathComponent(fileName)
                let ext = localURL.pathExtension.lowercased()
                if ext == "pdf" {
                    var title = ""
                    var author = ""
                    var coverName: String? = nil
                    #if canImport(PDFKit)
                    if let doc = PDFDocument(url: localURL) {
                        if let attrs = doc.documentAttributes {
                            if let t = attrs[PDFDocumentAttribute.titleAttribute] as? String { title = t }
                            if let a = attrs[PDFDocumentAttribute.authorAttribute] as? String { author = a }
                        }
                        if let page = doc.page(at: 0) {
                            let pageRect = page.bounds(for: .mediaBox)
                            let targetW: CGFloat = 600
                            let scale = targetW / max(pageRect.width, 1)
                            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                            UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                            if let ctx = UIGraphicsGetCurrentContext() {
                                UIColor.white.setFill()
                                ctx.fill(CGRect(origin: .zero, size: size))
                                ctx.saveGState()
                                ctx.translateBy(x: 0, y: size.height)
                                ctx.scaleBy(x: scale, y: -scale)
                                page.draw(with: .mediaBox, to: ctx)
                                ctx.restoreGState()
                            }
                            let img = UIGraphicsGetImageFromCurrentImageContext()
                            UIGraphicsEndImageContext()
                            if let data = img?.jpegData(compressionQuality: 0.8) { coverName = FileStore.saveCover(data, preferredExt: "jpg") }
                        }
                    }
                    #endif
                    if title.isEmpty {
                        let guessed = Ebook.guessMetadata(fromFileName: fileName)
                        title = guessed.title; if author.isEmpty { author = guessed.author }
                    }
                    let newBook = Ebook(title: title, author: author, genre: "Unsorted", fileName: fileName, fileKind: "pdf", coverFileName: coverName)
                    modelContext.insert(newBook)
                } else {
                    var title = ""
                    var author = ""
                    var subjects: [String] = []
                    var coverName: String? = nil
                    if let meta = try? EPUBParser().parseMetadata(fromEpubAt: localURL) {
                        title = meta.title ?? ""
                        author = meta.author ?? ""
                        subjects = meta.subjects
                        if let cover = meta.coverData {
                            let data = Thumbnailer.downsample(imageData: cover, maxDimension: 600) ?? cover
                            coverName = FileStore.saveCover(data, preferredExt: meta.coverExt)
                        }
                    }
                    if title.isEmpty || author.isEmpty {
                        let guessed = Ebook.guessMetadata(fromFileName: fileName)
                        if title.isEmpty { title = guessed.title }
                        if author.isEmpty { author = guessed.author }
                    }
                    let genre = subjects.first ?? "Unsorted"
                    let newBook = Ebook(title: title, author: author, genre: genre, fileName: fileName, fileKind: "epub", coverFileName: coverName)
                    modelContext.insert(newBook)
                }
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
        #if canImport(UIKit)
        if let url = book.coverURL, let img = downsampledImage(url: url, maxDimension: 600) {
            return Image(uiImage: img)
        }
        #endif
        return Image(systemName: "book")
    }

    #if canImport(UIKit)
    private func downsampledImage(url: URL, maxDimension: CGFloat) -> UIImage? {
        let srcOpts: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension * UIScreen.main.scale,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    #endif
}
