import XCTest
@testable import MacRAR

/// RARLAB's rar for the RAR tests, fetched by External/fetch-rar.sh into External/<archive name>/rar/rar: on CI by
/// the workflow before the tests, on a Mac by running the script once. External/.gitignore keeps the download out of
/// git. Without it the RAR tests skip.
struct RarTool {
    let url: URL

    /// External/ in the repository this file belongs to (MacRARTests/Support/RarTool.swift).
    static let external = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("External")

    static func locate() throws -> RarTool {
        let fetched = (try? FileManager.default.contentsOfDirectory(atPath: external.path)) ?? []
        let tools = fetched.filter { $0.hasPrefix("rarmacos-") }.sorted()
            .map { external.appendingPathComponent("\($0)/rar/rar") }
            .filter { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let url = tools.last else { throw XCTSkip("RARLAB's rar is not fetched; run External/fetch-rar.sh") }
        return RarTool(url: url)
    }

    /// Runs rar the way RarRunner does (UTF-8 locale, no input) and returns its exit code and output.
    func run(_ arguments: [String], in directory: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ProcessInfo.processInfo.environment.merging(["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: output, encoding: .utf8) ?? "")
    }
}
