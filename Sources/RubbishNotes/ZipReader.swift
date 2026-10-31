import Compression
import Foundation

/// Unpacks a .zip into a folder, without leaving the sandbox (no `ditto`):
/// stored and deflated entries, which is what the Finder and the app's own
/// exports write. Entries that would land outside the folder, symbolic links
/// and the Finder's `__MACOSX` resource forks are skipped.
enum ZipReader {
    enum Failure: Error, Equatable {
        case notAZip, unsupported, damaged, tooLarge
    }

    /// Larger single files are refused; a backup's images stay well below it.
    static let maxEntryBytes = 512 * 1024 * 1024
    /// Everything unpacked together, so a crafted archive can't fill the disk.
    static let maxTotalBytes = 4 * 1024 * 1024 * 1024

    /// Writes every file in the archive under `folder`; returns their relative paths.
    @discardableResult
    static func extract(_ zip: URL, to folder: URL) throws -> [String] {
        let bytes = [UInt8](try Data(contentsOf: zip, options: .mappedIfSafe))
        let entries = try centralDirectory(of: bytes)
        guard entries.reduce(0, { $0 + $1.size }) <= maxTotalBytes else { throw Failure.tooLarge }
        var written: [String] = []
        for entry in entries {
            guard let path = safePath(entry.name), !entry.isSymlink else { continue }
            let target = folder.appendingPathComponent(path)
            if entry.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            let content = try contents(of: entry, in: bytes)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: target)
            // Notes keep the dates they were last changed on, not the day they came in.
            if let date = entry.modified {
                try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
            }
            written.append(path)
        }
        return written
    }

    /// A relative path inside the folder, or nil for names that must not be written.
    static func safePath(_ name: String) -> String? {
        let parts = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
              !parts.contains(where: { $0 == ".." || $0 == "." }),
              parts.first != "__MACOSX", !(parts.last ?? "").hasPrefix("._") else { return nil }
        return parts.joined(separator: "/")
    }

    struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localOffset: Int
        let isSymlink: Bool
        /// MS-DOS time and date fields, in local time to 2 seconds.
        var dosTime: UInt16 = 0
        var dosDate: UInt16 = 0

        var modified: Date? {
            var parts = DateComponents()
            parts.year = 1980 + Int(dosDate >> 9)
            parts.month = Int(dosDate >> 5 & 0xF)
            parts.day = Int(dosDate & 0x1F)
            parts.hour = Int(dosTime >> 11)
            parts.minute = Int(dosTime >> 5 & 0x3F)
            parts.second = Int(dosTime & 0x1F) * 2
            guard dosDate != 0, parts.month != 0, parts.day != 0 else { return nil }
            return Calendar.current.date(from: parts)
        }
    }

    static func centralDirectory(of bytes: [UInt8]) throws -> [Entry] {
        // The end record sits in the last 22 bytes, plus up to 64 KB of comment.
        guard bytes.count >= 22 else { throw Failure.notAZip }
        var end = -1
        for i in stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65_535), by: -1)
        where bytes.u32(at: i) == 0x0605_4b50 {
            end = i
            break
        }
        guard end >= 0 else { throw Failure.notAZip }
        let count = Int(bytes.u16(at: end + 10))
        var offset = Int(bytes.u32(at: end + 16))
        // ZIP64 marks its sizes this way; app and Finder backups never need it.
        guard bytes.u32(at: end + 16) != 0xFFFF_FFFF, count != 0xFFFF else { throw Failure.unsupported }
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, bytes.u32(at: offset) == 0x0201_4b50 else { throw Failure.damaged }
            let nameLength = Int(bytes.u16(at: offset + 28))
            let extraLength = Int(bytes.u16(at: offset + 30))
            let commentLength = Int(bytes.u16(at: offset + 32))
            guard offset + 46 + nameLength <= bytes.count else { throw Failure.damaged }
            let nameBytes = Array(bytes[(offset + 46)..<(offset + 46 + nameLength)])
            let mode = bytes.u32(at: offset + 38) >> 16
            let compressed = bytes.u32(at: offset + 20), size = bytes.u32(at: offset + 24)
            guard compressed != 0xFFFF_FFFF, size != 0xFFFF_FFFF else { throw Failure.unsupported }
            entries.append(Entry(
                name: String(decoding: nameBytes, as: UTF8.self),
                method: bytes.u16(at: offset + 10),
                crc: bytes.u32(at: offset + 16),
                compressedSize: Int(compressed),
                size: Int(size),
                localOffset: Int(bytes.u32(at: offset + 42)),
                isSymlink: mode & 0xF000 == 0xA000,
                dosTime: bytes.u16(at: offset + 12),
                dosDate: bytes.u16(at: offset + 14)
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func contents(of entry: Entry, in bytes: [UInt8]) throws -> Data {
        guard entry.size <= maxEntryBytes else { throw Failure.tooLarge }
        let local = entry.localOffset
        guard local + 30 <= bytes.count, bytes.u32(at: local) == 0x0403_4b50 else { throw Failure.damaged }
        let start = local + 30 + Int(bytes.u16(at: local + 26)) + Int(bytes.u16(at: local + 28))
        guard start + entry.compressedSize <= bytes.count else { throw Failure.damaged }
        let raw = Data(bytes[start ..< start + entry.compressedSize])
        let content: Data
        switch entry.method {
        case 0: content = raw
        case 8: content = try inflate(raw, size: entry.size)
        default: throw Failure.unsupported
        }
        guard content.count == entry.size, CRC32.checksum(content) == entry.crc else { throw Failure.damaged }
        return content
    }

    /// Raw DEFLATE, which the Compression framework calls ZLIB.
    private static func inflate(_ source: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !source.isEmpty else { throw Failure.damaged }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            source.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, source.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.damaged }
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { c, byte in table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
    }
}

private extension Array where Element == UInt8 {
    func u16(at i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(at i: Int) -> UInt32 { UInt32(u16(at: i)) | UInt32(u16(at: i + 2)) << 16 }
}
