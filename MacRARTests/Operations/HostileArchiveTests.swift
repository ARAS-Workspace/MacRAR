import XCTest
@testable import MacRAR

/// Archives made to write outside the folder they are extracted into, as the archive attacks of 2025 did (7-Zip's
/// symbolic links in ZIP files, CVE-2025-11001/11002; WinRAR's paths, CVE-2025-8088), extracted the way the app
/// extracts: nothing lands outside the destination and no file outside changes, whether the archive names a path that
/// climbs out, an absolute path, or a link to follow. 7-Zip (26.04) does the refusing; these tests hold it to that.
/// A name that climbs out is written inside; following a link out fails the extraction, which the user is told of.
final class HostileArchiveTests: XCTestCase {
    private var workspace: Workspace!
    private var root = ""
    /// A file outside every destination that the archives aim at
    private var victim = ""

    override func setUpWithError() throws {
        workspace = try Workspace()
        root = workspace.root.resolvingSymlinksInPath().path
        victim = root + "/victim.txt"
        try Data("original".utf8).write(to: URL(fileURLWithPath: victim))
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        workspace = nil
    }

    private struct Outcome {
        /// Whether the extraction reported success
        let succeeded: Bool
        /// What it wrote outside the destination, by name in the workspace
        let outside: [String]
        /// What it wrote inside the destination, by path, a link with its target
        let inside: [String]
        /// What it printed for the user
        let told: String
    }

