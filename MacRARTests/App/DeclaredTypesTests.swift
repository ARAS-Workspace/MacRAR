import XCTest
@testable import MacRAR

/// The types the app declares to LaunchServices, which decide the files Finder offers the app, its Quick Actions and
/// its associations for.
final class DeclaredTypesTests: XCTestCase {
    private func declarations() throws -> [[String: Any]] {
        try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations") as? [[String: Any]])
    }

    private func declaration(_ identifier: String) throws -> [String: Any] {
        try XCTUnwrap(try declarations().first { $0["UTTypeIdentifier"] as? String == identifier }, "\(identifier) is not declared")
    }

    private func extensions(_ declaration: [String: Any]) -> Set<String> {
        let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
        return Set(tags?["public.filename-extension"] as? [String] ?? [])
    }

    /// Upstream 1.4.3 (533ce7e): the pieces of an old-style RAR set run from x.r00 to x.r99, and the declaration stopped
    /// at x.r03. They are a type of the app's own, which LaunchServices always takes from this app: declared under
    /// com.rarlab.rar-archive they did nothing wherever another app's declaration of that type won, as BetterZip's does
    /// on the Mac this was measured on, naming only rar and rev. The type is a RAR archive, so RAR's document type and
    /// the Quick Actions take its files.
    func testOldStyleRarVolumesAreATypeOfTheAppsOwn() throws {
        let volumes = try declaration("com.arasworkspace.MacRAR.rar-volume")
        XCTAssertEqual(extensions(volumes), Set((0...99).map { String(format: "r%02d", $0) }))
        let conforms = Set(volumes["UTTypeConformsTo"] as? [String] ?? [])
        XCTAssertTrue(conforms.isSuperset(of: ["com.rarlab.rar-archive", "public.archive"]), "\(conforms)")
        XCTAssertEqual(extensions(try declaration("com.rarlab.rar-archive")), ["rar"])
        let documents = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let rar = try XCTUnwrap(documents.first { $0["CFBundleTypeName"] as? String == "RAR Archive" })
        XCTAssertEqual(rar["LSItemContentTypes"] as? [String], ["com.rarlab.rar-archive", "com.arasworkspace.MacRAR.rar-volume"])
        XCTAssertTrue(QuickActions.archiveTypes.contains("com.arasworkspace.MacRAR.rar-volume"))
    }

    /// No extension is named by two of the app's declarations, which would leave LaunchServices to pick one.
    func testNoExtensionIsDeclaredTwice() throws {
        let named = try declarations().flatMap { Array(extensions($0)) }
        XCTAssertEqual(named.count, Set(named).count, "\(Dictionary(grouping: named) { $0 }.filter { $0.value.count > 1 }.keys)")
    }

    /// The app's own type, for the formats the system has none for, is a declaration of its own that the Archive
    /// document type and the Quick Actions name. The original's sat inside the RAR declaration until 1.4.3 and was
    /// never registered; this distribution declared it on its own from the start.
    func testTheAppsArchiveTypeIsDeclaredOnItsOwn() throws {
        for item in try declarations() {
            XCTAssertNotNil(item["UTTypeConformsTo"] as? [String], "\(item["UTTypeIdentifier"] ?? "?") nests something")
        }
        let own = extensions(try declaration("com.arasworkspace.MacRAR.archive"))
        XCTAssertTrue(own.isSuperset(of: ["7z", "cab", "arj", "lzh", "zst", "001"]), "\(own)")
        let documents = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let contentTypes = Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        XCTAssertTrue(contentTypes.isSuperset(of: ["com.rarlab.rar-archive", "com.arasworkspace.MacRAR.archive"]), "\(contentTypes)")
        XCTAssertTrue(QuickActions.archiveTypes.contains("com.arasworkspace.MacRAR.archive"))
        XCTAssertTrue(QuickActions.archiveTypes.contains("com.rarlab.rar-archive"))
    }

    /// Finder names the kinds the app declares in the user's language, from InfoPlist.strings, which the build writes
    /// from the kind_* texts of each language's translations so that the Turkish stays in tr.json. Upstream 1.4.3
    /// (533ce7e) named the kinds in English with Turkish InfoPlist.strings written by hand.
    func testTheArchiveKindsAreNamedInBothLanguages() throws {
        let documents = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        let names = documents.compactMap { $0["CFBundleTypeName"] as? String }
            + (try declarations()).compactMap { $0["UTTypeDescription"] as? String }
        XCTAssertEqual(Set(names), ["RAR Archive", "RAR Volume", "Archive"])
        for language in ["en", "tr"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "json", subdirectory: "translations"))
            let text = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language),
                "no \(language).lproj/InfoPlist.strings")
            let kinds = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], path)
            let expected = ["RAR Archive": text["kind_rar_archive"], "RAR Volume": text["kind_rar_volume"], "Archive": text["kind_archive"]]
            XCTAssertEqual(kinds, expected, language)
        }
    }
}
