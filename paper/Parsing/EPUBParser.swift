import Foundation

struct EPUBMetadata {
    var title: String?
    var author: String?
    var subjects: [String] = []
    var coverData: Data?
    var coverExt: String = "jpg"
}

enum EPUBParserError: Error { case invalid, missingContainer, missingOPF }

final class EPUBParser: NSObject, XMLParserDelegate {
    private var textStack: [String] = []
    private var currentElement: String = ""
    private var metadata = EPUBMetadata()

    // For OPF manifest parsing
    private var manifestItems: [String: (href: String, properties: String?)] = [:]
    private var spineItemRefs: [String] = []
    private var basePath: String = ""

    func parseMetadata(fromEpubAt url: URL) throws -> EPUBMetadata {
        let zip = try ZipSimple(url: url)
        // 1) Read META-INF/container.xml
        guard let containerEntry = zip.entries["META-INF/container.xml"] else { throw EPUBParserError.missingContainer }
        let containerData = try zip.data(for: containerEntry.name)
        let opfPath = try parseContainerXML(containerData)
        // 2) Read OPF
        guard let opfEntry = zip.entries[opfPath] else { throw EPUBParserError.missingOPF }
        basePath = (opfPath as NSString).deletingLastPathComponent
        let opfData = try zip.data(for: opfEntry.name)
        parseOPF(opfData)
        // 3) Resolve cover
        if let coverHref = findCoverHref() {
            let fullPath = (basePath as NSString).appendingPathComponent(coverHref)
            if let entry = zip.entries[fullPath] {
                metadata.coverData = try? zip.data(for: entry.name)
                metadata.coverExt = ((coverHref as NSString).pathExtension.isEmpty ? "jpg" : (coverHref as NSString).pathExtension)
            }
        }
        return metadata
    }

    private func parseContainerXML(_ data: Data) throws -> String {
        // A quick and dirty parse to find rootfile full-path
        let parser = XMLParser(data: data)
        var result: String?
        class ContainerDelegate: NSObject, XMLParserDelegate {
            var fullPath: String?
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
                if elementName.lowercased().hasSuffix("rootfile") {
                    if let fp = attributeDict["full-path"] ?? attributeDict["fullPath"] { fullPath = fp }
                }
            }
        }
        let del = ContainerDelegate()
        parser.delegate = del
        parser.parse()
        result = del.fullPath
        guard let path = result else { throw EPUBParserError.invalid }
        return path
    }

    private func parseOPF(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    // MARK: XMLParserDelegate for OPF
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        textStack.removeAll(keepingCapacity: true)
        if currentElement == "meta" {
            // sometimes cover is signaled via <meta name="cover" content="cover-image-id"/>
            // handled later using manifest map
        }
        if currentElement == "item" {
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifestItems[id] = (href: href, properties: attributeDict["properties"])
            }
        } else if currentElement == "itemref" {
            if let idref = attributeDict["idref"] { spineItemRefs.append(idref) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textStack.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = textStack.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let name = elementName.lowercased()
        if name.hasSuffix("title"), !text.isEmpty {
            metadata.title = text
        } else if name.hasSuffix("creator") || name == "author" {
            if !(text.isEmpty) { metadata.author = text }
        } else if name.hasSuffix("subject") {
            if !text.isEmpty { metadata.subjects.append(text) }
        }
        currentElement = ""
        textStack.removeAll(keepingCapacity: true)
    }

    private func findCoverHref() -> String? {
        // heuristics: look for manifest item with properties containing "cover-image"
        if let item = manifestItems.values.first(where: { ($0.properties ?? "").contains("cover-image") }) {
            return item.href
        }
        // or meta name=cover content=id is inside OPF, but we didn't capture it here.
        // fallback: find href that looks like cover image
        if let candidate = manifestItems.values.first(where: { $0.href.lowercased().contains("cover") && ($0.href.lowercased().hasSuffix(".jpg") || $0.href.lowercased().hasSuffix(".jpeg") || $0.href.lowercased().hasSuffix(".png")) }) {
            return candidate.href
        }
        return nil
    }
}

// MARK: - Reading order package
struct EpubPackage {
    let basePath: String
    let spineHrefs: [String]
    let navMap: [String:String] // href -> title
}

extension EPUBParser {
    func parsePackage(fromEpubAt url: URL) throws -> EpubPackage {
        let zip = try ZipSimple(url: url)
        // container.xml
        guard let containerEntry = zip.entries["META-INF/container.xml"] else { throw EPUBParserError.missingContainer }
        let containerData = try zip.data(for: containerEntry.name)
        let opfPath = try parseContainerXML(containerData)
        guard let opfEntry = zip.entries[opfPath] else { throw EPUBParserError.missingOPF }
        basePath = (opfPath as NSString).deletingLastPathComponent
        // Parse OPF to build manifest + spine
        let opfData = try zip.data(for: opfEntry.name)
        manifestItems.removeAll(); spineItemRefs.removeAll()
        parseOPF(opfData)
        let hrefs: [String] = spineItemRefs.compactMap { manifestItems[$0]?.href }
        var nav: [String:String] = [:]
        if let navId = manifestItems.first(where: { ($0.value.properties ?? "").contains("nav") })?.key,
           let navHref = manifestItems[navId]?.href {
            let full = (basePath as NSString).appendingPathComponent(navHref)
            if let entry = zip.entries[full], let data = try? zip.data(for: entry.name) {
                nav = parseNavXHTML(data: data)
            }
        }
        return EpubPackage(basePath: basePath, spineHrefs: hrefs, navMap: nav)
    }
}

// MARK: - Parse nav.xhtml for TOC
extension EPUBParser {
    private struct NavContext {
        var capturingTOC = false
        var stack: [String] = []
        var currentHref: String?
        var currentText: String = ""
        var map: [String:String] = [:]
    }

    fileprivate func parseNavXHTML(data: Data) -> [String:String] {
        class NavDelegate: NSObject, XMLParserDelegate {
            var ctx = NavContext()
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
                let name = elementName.lowercased()
                ctx.stack.append(name)
                if name == "nav" {
                    let type = (attributeDict["epub:type"] ?? attributeDict["type"] ?? "").lowercased()
                    if type.contains("toc") { ctx.capturingTOC = true }
                }
                if ctx.capturingTOC && name == "a" {
                    ctx.currentHref = attributeDict["href"]
                    ctx.currentText = ""
                }
            }
            func parser(_ parser: XMLParser, foundCharacters string: String) { if ctx.capturingTOC { ctx.currentText += string } }
            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                let name = elementName.lowercased()
                if ctx.capturingTOC && name == "a" {
                    if let href = ctx.currentHref {
                        let title = ctx.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty { ctx.map[href] = title }
                    }
                    ctx.currentHref = nil
                    ctx.currentText = ""
                }
                _ = ctx.stack.popLast()
                if name == "nav" && ctx.capturingTOC { ctx.capturingTOC = false }
            }
        }
        let parser = XMLParser(data: data)
        let del = NavDelegate()
        parser.delegate = del
        parser.parse()
        return del.ctx.map
    }
}
