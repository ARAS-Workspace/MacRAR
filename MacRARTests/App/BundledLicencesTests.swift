import XCTest

/// The licences every copy of the app carries in its resources: the MIT notice of the app's own code, the third-party
/// notices, 7-Zip's licence and the GNU LGPL 2.1 it refers to.
final class BundledLicencesTests: XCTestCase {
    /// Each resource and the repository file it is copied from.
    private let licences = [
        "LICENSE": "LICENSE",
        "THIRD_PARTY_LICENSES": "THIRD_PARTY_LICENSES",
        "7zip-license.txt": "Libraries/SevenZipKit/LICENSE",
        "lgpl-2.1.txt": "Libraries/SevenZipKit/copying.txt",
    ]

    private func bundled(_ name: String) throws -> Data {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        return try Data(contentsOf: resources.appendingPathComponent(name))
    }

    /// The build step copies the files byte for byte, under their names in the resources.
    func testTheAppCarriesItsLicencesByteForByte() throws {
        for (resource, source) in licences {
            let original = try Data(contentsOf: Repository.root.appendingPathComponent(source))
            XCTAssertEqual(try bundled(resource), original, "\(resource) differs from \(source)")
        }
    }

    /// MIT asks for the original copyright notice in every copy: Mesut Çevik's line stays as he wrote it, with the
    /// precomposed Ç of the original LICENSE, whatever else changes in the file.
    func testTheBundledLicenceKeepsTheOriginalCopyrightLine() throws {
        let line = Data("\nCopyright (c) 2026 Mesut \u{C7}evik (github.com/mstcvk)\n".utf8)
        XCTAssertNotNil(try bundled("LICENSE").range(of: line))
    }

    /// The text 7-Zip's licence refers to is the LGPL itself, version 2.1, and not another text under its name.
    func testTheLgplTextIsVersion2Point1() throws {
        let head = try XCTUnwrap(String(bytes: try bundled("lgpl-2.1.txt").prefix(200), encoding: .ascii))
        XCTAssertTrue(head.contains("GNU LESSER GENERAL PUBLIC LICENSE"), head)
        XCTAssertTrue(head.contains("Version 2.1, February 1999"), head)
    }

    /// The third-party notices say the 7-Zip library is a modified build and where its source is, as the LGPL asks
    /// of an app that ships it.
    func testTheThirdPartyNoticesDescribeTheModifiedLibrary() throws {
        let notices = try XCTUnwrap(String(data: try bundled("THIRD_PARTY_LICENSES"), encoding: .utf8))
        let source = try String(contentsOf: Repository.root.appendingPathComponent("Libraries/SevenZipKit/SOURCE"), encoding: .utf8)
        let release = try XCTUnwrap(source.split(separator: "\n").first { $0.hasPrefix("Release:") }?.split(separator: " ").last)
        XCTAssertTrue(notices.contains("The library is a modified build"), notices)
        XCTAssertTrue(notices.contains(String(release)), "THIRD_PARTY_LICENSES names another release than SOURCE: \(release)")
    }
}
