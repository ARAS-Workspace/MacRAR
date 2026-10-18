import XCTest
@testable import MacRAR

/// The Windows code pages ZIP names are read with: those Windows gives the user's region (.NET's IcuLocaleData, a
/// language of each region here), whatever the language; Windows' United States pages for a region it gives none of
/// these, and for no region. The app sets them for its own region when it launches.
final class WindowsCodePagesTests: XCTestCase {
    private let expected: [(WindowsCodePages, [String])] = [
        (WindowsCodePages(oem: 857, ansi: 1254), ["tr_TR", "en_TR"]),
        (WindowsCodePages(oem: 850, ansi: 1252), [
            "ca_AD", "de_AT", "fr_BE", "de_CH", "de_DE", "da_DK", "es_ES", "fi_FI", "fr_FR", "en_GB", "ga_IE",
            "is_IS", "it_IT", "de_LI", "lb_LU", "fr_MC", "nl_NL", "nb_NO", "pt_PT", "sv_SE", "it_SM",
        ]),
        (WindowsCodePages(oem: 852, ansi: 1250), ["cs_CZ", "hr_HR", "hu_HU", "pl_PL", "ro_RO", "sl_SI", "sk_SK"]),
        (WindowsCodePages(oem: 866, ansi: 1251), ["bg_BG", "be_BY", "ru_RU", "uk_UA"]),
        (WindowsCodePages(oem: 737, ansi: 1253), ["el_GR"]),
        (WindowsCodePages(oem: 437, ansi: 1252), ["en_US", "tr_US", "ja_JP", "kk_KZ", "en", "tr"]),
    ]

    func testTheRegionDecides() {
        for (pages, locales) in expected {
            for identifier in locales {
                XCTAssertEqual(WindowsCodePages(Locale(identifier: identifier)), pages, identifier)
            }
        }
    }

    func testTheAppSetsThemForItsRegionAtLaunch() {
        XCTAssertEqual(SevenZipBridge.windowsCodePages, WindowsCodePages(.current), "\(Locale.current.identifier)")
    }
}
