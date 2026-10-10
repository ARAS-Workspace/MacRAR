import XCTest
@testable import MacRAR

/// A scratch directory per test with the sources every archive test packs:
/// a text file, and a folder holding a binary file and a file with a Turkish name.
final class Workspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacRARTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src/sub"), withIntermediateDirectories: true)
        try Data("hello archive\n".utf8).write(to: url("src/a.txt"))
        try Self.noise(count: 1 << 20).write(to: url("src/sub/b.bin"))
        try Data("utf-8 name\n".utf8).write(to: url("src/sub/çalışma ğüş.txt"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    func path(_ relative: String) -> String { url(relative).path }

    /// The sources as MacRAR passes them: absolute paths of the selected items.
    var sources: [String] { [path("src/a.txt"), path("src/sub")] }

    func makeDirectory(_ relative: String) throws -> String {
        try FileManager.default.createDirectory(at: url(relative), withIntermediateDirectories: true)
        return path(relative)
    }

    func contents(_ relative: String) -> Data? { FileManager.default.contents(atPath: path(relative)) }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(relative)) }

    /// Creates folders under their composed (NFC) names, as shell tools, git and archives made elsewhere name them.
    /// Foundation's own file calls write names decomposed, and Process passes them on decomposed.
    @discardableResult
    func makeComposedDirectory(_ relative: String) throws -> String {
        var folder = root.path
        for component in relative.precomposedStringWithCanonicalMapping.split(separator: "/") {
            folder += "/\(component)"
            guard mkdir(folder, 0o755) == 0 || errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return folder
    }

    /// Writes a file under its composed (NFC) name, in folders named the same way.
    func writeComposed(_ data: Data, to relative: String) throws {
        var components = relative.precomposedStringWithCanonicalMapping.split(separator: "/").map(String.init)
        let name = components.removeLast()
        let folder = try makeComposedDirectory(components.joined(separator: "/"))
        let descriptor = open("\(folder)/\(name)", O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == data.count else { throw POSIXError(.EIO) }
    }

    /// The files at the top level whose names start with `prefix`, with their contents: a volume set to compare.
    func files(startingWith prefix: String) throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(prefix) }
        return Dictionary(uniqueKeysWithValues: names.map { ($0, contents($0) ?? Data()) })
    }

    private static func noise(count: Int) -> Data {
        var state: UInt32 = 2_654_435_761
        return Data((0..<count).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 13)
        })
    }
}

extension XCTestCase {
    /// Runs a 7-Zip operation to completion the way the app does, through SevenZipBridge.Job.
    func run(_ operation: SevenZipBridge.Operation, cancelled: Bool = false,
             file: StaticString = #filePath, line: UInt = #line) -> SevenZipBridge.Outcome {
        let job = SevenZipBridge.Job()
        if cancelled { job.cancel() }
        let done = expectation(description: "operation finished")
        var result: SevenZipBridge.Outcome?
        job.start(operation) { outcome in
            result = outcome
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        guard let result else {
            XCTFail("operation did not finish", file: file, line: line)
            return SevenZipBridge.Outcome(code: .failed, error: "", messages: [])
        }
        return result
    }

    func update(_ archive: String, _ sources: [String], _ options: SevenZipBridge.UpdateOptions,
                file: StaticString = #filePath, line: UInt = #line) {
        let outcome = run(.update(archive: archive, sources: sources, options: options), file: file, line: line)
        XCTAssertEqual(outcome.code, .ok, "update \(archive): \(outcome.error)", file: file, line: line)
    }
}
