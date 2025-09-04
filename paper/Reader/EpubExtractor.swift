import Foundation

enum EpubExtractor {
    static func extractionFolder(for book: Ebook) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("ExtractedEPUBs", isDirectory: true)
            .appendingPathComponent(book.id.uuidString, isDirectory: true)
    }

    static func ensureExtracted(book: Ebook) throws -> URL {
        let folder = extractionFolder(for: book)
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".done").path) {
            return folder
        }
        try extractAll(book: book, to: folder)
        return folder
    }

    private static func extractAll(book: Ebook, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let epubURL = FileStore.ebooksFolderURL.appendingPathComponent(book.fileName)
        let zip = try ZipSimple(url: epubURL)
        for (name, _) in zip.entries {
            if name.hasSuffix("/") { // directory entry
                let dirURL = folder.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                continue
            }
            let data = try zip.data(for: name)
            let dest = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
        }
        let done = folder.appendingPathComponent(".done")
        try Data("ok".utf8).write(to: done)
    }

    static func deleteExtracted(book: Ebook) {
        let folder = extractionFolder(for: book)
        try? FileManager.default.removeItem(at: folder)
    }
}
