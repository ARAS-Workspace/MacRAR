import Foundation

/// The code pages Windows writes ZIP names in when it does not write UTF-8: the OEM one for the names FAT, NTFS and Unix
/// hosts made (857 on Turkish Windows), the ANSI one for the others (1254). Windows takes both from its region; macOS has
/// no such pages, so the app reads such names as Windows does in the user's region. The table holds the regions whose
/// Windows languages share their pages, as Windows' locale data gives them (.NET's IcuLocaleData); any other region, or
/// none, reads them as Windows in the United States does.
struct WindowsCodePages: Equatable {
    let oem: UInt32
    let ansi: UInt32

    static let unitedStates = WindowsCodePages(oem: 437, ansi: 1252)

    init(oem: UInt32, ansi: UInt32) {
        self.oem = oem
        self.ansi = ansi
    }

    /// As Windows reads them in `locale`'s region; the language plays no part.
    init(_ locale: Locale) {
        self = locale.region.flatMap { Self.byRegion[$0.identifier] } ?? Self.unitedStates
    }

    private static let byRegion: [String: WindowsCodePages] = {
        let groups: [(WindowsCodePages, [String])] = [
            (WindowsCodePages(oem: 857, ansi: 1254), ["TR"]),
            (WindowsCodePages(oem: 850, ansi: 1252), [
                "AD", "AT", "BE", "CH", "DE", "DK", "ES", "FI", "FR", "GB", "IE",
                "IS", "IT", "LI", "LU", "MC", "NL", "NO", "PT", "SE", "SM",
            ]),
            (WindowsCodePages(oem: 852, ansi: 1250), ["CZ", "HR", "HU", "PL", "RO", "SI", "SK"]),
            (WindowsCodePages(oem: 866, ansi: 1251), ["BG", "BY", "RU", "UA"]),
            (WindowsCodePages(oem: 737, ansi: 1253), ["GR"]),
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { pages, regions in regions.map { ($0, pages) } })
    }()
}
