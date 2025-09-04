import SwiftUI
import WebKit

struct ReaderView: View {
    let book: Ebook
    @Environment(\.modelContext) private var modelContext
    @State private var rootFolder: URL?
    @State private var chapters: [URL] = []
    @State private var selection: Int = 0
    @State private var error: String?
    @State private var showUI: Bool = false
    @State private var showTOC: Bool = false
    @State private var showInfo: Bool = false
    @State private var showSettings: Bool = false
    @AppStorage("readerTheme") private var readerTheme: String = ReaderTheme.light.rawValue
    @AppStorage("readerFontScale") private var readerFontScale: Double = 1.0
    @AppStorage("readerFontInitialized") private var readerFontInitialized: Bool = false
    @State private var currentPage: Int = 0
    @State private var currentPageCount: Int = 1
    @State private var navMap: [String:String] = [:]
    @State private var basePathRelative: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if let root = rootFolder, !chapters.isEmpty {
                TabView(selection: $selection) {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { idx, url in
                        HTMLFileView(
                            fileURL: url,
                            readAccessURL: root,
                            theme: ReaderTheme(rawValue: readerTheme) ?? .light,
                            fontScale: readerFontScale,
                            pageIndex: idx == selection ? $currentPage : .constant(0),
                            onPageCount: { count in if idx == selection { currentPageCount = max(1, count) } }
                        )
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Full-screen tap layer to toggle UI (below controls)
                Rectangle().fill(Color.clear).contentShape(Rectangle()).ignoresSafeArea().onTapGesture { withAnimation { showUI.toggle() } }

                // Always-visible page arrows
                HStack {
                    Button { prev() } label: {
                        Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44).overlay(Image(systemName: "chevron.left"))
                    }.padding(.leading, 16).disabled(selection == 0 && currentPage == 0)
                    Spacer()
                    Button { next() } label: {
                        Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44).overlay(Image(systemName: "chevron.right"))
                    }.padding(.trailing, 16).disabled(selection + 1 >= chapters.count && currentPage + 1 >= currentPageCount)
                }

                // Top overlay controls (hidden until tapped)
                if showUI {
                    VStack {
                        HStack {
                            Button { dismiss() } label: { Image(systemName: "house") }
                            Text(book.title).font(.headline)
                            Spacer()
                            Button { showTOC = true } label: { Image(systemName: "list.bullet") }
                            Button { showSettings = true } label: { Image(systemName: "textformat.size") }
                            Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        Spacer()
                        // Bottom overlay: page scrubber (only when multiple pages)
                        if currentPageCount > 1 {
                            HStack {
                                Text("\(currentPage + 1) / \(currentPageCount)")
                                    .font(.footnote)
                          
                                Slider(
                                    value: Binding(
                                        get: { Double(currentPage) },
                                        set: { currentPage = Int($0.rounded()) }
                                    ),
                                    in: 0...Double(currentPageCount - 1),
                                    step: 1
                                )
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            .background(.ultraThinMaterial)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView("Loading…")
            }
        }
        .onChange(of: selection) { _, _ in
            // reset per-chapter page when chapter changes
            currentPage = 0
            currentPageCount = 1
            saveProgress(index: selection)
        }
        .onChange(of: currentPage) { _, _ in
            // Save progress including current page
            book.lastReadIndex = selection
            book.lastReadPage = currentPage
            book.lastReadAt = Date()
            try? modelContext.save()
        }
        .onChange(of: currentPageCount) { _, newCount in
            // Clamp currentPage to valid range when page count changes
            let maxIndex = max(0, newCount - 1)
            if currentPage > maxIndex { currentPage = maxIndex }
        }
        .task { await prepare() }
        .sheet(isPresented: $showInfo) { NavigationStack { EbookDetailView(book: book) } }
        .sheet(isPresented: $showTOC) { tocSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    private func prepare() async {
        do {
            let root = try EpubExtractor.ensureExtracted(book: book)
            rootFolder = root
            let epubURL = FileStore.ebooksFolderURL.appendingPathComponent(book.fileName)
            let pack = try EPUBParser().parsePackage(fromEpubAt: epubURL)
            // build file URLs for spine
            let base = root.appendingPathComponent(pack.basePath)
            let urls = pack.spineHrefs.map { href -> URL in
                base.appendingPathComponent(href)
            }
            chapters = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            navMap = pack.navMap
            basePathRelative = base.path
            // Restore progress if available
            if let idx = book.lastReadIndex as Int?, idx < chapters.count { selection = idx; currentPage = max(0, book.lastReadPage) }
            // Initialize default font scale once per device if not set by user
            if !readerFontInitialized {
                #if canImport(UIKit)
                let w = UIScreen.main.bounds.width
                let h = UIScreen.main.bounds.height
                let longest = max(w, h)
                // Simple heuristic: larger screens get slightly larger default text
                let scale: Double = longest >= 1024 ? 1.15 : (longest >= 812 ? 1.08 : 1.0)
                readerFontScale = scale
                #else
                readerFontScale = 1.0
                #endif
                readerFontInitialized = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveProgress(index: Int) {
        book.lastReadIndex = index
        book.lastReadAt = Date()
        try? modelContext.save()
    }

    private func next() {
        if currentPage + 1 < currentPageCount {
            currentPage += 1
        } else if selection + 1 < chapters.count {
            selection += 1
            currentPage = 0
        }
    }

    private func prev() {
        if currentPage > 0 {
            currentPage -= 1
        } else if selection > 0 {
            selection -= 1
            currentPage = 0
        }
    }

    private var tocSheet: some View {
        NavigationStack {
            List(Array(chapters.enumerated()), id: \.offset) { idx, url in
                Button {
                    selection = idx
                    showTOC = false
                } label: {
                    HStack {
                        Text(chapterTitle(for: url, index: idx))
                        if idx == selection { Spacer(); Image(systemName: "checkmark").foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Table of Contents")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showTOC = false } } }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Theme")) {
                    Picker("Theme", selection: $readerTheme) {
                        ForEach(ReaderTheme.allCases) { t in Text(t.title).tag(t.rawValue) }
                    }.pickerStyle(.segmented)
                }
                Section(header: Text("Font Size")) {
                    Slider(value: $readerFontScale, in: 0.7...1.6, step: 0.05) { Text("Size") }
                    Text("\(Int(readerFontScale * 100))%")
                }
            }
            .navigationTitle("Reading Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }
    }

    private func chapterTitle(for url: URL, index: Int) -> String {
        // Try navMap first using relative href
        let rel = url.path.replacingOccurrences(of: basePathRelative + "/", with: "")
        if let title = navMap[rel] { return title }
        if let data = try? Data(contentsOf: url), let html = String(data: data, encoding: .utf8) {
            if let rangeOpen = html.range(of: "<title>", options: .caseInsensitive), let rangeClose = html.range(of: "</title>", options: .caseInsensitive), rangeOpen.upperBound < rangeClose.lowerBound {
                let t = String(html[rangeOpen.upperBound..<rangeClose.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    }
}

private struct HTMLFileView: UIViewRepresentable {
    let fileURL: URL
    let readAccessURL: URL
    let theme: ReaderTheme
    let fontScale: Double
    @Binding var pageIndex: Int
    let onPageCount: (Int) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.scrollView.isPagingEnabled = false
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.backgroundColor = .systemBackground
        wv.isOpaque = false
        let coord = context.coordinator
        coord.onPageCount = onPageCount
        coord.theme = theme
        coord.fontScale = fontScale
        wv.navigationDelegate = coord
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // use loadFileURL for local file with read access to root
        if webView.url != fileURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        } else {
            context.coordinator.theme = theme
            context.coordinator.fontScale = fontScale
            context.coordinator.applyStyles(webView: webView, theme: theme, fontScale: fontScale)
            context.coordinator.setPage(webView: webView, index: pageIndex)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onPageCount: ((Int) -> Void)?
        var theme: ReaderTheme = .light
        var fontScale: Double = 1.0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyStyles(webView: webView, theme: theme, fontScale: fontScale)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updatePageCount(webView: webView)
            }
        }

        func applyStyles(webView: WKWebView, theme: ReaderTheme, fontScale: Double) {
            let css = theme.css(fontScale: fontScale)
            let js = """
            (function(){
              var style = document.getElementById('paper-reader-style');
              if(!style){ style = document.createElement('style'); style.id='paper-reader-style'; document.documentElement.appendChild(style); }
              var w = Math.floor((window.visualViewport && window.visualViewport.width) ? window.visualViewport.width : (window.innerWidth || 0));
              var base = `\(css)`;
              var extras = `html,body{margin:0;height:100vh;overflow:hidden;box-sizing:border-box;} *{box-sizing:inherit;} body{ -webkit-column-width: ${w}px; -webkit-column-gap: 0px; } img,svg,video{max-width:100%;height:auto;} pre,code{white-space:pre-wrap;} table{width:100%;table-layout:fixed;} p,li{word-break:break-word;overflow-wrap:break-word;} h1,h2,h3,h4,h5,h6{break-inside:avoid; -webkit-column-break-inside:avoid;}`;
              style.textContent = base + extras;
              if(!window._paperResizeHooked){
                window.addEventListener('resize', function(){
                  var w = Math.floor((window.visualViewport && window.visualViewport.width) ? window.visualViewport.width : (window.innerWidth || 0));
                  var base = `\(css)`;
                  var extras = `html,body{margin:0;height:100vh;overflow:hidden;box-sizing:border-box;} *{box-sizing:inherit;} body{ -webkit-column-width: ${w}px; -webkit-column-gap: 0px; } img,svg,video{max-width:100%;height:auto;} pre,code{white-space:pre-wrap;} table{width:100%;table-layout:fixed;} p,li{word-break:break-word;overflow-wrap:break-word;} h1,h2,h3,h4,h5,h6{break-inside:avoid; -webkit-column-break-inside:avoid;}`;
                  style.textContent = base + extras;
                });
                window._paperResizeHooked = true;
              }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.updatePageCount(webView: webView)
                }
            })
        }

        func setPage(webView: WKWebView, index: Int) {
            let js = """
            (function(){
              var w = Math.floor((window.visualViewport && window.visualViewport.width) ? window.visualViewport.width : (window.innerWidth || 0));
              var x = Math.max(0, Math.floor(\(index)) * Math.max(1,w));
              if(document.scrollingElement){ document.scrollingElement.scrollLeft = x; }
              return x;
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func updatePageCount(webView: WKWebView) {
            let js = """
            (function(){
              var w = Math.floor((window.visualViewport && window.visualViewport.width) ? window.visualViewport.width : (window.innerWidth || 0));
              var total = (document.scrollingElement ? document.scrollingElement.scrollWidth : document.documentElement.scrollWidth);
              var count = Math.max(1, Math.ceil(total / Math.max(1, w)));
              return count;
            })();
            """
            webView.evaluateJavaScript(js) { result, _ in
                if let n = result as? Int { self.onPageCount?(n) }
                else if let s = result as? String, let n = Int(s) { self.onPageCount?(n) }
            }
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func css(fontScale: Double) -> String {
        switch self {
        case .light:
            return baseCSS(bg: "#FFFFFF", fg: "#111111", fontScale: fontScale)
        case .sepia:
            return baseCSS(bg: "#F4ECD8", fg: "#5B4636", fontScale: fontScale)
        case .dark:
            return baseCSS(bg: "#000000", fg: "#E6E6E6", fontScale: fontScale)
        }
    }
    private func baseCSS(bg: String, fg: String, fontScale: Double) -> String {
        return "html,body{background:\(bg);color:\(fg);line-height:1.6;font-size:\(Int(fontScale*100))%;padding: 1.2em;} img{max-width:100%;height:auto;} a{color:inherit;}"
    }
}
