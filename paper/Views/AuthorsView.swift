import SwiftUI
import SwiftData

struct AuthorsView: View {
    @Query private var ebooks: [Ebook]

    struct AuthorGroup: Identifiable {
        var name: String
        var books: [Ebook]
        var id: String { name }
    }

    private var groups: [AuthorGroup] {
        var dict: [String: [Ebook]] = [:]
        for b in ebooks {
            let key = b.author.isEmpty ? "Unknown" : b.author
            dict[key, default: []].append(b)
        }
        return dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { AuthorGroup(name: $0, books: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List(groups) { group in
                NavigationLink(destination: BooksListView(title: group.name, books: group.books)) {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.books.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Authors")
        }
    }
}

struct BooksListView: View {
    let title: String
    let books: [Ebook]
    @State private var presentedBook: Ebook?

    init(title: String, books: [Ebook]) {
        self.title = title
        self.books = books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List(books) { book in
            Button {
                presentedBook = book
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.headline)
                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $presentedBook) { ReaderView(book: $0) }
        .navigationTitle(title)
    }
}
