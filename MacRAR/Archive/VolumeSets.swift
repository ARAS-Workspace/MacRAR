import Foundation

/// The volumes of a split archive, chosen in Finder, opened or dropped: 7-Zip reads a whole set from its first volume,
/// and reads a later one as an archive of its own, which fails or shows only the items that start in it.
enum VolumeSets {
    /// One archive per volume set: its first volume when that is chosen or on the disk beside the others, otherwise the
    /// earliest one chosen. Sets are named name.partN.rar (part1, part01 or part001), name.7z.001 … and, the old way,
    /// name.rar with name.r00, name.r01 … or name.zip with name.z01 …; anything else is kept as it is, in its place.
    static func firstVolumes(_ paths: [String]) -> [String] {
        var result: [String] = []
        var placed: [String: (index: Int, number: Int)] = [:]
        for path in paths {
            guard let volume = Volume(path) else { result.append(path); continue }
            let pick = FileManager.default.fileExists(atPath: volume.first)
                ? (path: volume.first, number: Int.min) : (path: path, number: volume.number)
            if let earlier = placed[volume.set] {
                if pick.number < earlier.number {
                    result[earlier.index] = pick.path
                    placed[volume.set] = (earlier.index, pick.number)
                }
            } else {
                placed[volume.set] = (result.count, pick.number)
                result.append(pick.path)
            }
        }
        return result
    }
}

/// A file named as one volume of a split archive: the set it belongs to, its place in the set, and the set's first
/// volume.
private struct Volume {
    let set: String
    let number: Int
    let first: String

    init?(_ path: String) {
        let ns = path as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        let lowerExt = ext.lowercased()
        if lowerExt == "rar", let part = stem.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) {
            // name.part3.rar: rar pads the numbers to the widest, part01 when there are ten or more
            let digits = stem[part].dropFirst(".part".count)
            let base = String(stem[..<part.lowerBound])
            set = base.lowercased() + ".partN.rar"
            number = Int(digits) ?? 0
            first = base + stem[part].prefix(".part".count) + String(repeating: "0", count: digits.count - 1) + "1." + ext
        } else if lowerExt.range(of: #"^\d{3}$"#, options: .regularExpression) != nil,
                  ["7z", "zip", "rar", "tar", "bin"].contains((stem as NSString).pathExtension.lowercased()) {
            set = stem.lowercased() + ".NNN"
            number = Int(ext) ?? 0
            first = stem + ".001"
        } else if lowerExt.range(of: #"^[rz]\d\d$"#, options: .regularExpression) != nil {
            // name.r00 follows name.rar, name.z01 comes with name.zip
            let head = lowerExt.hasPrefix("r") ? "rar" : "zip"
            set = stem.lowercased() + "." + head
            number = (Int(ext.dropFirst()) ?? 0) + 1
            first = stem + "." + head
        } else if lowerExt == "rar" || lowerExt == "zip" {
            set = stem.lowercased() + "." + lowerExt
            number = 0
            first = path
        } else {
            return nil
        }
    }
}
