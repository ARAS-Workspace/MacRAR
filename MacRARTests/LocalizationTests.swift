import XCTest
@testable import MacRAR

/// en.json and tr.json stay in step with each other and with every key the sources ask for.
final class LocalizationTests: XCTestCase {
    private func table(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "json", subdirectory: "translations"),
                                "\(language).json is not in the app bundle")
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private func specifiers(_ text: String) throws -> [String] {
        let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcCsSp%]"#)
        let range = NSRange(text.startIndex..., in: text)
        return specifier.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
    }

    func testBothLanguagesHaveTheSameKeys() throws {
        let english = try table("en"), turkish = try table("tr")
        XCTAssertEqual(Set(english.keys).subtracting(turkish.keys), [], "missing in tr.json")
        XCTAssertEqual(Set(turkish.keys).subtracting(english.keys), [], "missing in en.json")
    }

    func testFormatSpecifiersMatch() throws {
        let english = try table("en"), turkish = try table("tr")
        for (key, text) in english {
            XCTAssertEqual(try specifiers(text), try specifiers(turkish[key] ?? ""), key)
        }
    }

    func testEveryKeyInTheSourcesExists() throws {
        let english = try table("en")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sources = repository.appendingPathComponent("MacRAR")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let call = try NSRegularExpression(pattern: #"loc\.t\("([a-z0-9_]+)""#)
        var used = Set<String>()
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert((text as NSString).substring(with: match.range(at: 1)))
            }
        }
        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(used.subtracting(english.keys), [], "keys used in the sources but missing from en.json")
    }
}