    /// Extracts the archive `data` as `name` into a folder of its own, as the app does.
    private func extract(_ data: Data, as name: String) throws -> Outcome {
        let archive = root + "/" + name
        try data.write(to: URL(fileURLWithPath: archive))
        let destination = root + "/out-" + name
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: root))
        guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { throw XCTSkip("\(name) did not list") }
        var succeeded = false
        let told = printed {
            succeeded = finished { Ops.extract(.init(info: info, names: nil, dest: destination), password: nil, host: nil, completion: $0) }
        }
        let outside = Set(try FileManager.default.contentsOfDirectory(atPath: root)).subtracting(before).sorted()
        let inside = (FileManager.default.subpaths(atPath: destination) ?? []).sorted().map { path in
            (try? FileManager.default.destinationOfSymbolicLink(atPath: destination + "/" + path)).map { "\(path) -> \($0)" } ?? path
        }
        return Outcome(succeeded: succeeded, outside: outside, inside: inside, told: told)
    }

    private var victimText: String { (try? String(contentsOfFile: victim, encoding: .utf8)) ?? "missing" }

    /// A name that climbs out of the destination never leaves it: 7-Zip writes it inside, without the climb.
    func testANameThatClimbsOutStaysInside() throws {
        for (name, data) in [("zip", HostileArchive.zip([.file("../escaped.txt")])),
                             ("tar", HostileArchive.tar([.file("../escaped.txt")]))] {
            // Past the question the app asks first (the next test)
            var outcome: Outcome?
            try withEnvironment(["MACRAR_DEBUG_OVERWRITE": "overwrite"]) { outcome = try extract(data, as: "climb.\(name)") }
            XCTAssertEqual(outcome?.outside, [], name)
            XCTAssertEqual(outcome?.inside, ["escaped.txt"], name)
        }
    }

    /// An archive whose name climbs out is extracted without a question: the app took ".." for an item already in the
    /// destination, always there, and asked whether to replace it; cancelled, the extraction ended without a word.
    /// A name such as "./a.txt" is asked about by the item it writes, "a.txt".
    func testANameThatClimbsOutAsksNothing() throws {
        let outcome = try extract(HostileArchive.zip([.file("../escaped.txt")]), as: "question.zip")
        XCTAssertTrue(outcome.succeeded, "the overwrite question for \"..\" was asked and cancelled")
        XCTAssertEqual(outcome.inside, ["escaped.txt"])
        XCTAssertTrue(try extract(HostileArchive.zip([.file("./fresh.txt")]), as: "dot.zip").succeeded, "asked about \".\"")
        // The item it writes is there already: asked about, and cancelled
        try FileManager.default.createDirectory(atPath: root + "/out-there.zip", withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: URL(fileURLWithPath: root + "/out-there.zip/a.txt"))
        XCTAssertFalse(try extract(HostileArchive.zip([.file("./a.txt", "new")]), as: "there.zip").succeeded, "not asked about a.txt")
        XCTAssertEqual(try String(contentsOfFile: root + "/out-there.zip/a.txt", encoding: .utf8), "kept")
        XCTAssertEqual(["../a/b", "./a", "/a/b", "a", "..", "./"].map(ArchiveInfo.topName(of:)), ["a", "a", "a", "a", nil, nil])
        let info = ArchiveInfo(path: "/x.zip", kind: .other, details: "ZIP", entries: [])
        XCTAssertEqual(Ops.topLevelNames(info: info, names: ["../a/b", "./c", "a/d", ".."]), ["a", "c"], "the selection's tops")
    }

    /// An absolute name, or one that climbs back out from inside, lands inside the destination.
    func testAnAbsoluteNameLandsInside() throws {
        let absolute = root + "/absolute.txt"
        for (name, data) in [("zip", HostileArchive.zip([.file(absolute)])), ("tar", HostileArchive.tar([.file(absolute)]))] {
            let outcome = try extract(data, as: "absolute.\(name)")
            XCTAssertEqual(outcome.outside, [], name)
            XCTAssertEqual(outcome.inside.last, String(absolute.dropFirst()), name)
        }
        let inner = try extract(HostileArchive.zip([.file("dir/../../up.txt")]), as: "inner.zip")
        XCTAssertEqual(inner.outside, [])
        XCTAssertEqual(inner.inside, ["dir", "dir/up.txt"])
    }

    /// Nothing is written through a link the archive made, whether it points up or to an absolute folder outside (7-Zip
    /// makes the links after the files), and no link it leaves points outside the destination.
    func testNothingIsWrittenThroughALink() throws {
        let cases = [
            ("up.zip", HostileArchive.zip([.symlink("link", to: ".."), .file("link/through.txt")])),
            ("absolute.zip", HostileArchive.zip([.symlink("link", to: root), .file("link/through.txt")])),
            ("up.tar", HostileArchive.tar([.symlink("link", to: ".."), .file("link/through.txt")])),
        ]
        for (name, data) in cases {
            let outcome = try extract(data, as: name)
            XCTAssertEqual(outcome.outside, [], name)
            XCTAssertFalse(outcome.inside.contains { $0.hasSuffix("through.txt") }, "\(name): \(outcome.inside)")
            let destination = root + "/out-" + name
            for path in FileManager.default.subpaths(atPath: destination) ?? [] {
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: destination + "/" + path) else { continue }
                let folder = ((destination + "/" + path) as NSString).deletingLastPathComponent
                let resolved = ((target.hasPrefix("/") ? target : folder + "/" + target) as NSString).standardizingPath
                XCTAssertTrue(resolved.hasPrefix(destination + "/"), "\(name): \(path) points outside, to \(target)")
            }
            XCTAssertFalse(outcome.succeeded, "\(name): the refusal went unreported")
        }
    }

    /// A link to a file outside, followed by an item of the same name, never changes that file: the item is written
    /// as a file of its own.
    func testALinkToAFileOutsideNeverChangesIt() throws {
        let cases = [
            ("symlink.zip", HostileArchive.zip([.symlink("s", to: victim), .file("s", "pwned")])),
            ("symlink.tar", HostileArchive.tar([.symlink("s", to: victim), .file("s", "pwned")])),
            ("hardlink.tar", HostileArchive.tar([.hardLink("s", to: victim), .file("s", "pwned")])),
        ]
        for (name, data) in cases {
            let outcome = try extract(data, as: name)
            XCTAssertEqual(victimText, "original", "\(name) changed the file outside")
            XCTAssertEqual(outcome.outside, [], name)
            let written = root + "/out-" + name + "/s"
            let attributes = try FileManager.default.attributesOfItem(atPath: written)
            XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular, name)
            XCTAssertEqual(attributes[.referenceCount] as? Int, 1, "\(name): a hard link to the file outside")
        }
    }
}
