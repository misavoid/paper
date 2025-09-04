import Foundation

enum FileStore {
    static var ebooksFolderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Ebooks", isDirectory: true)
    }

    static var coversFolderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Covers", isDirectory: true)
    }

    static func ensureFolders() {
        for url in [ebooksFolderURL, coversFolderURL] {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    static func saveImportedFile(originalURL: URL) throws -> String {
        ensureFolders()
        let fileName = uniqueFileName(for: originalURL.lastPathComponent)
        let destURL = ebooksFolderURL.appendingPathComponent(fileName)
        // If it's a security-scoped resource, access it
        var didStartAccessing = false
        if originalURL.startAccessingSecurityScopedResource() {
            didStartAccessing = true
        }
        defer {
            if didStartAccessing { originalURL.stopAccessingSecurityScopedResource() }
        }
        // Copy into app container
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: originalURL, to: destURL)
        return fileName
    }

    static func deleteFile(named fileName: String) {
        let url = ebooksFolderURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func saveCover(_ data: Data, preferredExt: String = "jpg") -> String? {
        ensureFolders()
        let name = UUID().uuidString + "." + (preferredExt.isEmpty ? "jpg" : preferredExt)
        let url = coversFolderURL.appendingPathComponent(name)
        do { try data.write(to: url); return name } catch { return nil }
    }

    static func uniqueFileName(for proposed: String) -> String {
        var name = (proposed as NSString).deletingPathExtension
        var ext = (proposed as NSString).pathExtension
        if ext.isEmpty { ext = "epub" }
        var candidate = "\(name).\(ext)"
        var index = 1
        while FileManager.default.fileExists(atPath: ebooksFolderURL.appendingPathComponent(candidate).path) {
            index += 1
            candidate = "\(name) (\(index)).\(ext)"
        }
        return candidate
    }
}
