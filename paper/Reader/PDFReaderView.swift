import SwiftUI
import PDFKit
#if canImport(PencilKit)
import PencilKit
#endif

struct PDFReaderView: View {
    let book: Ebook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showUI: Bool = false
    @State private var pageCount: Int = 1
    @State private var currentPageIndex: Int = 0
    #if canImport(PencilKit)
    @State private var isDrawing: Bool = false
    @State private var drawing: PKDrawing = PKDrawing()
    #endif

    var body: some View {
        ZStack {
            PDFKitView(fileURL: FileStore.ebooksFolderURL.appendingPathComponent(book.fileName), currentIndex: $currentPageIndex, pageCount: $pageCount)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { showUI.toggle() } }

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
                        #if canImport(PencilKit)
                        Button { isDrawing.toggle(); if !isDrawing { saveDrawing() } } label: { Image(systemName: isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip") }
                        #endif
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
            #if canImport(PencilKit)
            if isDrawing {
                PencilCanvasView(drawing: $drawing, isDrawing: true)
                    .ignoresSafeArea()
                    .onDisappear { saveDrawing() }
                    .onChange(of: currentPageIndex) { _, _ in saveDrawing(); loadDrawing() }
            }
            #endif
        }
        .onChange(of: currentPageIndex) { _, _ in saveProgress() }
        .task {
            // restore progress
            currentPageIndex = max(0, book.lastReadPage)
            #if canImport(PencilKit)
            loadDrawing()
            #endif
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

#if canImport(PencilKit)
// MARK: - Drawing persistence (PDF)
extension PDFReaderView {
    private func saveDrawing() {
        AnnotationStore.save(drawing: drawing, bookID: book.id, kind: "pdf", chapter: 0, page: currentPageIndex)
    }
    private func loadDrawing() {
        if let d = AnnotationStore.load(bookID: book.id, kind: "pdf", chapter: 0, page: currentPageIndex) {
            drawing = d
        } else {
            drawing = PKDrawing()
        }
    }
}
#endif

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
