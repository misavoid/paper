import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            CollectionsView()
                .tabItem { Label("Collections", systemImage: "square.grid.2x2") }

            AuthorsView()
                .tabItem { Label("Authors", systemImage: "person.2") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Ebook.self, inMemory: true)
}

