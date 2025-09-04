import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let book: Ebook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showUI: Bool = false
    @State private var pageCount: Int = 1
    @State private var currentPageIndex: Int = 0
    

    var body: some View {
        ZStack {
            PDFKitView(fileURL: FileStore.ebooksFolderURL.appendingPathComponent(book.fileName), currentIndex: $currentPageIndex, pageCount: $pageCount)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { showUI.toggle() } }

            // Drawing overlay (below UI and arrows)
#if canImport(PencilKit)
            if isDrawing {
                PencilCanvasView(drawing: $drawing, isDrawing: true)
                    .ignoresSafeArea()
            }
#endif

            // Navigation arrows
            HStack {
                Button { prev() } label: { Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44).overlay(Image(systemName: "chevron.left")) }
                    .padding(.leading, 16)
                    .disabled(currentPageIndex == 0)
                Spacer()
                Button { next() } label: { Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44).overlay(Image(systemName: "chevron.right")) }
                    .padding(.trailing, 16)
                    .disabled(currentPageIndex + 1 >= pageCount)
            }

            if showUI {
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "house") }
                        Text(book.title).font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    Spacer()
                    if pageCount > 1 {
                        HStack {
                            Text("\(currentPageIndex + 1) / \(pageCount)").font(.footnote).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { Double(currentPageIndex) }, set: { currentPageIndex = Int($0.rounded()) }), in: 0...Double(pageCount - 1), step: 1)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                        .background(.ultraThinMaterial)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: currentPageIndex) { _, _ in saveProgress() }
        .task {
            // restore progress
            currentPageIndex = max(0, book.lastReadPage)
        }
    }

    private func saveProgress() {
        book.lastReadIndex = 0
        book.lastReadPage = currentPageIndex
        book.lastReadAt = Date()
        try? modelContext.save()
    }

    private func next() { if currentPageIndex + 1 < pageCount { currentPageIndex += 1 } }
    private func prev() { if currentPageIndex > 0 { currentPageIndex -= 1 } }
}

// Pencil functionality removed for now

private struct PDFKitView: UIViewRepresentable {
    let fileURL: URL
    @Binding var currentIndex: Int
    @Binding var pageCount: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .horizontal
        view.displayMode = .singlePage
        view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 0])
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: fileURL)
        pageCount = view.document?.pageCount ?? 1
        if let page = view.document?.page(at: currentIndex) { view.go(to: page) }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged), name: Notification.Name.PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let doc = uiView.document, currentIndex < doc.pageCount, let page = doc.page(at: currentIndex), uiView.currentPage != page {
            uiView.go(to: page)
        }
        pageCount = uiView.document?.pageCount ?? 1
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        let parent: PDFKitView
        init(parent: PDFKitView) { self.parent = parent }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let doc = view.document, let page = view.currentPage else { return }
            let idx = doc.index(for: page)
            if idx != parent.currentIndex { parent.currentIndex = idx }
            parent.pageCount = doc.pageCount
        }
    }
}
