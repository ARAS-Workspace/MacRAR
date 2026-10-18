import Foundation

/// Archives written the way an attacker writes them, which no archiver would: ZIP entries with any name and Unix mode
/// (a symbolic link is an entry with mode 0o120777 whose data is its target), and TAR entries with any name, type and
/// link (type "2" a symbolic link, "1" a hard link). Stored, uncompressed.
enum HostileArchive {
    struct ZipEntry {
        let name: String
        let data: Data
        let mode: UInt32

        static func file(_ name: String, _ text: String = "x") -> ZipEntry {
            ZipEntry(name: name, data: Data(text.utf8), mode: 0o100644)
        }
        static func symlink(_ name: String, to target: String) -> ZipEntry { ZipEntry(name: name, data: Data(target.utf8), mode: 0o120777) }
    }

    struct TarEntry {
        let name: String
        let data: Data
        let type: UInt8
        let link: String

        static func file(_ name: String, _ text: String = "x") -> TarEntry {
            TarEntry(name: name, data: Data(text.utf8), type: 0x30, link: "")
        }
        static func symlink(_ name: String, to target: String) -> TarEntry { TarEntry(name: name, data: Data(), type: 0x32, link: target) }
        static func hardLink(_ name: String, to target: String) -> TarEntry { TarEntry(name: name, data: Data(), type: 0x31, link: target) }
    }

    static func zip(_ entries: [ZipEntry]) -> Data {
        var archive = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8), offset = UInt32(archive.count), sum = crc32(entry.data), size = UInt32(entry.data.count)
            // Version 2.0, the UTF-8 flag, stored, no date
            archive += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0)
            archive += le32(sum) + le32(size) + le32(size) + le16(UInt16(name.count)) + le16(0) + name + entry.data
            // Made on Unix (3), so that the mode in the high half of the external attributes counts
            central += le32(0x0201_4B50) + le16(3 << 8 | 20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0)
            central += le32(sum) + le32(size) + le32(size) + le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(entry.mode << 16) + le32(offset) + name
        }
        let centralOffset = UInt32(archive.count)
        archive += central + le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        return archive + le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
    }

    static func tar(_ entries: [TarEntry]) -> Data {
        var archive = Data()
        for entry in entries {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, at offset: Int, length: Int) {
                for (index, byte) in text.utf8.prefix(length).enumerated() { header[offset + index] = byte }
            }
            // A name longer than the 100 bytes of its field goes on in the ustar prefix, split at a slash
            if entry.name.utf8.count > 100, let slash = entry.name.lastIndex(of: "/") {
                put(String(entry.name[entry.name.index(after: slash)...]), at: 0, length: 100)
                put(String(entry.name[..<slash]), at: 345, length: 155)
            } else {
                put(entry.name, at: 0, length: 100)
            }
            put("0000644", at: 100, length: 7)
            put("0000000", at: 108, length: 7)
            put("0000000", at: 116, length: 7)
            put(String(format: "%011o", entry.data.count), at: 124, length: 11)
            put(String(format: "%011o", 1_700_000_000), at: 136, length: 11)
            header[156] = entry.type
            put(entry.link, at: 157, length: 100)
            put("ustar", at: 257, length: 5)
            put("00", at: 263, length: 2)
            // The checksum is taken with its own field as spaces
            for index in 148..<156 { header[index] = 0x20 }
            put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }), at: 148, length: 6)
            header[154] = 0
            archive += Data(header) + entry.data
            if entry.data.count % 512 != 0 { archive += Data(count: 512 - entry.data.count % 512) }
        }
        return archive + Data(count: 1024)
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}
