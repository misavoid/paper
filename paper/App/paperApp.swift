//
//  paperApp.swift
//  paper
//
//  Created by Misa Nthrop on 04.09.25.
//

import SwiftUI
import SwiftData

@main
struct paperApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Ebook.self])
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        let storeURL = support.appendingPathComponent("EbookStore.store")
        // Prefer a named URL to avoid collisions with any previous template store
        if let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)]) {
            return container
        }
        // If opening fails, try deleting the existing file once and retry
        try? fm.removeItem(at: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)]) {
            return container
        }
        // As a last resort, fall back to in-memory to avoid crashing
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
