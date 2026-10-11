import Foundation

enum Formats {
    /// Extensions the app can open
    static let openable: Set<String> = [
        "rar", "zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst", "lz4", "lzma", "tlz", "z",
        "cab", "arj", "lzh", "lha", "cpio", "iso", "wim", "swm", "esd", "deb", "rpm", "jar", "war", "ear", "apk", "ipa",
        "xpi", "crx", "nupkg", "msi", "chm", "udf", "vhd", "vhdx", "vmdk", "qcow2", "squashfs", "cramfs", "ext", "ext2", "ext3", "ext4",
        "hfs", "hfsx", "dmg", "xar", "pkg", "ar", "a", "lib", "zipx", "br", "001", "lz", "uue", "bzip2", "gzip", "sfx",
    ]

    static func isArchive(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if openable.contains(ext) { return true }
        return ext.range(of: #"^r\d\d$"#, options: .regularExpression) != nil
    }

    static func kind(of path: String) -> ArchiveKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "rar" || ext.range(of: #"^r\d\d$"#, options: .regularExpression) != nil { return .rar }
        return .other
    }

    static func isMultiVolume(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.range(of: #"\.part\d+\.rar$|\.\d{3}$|\.r\d\d$|\.z\d\d$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
