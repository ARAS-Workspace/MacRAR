import Foundation

/// ZIP archives as Windows' own zip and older Windows tools write them: stored files with no UTF-8 flag and no Unicode
/// extra field, each name in the bytes of a Windows code page and each entry naming the system it was made on (FAT for
/// names in the OEM code page, 857 on Turkish Windows). Each file holds its own name.
enum WindowsZip {
    struct Entry {
        let name: [UInt8]
        /// The "made by" system: 0 FAT, 3 Unix, 14 VFAT
        let host: UInt8
    }

    /// `name` in the bytes of Windows code page `codePage` (65001 for UTF-8).
    static func entry(_ name: String, codePage: UInt32, host: UInt8 = 0) -> Entry {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringConvertWindowsCodepageToEncoding(codePage)))
        guard let bytes = name.data(using: encoding) else { preconditionFailure("\(name) is not in code page \(codePage)") }
        return Entry(name: [UInt8](bytes), host: host)
    }

    static func data(_ entries: [Entry]) -> Data {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(archive.count)
            let crc = crc32(entry.name)
            let size = UInt32(entry.name.count)
            archive.append(le32: 0x0403_4B50)
            archive.append(le16: [20, 0, 0, 0x6000, 0x5B4D])
            archive.append(le32: crc, size, size)
            archive.append(le16: [UInt16(entry.name.count), 0])
            archive.append(contentsOf: entry.name + entry.name)
            central.append(le32: 0x0201_4B50)
            central.append(le16: [UInt16(entry.host) << 8 | 20, 20, 0, 0, 0x6000, 0x5B4D])
            central.append(le32: crc, size, size)
            central.append(le16: [UInt16(entry.name.count), 0, 0, 0, 0])
            central.append(le32: 0x20, offset)
            central.append(contentsOf: entry.name)
        }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: [0, 0, UInt16(entries.count), UInt16(entries.count)])
        archive.append(le32: UInt32(central.count), centralOffset)
        archive.append(le16: [0])
        return archive
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}

private extension Data {
    mutating func append(le16 values: [UInt16]) {
        for value in values { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    }

    mutating func append(le32 values: UInt32...) {
        for value in values { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    }
}
