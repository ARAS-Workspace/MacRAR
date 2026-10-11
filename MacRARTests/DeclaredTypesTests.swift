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

    /// Upstream 1.4.3 (533ce7e): the pieces of an old-style RAR set run from x.r00 to x.r99, and the declaration
    /// stopped at x.r03, so on a Mac where no other app declares the rest Finder took x.r04 … for unknown files.
    func testEveryOldStyleRarVolumeIsDeclared() throws {
        let declared = extensions(try declaration("com.rarlab.rar-archive"))
        XCTAssertTrue(declared.contains("rar"))
        let volumes = Set((0...99).map { String(format: "r%02d", $0) })
        XCTAssertEqual(volumes.subtracting(declared), [], "not declared")
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
        XCTAssertEqual(Set(names), ["RAR Archive", "Archive"])
        for language in ["en", "tr"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "json", subdirectory: "translations"))
            let text = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language),
                "no \(language).lproj/InfoPlist.strings")
            let kinds = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], path)
            XCTAssertEqual(kinds, ["RAR Archive": text["kind_rar_archive"], "Archive": text["kind_archive"]], language)
        }
    }
}
