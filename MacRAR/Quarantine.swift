import Foundation

/// Carries the quarantine information (com.apple.quarantine) of an archive downloaded from the internet over to the extracted items.
/// Without it, apps and scripts inside the archive could run without passing the Gatekeeper check
/// (the macOS counterpart of CVE-2025-0411 on Windows). Archive Utility behaves the same way.
enum Quarantine {
    private static let attr = "com.apple.quarantine"

    /// The file's quarantine value; nil if none
    static func value(of path: String) -> Data? {
        let size = getxattr(path, attr, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let n = data.withUnsafeMutableBytes { getxattr(path, attr, $0.baseAddress, size, 0, 0) }
        return n > 0 ? data.prefix(n) : nil
    }

    /// Applies the quarantine value to every item this extraction wrote in `dest` (those changed after `since`).
    /// tops: the archive's top-level names, so files written into folders that already existed are found too.
    /// Symbolic links are not followed, so the walk never leaves the destination folder.
    static func apply(_ value: Data, dest: String, tops: [String], since: Date) {
        let fm = FileManager.default
        let limit = since.timeIntervalSince1970 - 2   // HFS+/FAT timestamps have one-second precision
        func info(_ p: String) -> (changed: Bool, isDir: Bool)? {
            var st = stat()
            guard lstat(p, &st) == 0 else { return nil }
            let ctime = Double(st.st_ctimespec.tv_sec) + Double(st.st_ctimespec.tv_nsec) / 1e9
            return (ctime >= limit, (st.st_mode & S_IFMT) == S_IFDIR)
        }
        func tag(_ p: String) {
            _ = value.withUnsafeBytes { setxattr(p, attr, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        }

        // Top-level names + new items extracted under a new name (-aou)
        var roots = Set(tops)
        for name in (try? fm.contentsOfDirectory(atPath: dest)) ?? [] {
            if info((dest as NSString).appendingPathComponent(name))?.changed == true { roots.insert(name) }
        }
        for name in roots {
            let root = (dest as NSString).appendingPathComponent(name)
            guard let r = info(root) else { continue }
            if r.changed { tag(root) }
            guard r.isDir, let walker = fm.enumerator(atPath: root) else { continue }
            for case let rel as String in walker {
                let p = (root as NSString).appendingPathComponent(rel)
                if info(p)?.changed == true { tag(p) }
            }
        }
    }
}
