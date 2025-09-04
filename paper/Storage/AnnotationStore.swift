import Foundation
import PencilKit

enum AnnotationStore {
    static var annotationsFolderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Annotations", isDirectory: true)
    }

    static func pathFor(bookID: UUID, kind: String, chapter: Int, page: Int) -> URL {
        let base = annotationsFolderURL
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
            .appendingPathComponent(kind, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(chapter)-\(page).drawing")
    }

    static func save(drawing: PKDrawing, bookID: UUID, kind: String, chapter: Int, page: Int) {
        let url = pathFor(bookID: bookID, kind: kind, chapter: chapter, page: page)
        let data = drawing.dataRepresentation()
        try? data.write(to: url)
    }

    static func load(bookID: UUID, kind: String, chapter: Int, page: Int) -> PKDrawing? {
        let url = pathFor(bookID: bookID, kind: kind, chapter: chapter, page: page)
        if let data = try? Data(contentsOf: url) {
            return try? PKDrawing(data: data)
        }
        return nil
    }
}

