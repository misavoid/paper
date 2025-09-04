import Foundation
import SwiftData

@Model
final class Ebook {
    var id: UUID
    var title: String
    var author: String
    var genre: String
    var fileName: String
    var dateAdded: Date
    var coverFileName: String?
    var lastReadIndex: Int
    var lastReadAt: Date?
    var lastReadPage: Int

    init(id: UUID = UUID(), title: String, author: String, genre: String, fileName: String, coverFileName: String? = nil, dateAdded: Date = Date(), lastReadIndex: Int = 0, lastReadAt: Date? = nil, lastReadPage: Int = 0) {
        self.id = id
        self.title = title
        self.author = author
        self.genre = genre
        self.fileName = fileName
        self.coverFileName = coverFileName
        self.dateAdded = dateAdded
        self.lastReadIndex = lastReadIndex
        self.lastReadAt = lastReadAt
        self.lastReadPage = lastReadPage
    }
}

extension Ebook {
    static func guessMetadata(fromFileName name: String) -> (title: String, author: String) {
        let base = (name as NSString).deletingPathExtension
        // Try pattern: "Author - Title"
        let parts = base.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2 {
            return (title: parts[1], author: parts[0])
        }
        // Fallback: title from filename, unknown author
        return (title: base, author: "Unknown")
    }
}

extension Ebook {
    var coverURL: URL? {
        guard let name = coverFileName else { return nil }
        return FileStore.coversFolderURL.appendingPathComponent(name)
    }
}
