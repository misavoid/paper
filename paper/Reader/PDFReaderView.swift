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
    @State private var pdfViewRef: PDFView?
#endif

    var body: some View {
        ZStack {
            PDFKitView(fileURL: FileStore.ebooksFolderURL.appendingPathComponent(book.fileName), currentIndex: $currentPageIndex, pageCount: $pageCount, onCreated: { view in
                #if canImport(PencilKit)
                self.pdfViewRef = view
                #endif
            })
                .ignoresSafeArea()
                .onTapGesture { withAnimation { if !isDrawing { showUI.toggle() } } }

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
                        #if canImport(PencilKit)
                        Button {
                            if isDrawing {
                                // turning off: save and embed
                                saveDrawing()
                                embedCurrentDrawingIntoPDF()
                                isDrawing = false
                            } else {
                                loadDrawing()
                                isDrawing = true
                            }
                        } label: { Image(systemName: isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip") }
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
            // Keep drawings in sync when page changes
            .onChange(of: currentPageIndex) { _, _ in if isDrawing { saveDrawing() }; loadDrawing() }
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

    // Flatten current drawing into the PDF file by rasterizing current page
    private func embedCurrentDrawingIntoPDF() {
        guard let view = pdfViewRef, let doc = view.document, let page = doc.page(at: currentPageIndex) else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        // Render current page + drawing into a new PDF page
        let mutableData = NSMutableData()
        UIGraphicsBeginPDFContextToData(mutableData, pageBounds, nil)
        UIGraphicsBeginPDFPageWithInfo(pageBounds, nil)
        guard let ctx = UIGraphicsGetCurrentContext() else { UIGraphicsEndPDFContext(); return }
        // Draw original PDF page
        ctx.saveGState()
        ctx.translateBy(x: 0, y: pageBounds.height)
        ctx.scaleBy(x: 1, y: -1)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        // Draw the PencilKit image scaled to page
        let viewRect = view.bounds
        let img = drawing.image(from: viewRect, scale: 2.0)
        // Fit view rect to page bounds
        img.draw(in: pageBounds, blendMode: .normal, alpha: 1.0)
        UIGraphicsEndPDFContext()
        // Replace page in document
        if let newDoc = PDFDocument(data: mutableData as Data), let newPage = newDoc.page(at: 0) {
            doc.removePage(at: currentPageIndex)
            doc.insert(newPage, at: currentPageIndex)
            // Write back to disk
            let url = FileStore.ebooksFolderURL.appendingPathComponent(book.fileName)
            doc.write(to: url)
            // Clear drawing for this page as it's embedded now
            drawing = PKDrawing()
            AnnotationStore.save(drawing: drawing, bookID: book.id, kind: "pdf", chapter: 0, page: currentPageIndex)
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
