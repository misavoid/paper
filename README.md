**Paper — iPad EPUB Library & Reader**

- **Platform:** iPadOS (also runs on iPhone)
- **Tech:** SwiftUI, SwiftData, WKWebView
- **Focus:** Clean local library management + fast, simple reading

**Features**
- **Library:** Grid with covers, search, sort (Recent/Title/Author), multi‑select delete.
- **Imports:** Plus button imports `.epub` from Files; copies into `Documents/Ebooks/`.
- **Metadata:** Extracts title/author/subjects and cover (OPF + nav.xhtml where available); filename fallback.
- **Collections:** Browse by author or genre (subjects → first subject → genre).
- **Reader:** Full‑screen, true page‑turn pagination (no scrolling), tap to reveal UI, TOC, themes (Light/Sepia/Dark), font size slider, chapter/page progress, “Continue reading”.
- **Storage:** Covers in `Documents/Covers/`. Extracted EPUBs cached in `Library/Caches/ExtractedEPUBs/<book-id>/` and auto‑cleaned on book deletion.

**Requirements**
- **Xcode:** 16.x (Swift 5.10+).  
- **OS target:** iOS/iPadOS per project settings (currently 18.5).

**Run**
- Open `paper.xcodeproj` in Xcode.
- Select an iPad simulator or a physical iPad.
- Build & run. On first launch, tap Library’s `+` to import `.epub` files from Files.

**Reader Controls**
- **Tap page:** Toggle top/bottom overlays.
- **Arrows:** Always visible; turn pages/chapters.
- **Home:** In overlay, returns to Library.
- **TOC:** Jump to any chapter (uses nav.xhtml titles when present; falls back to `<title>` or filename).
- **Settings:** Theme + font size applied across the whole book. Defaults auto‑adjust by device size on first run.

**Project Structure**
- `paper/App/`: App entry + root `ContentView`.
- `paper/Models/`: SwiftData models (e.g., `Ebook`).
- `paper/Views/`: SwiftUI screens (Library, Authors, Collections, Detail).
- `paper/Reader/`: Reader UI (`ReaderView`) and extraction (`EpubExtractor`).
- `paper/Parsing/`: ZIP + EPUB parsing (`ZipSimple`, `EPUBParser`).
- `paper/Storage/`: Filesystem utilities (`FileStore`).

**Data & Persistence**
- **SwiftData Store:** Located under Application Support as `EbookStore.store`.  
  If opening the on‑device store fails (e.g., schema drift), the app deletes the store once and retries; final fallback is in‑memory (app won’t crash).
- **Model:** `Ebook` stores title, author, genre, file/cover names, date added, and reading progress (`lastReadIndex`, `lastReadPage`, `lastReadAt`).

**Security & Entitlements**
- App sandbox enabled; user‑selected read‑only access for imports.  
- iCloud/Push disabled per requirements.

**Known Limitations**
- **EPUB/ZIP:** No encrypted EPUB support; limited ZIP64 handling.
- **Content CSS:** Highly custom EPUB CSS can still affect pagination; we normalize with base CSS and column layout, but complex layouts (large tables/pre/code) may vary.
- **Progress:** Chapter/page progress is tracked; mid‑paragraph anchors are not yet preserved across reloads.

**Roadmap**
- Hierarchical TOC (nested sections) with breadcrumbs.
- Per‑chapter last‑page memory when navigating back to earlier chapters.
- Margin/line‑height preferences; theme auto (match system).
- Drag & drop import; share‑sheet import handler.

**Troubleshooting**
- If the app previously crashed on launch due to data store issues, it now safely falls back; to reset, delete the app or remove `Application Support/EbookStore.store` from the app’s container.
- If pagination looks off for a specific EPUB, try reopening the reader or rotating once; the reader recomputes pages on viewport size changes.

**Contributing**
- PRs welcome for reader features, EPUB parsing, and accessibility.

**License**
- Add a license file if you plan to distribute publicly.

