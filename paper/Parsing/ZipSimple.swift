import Foundation
import Compression

// Minimal ZIP reader sufficient for EPUBs (no ZIP64, no encryption).
enum ZipError: Error { case notZip, unsupported, truncated, entryNotFound }

struct ZipEntry {
    let name: String
    let method: UInt16
    let localHeaderOffset: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
}

final class ZipSimple {
    private let fh: FileHandle
    private let size: UInt64
    private(set) var entries: [String: ZipEntry] = [:]

    init(url: URL) throws {
        self.fh = try FileHandle(forReadingFrom: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        try readCentralDirectory()
    }

    deinit { try? fh.close() }

    func data(for path: String) throws -> Data {
        guard let e = entries[path] else { throw ZipError.entryNotFound }
        try fh.seek(toOffset: UInt64(e.localHeaderOffset))
        let localHeader = try fh.read(upToCount: 30) ?? Data()
        if localHeader.count < 30 { throw ZipError.truncated }
        // local file header signature 0x04034b50
        let sig = le32(localHeader, 0)
        guard sig == 0x04034b50 else { throw ZipError.notZip }
        let nameLen = le16(localHeader, 26)
        let extraLen = le16(localHeader, 28)
        let dataOffset = UInt64(e.localHeaderOffset) + 30 + UInt64(nameLen + extraLen)
        try fh.seek(toOffset: dataOffset)
        let comp = try fh.read(upToCount: Int(e.compressedSize)) ?? Data()
        if e.method == 0 { return comp }
        if e.method == 8 { // deflate
            return try inflate(data: comp, uncompressedSize: Int(e.uncompressedSize))
        }
        throw ZipError.unsupported
    }

    private func inflate(data: Data, uncompressedSize: Int) throws -> Data {
        var dst = Data(count: max(uncompressedSize, data.count * 2))
        let result = dst.withUnsafeMutableBytes { dstBuf -> Int in
            return data.withUnsafeBytes { srcBuf -> Int in
                let decoded = compression_decode_buffer(dstBuf.baseAddress!.assumingMemoryBound(to: UInt8.self), dstBuf.count,
                                                        srcBuf.baseAddress!.assumingMemoryBound(to: UInt8.self), srcBuf.count,
                                                        nil, COMPRESSION_ZLIB)
                return decoded
            }
        }
        if result == 0 { throw ZipError.truncated }
        dst.count = result
        return dst
    }

    private func readCentralDirectory() throws {
        // Search for End of Central Directory (EOCD) signature 0x06054b50 in last 64KB
        let maxSearch = min(UInt64(65557), size)
        let start = size - maxSearch
        try fh.seek(toOffset: start)
        let tail = try fh.readToEnd() ?? Data()
        var eocdOffsetInTail: Int? = nil
        let sig0: UInt8 = 0x50, sig1: UInt8 = 0x4b, sig2: UInt8 = 0x05, sig3: UInt8 = 0x06
        let bytes = Array(tail)
        if bytes.count >= 22 {
            for i in stride(from: bytes.count - 4, through: 0, by: -1) {
                if bytes[i] == sig0 && bytes[i+1] == sig1 && bytes[i+2] == sig2 && bytes[i+3] == sig3 {
                    eocdOffsetInTail = i
                    break
                }
            }
        }
        guard let eocdIdx = eocdOffsetInTail else { throw ZipError.notZip }
        let eocd = tail.subdata(in: eocdIdx ..< eocdIdx + 22)
        let cdSize = le32(eocd, 12)
        let cdOffset = le32(eocd, 16)
        try fh.seek(toOffset: UInt64(cdOffset))
        let cdData = try fh.read(upToCount: Int(cdSize)) ?? Data()
        var cursor = 0
        while cursor + 46 <= cdData.count {
            // central directory header signature 0x02014b50
            let sig = le32(cdData, cursor)
            guard sig == 0x02014b50 else { break }
            let compMethod = le16(cdData, cursor + 10)
            let compSize = le32(cdData, cursor + 20)
            let uncompSize = le32(cdData, cursor + 24)
            let nameLen = Int(le16(cdData, cursor + 28))
            let extraLen = Int(le16(cdData, cursor + 30))
            let commentLen = Int(le16(cdData, cursor + 32))
            let localHeaderRel = le32(cdData, cursor + 42)
            let nameData = cdData.subdata(in: cursor + 46 ..< cursor + 46 + nameLen)
            guard let name = String(data: nameData, encoding: .utf8) else { throw ZipError.truncated }
            let entry = ZipEntry(name: name, method: compMethod, localHeaderOffset: localHeaderRel, compressedSize: compSize, uncompressedSize: uncompSize)
            entries[name] = entry
            cursor += 46 + nameLen + extraLen + commentLen
        }
        if entries.isEmpty { throw ZipError.truncated }
    }
}

extension Data {
    // helper to iterate bytes windows
    func windows(ofCount k: Int) -> AnySequence<SubSequence> {
        let n = count
        guard k > 0, n >= k else { return AnySequence([]) }
        var i = startIndex
        return AnySequence {
            AnyIterator {
                if i.advanced(by: k) <= self.endIndex {
                    defer { i = i.advanced(by: 1) }
                    return self[i ..< i.advanced(by: k)]
                }
                return nil
            }
        }
    }
}

// MARK: - Little-endian readers that avoid alignment issues
private func le16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset + 2 <= data.count else { return 0 }
    let b0 = UInt16(data[offset])
    let b1 = UInt16(data[offset + 1]) << 8
    return b0 | b1
}

private func le32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1]) << 8
    let b2 = UInt32(data[offset + 2]) << 16
    let b3 = UInt32(data[offset + 3]) << 24
    return b0 | b1 | b2 | b3
}
