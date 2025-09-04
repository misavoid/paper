import SwiftUI
import SwiftData

struct CollectionsView: View {
    @Query private var ebooks: [Ebook]

    struct GenreGroup: Identifiable {
        var name: String
        var books: [Ebook]
        var id: String { name }
    }

    private var groups: [GenreGroup] {
        var dict: [String: [Ebook]] = [:]
        for b in ebooks {
            let key = b.genre.isEmpty ? "Unsorted" : b.genre
            dict[key, default: []].append(b)
        }
        return dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { GenreGroup(name: $0, books: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List(groups) { group in
                NavigationLink(destination: GenreBooksView(genre: group.name, books: group.books)) {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.books.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Collections")
        }
    }
}

struct GenreBooksView: View {
    let genre: String
    let books: [Ebook]
    @State private var presentedBook: Ebook?

    var body: some View {
        let sorted = books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        List(sorted) { book in
            Button { presentedBook = book } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.headline)
                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $presentedBook) { ReaderView(book: $0) }
        .navigationTitle(genre)
    }
}
