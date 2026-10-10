import XCTest
@testable import MacRAR

/// How a second copy of the app ended.
struct AppExit {
    let status: Int32
    let output: String
    let seconds: TimeInterval
}

extension XCTestCase {
    /// Runs a second copy of the app with the arguments a Finder Quick Action passes after "--args", and waits for it.
    /// MACRAR_DEBUG_CONFIRM prints the alerts that report a result, and the argument domain keeps the result from being
    /// revealed in Finder; "-Key value" pairs in `arguments` set further defaults for that copy only.
    func launchApp(_ arguments: [String], environment: [String: String] = [:], timeout: TimeInterval = 60,
                   file: StaticString = #filePath, line: UInt = #line) throws -> AppExit {
        let process = Process()
        process.executableURL = try XCTUnwrap(Bundle.main.executableURL)
        process.arguments = ["-RevealAfterExtract", "NO", "-RevealAfterCompress", "NO"] + arguments
        // A fresh environment: the test host's XCTest variables would load the tests into the copy as well
        process.environment = [
            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin",
            "MACRAR_LANG": "en", "MACRAR_NO_UPDATE_CHECK": "1", "MACRAR_DEBUG_CONFIRM": "1",
        ].merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        let started = Date()
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            XCTFail("MacRAR \(arguments.joined(separator: " ")) did not finish", file: file, line: line)
        }
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return AppExit(status: process.terminationStatus, output: output, seconds: Date().timeIntervalSince(started))
    }

    /// A string from en.json, the language the copies run in.
    func english(_ key: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "en", withExtension: "json", subdirectory: "translations"))
        let table = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        return try XCTUnwrap(table[key], key)
    }
}
