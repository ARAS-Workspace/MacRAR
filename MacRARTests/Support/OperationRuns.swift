import XCTest
@testable import MacRAR

extension XCTestCase {
    /// An operation such as Ops.extract or Ops.add run to its completion; whether it worked.
    func finished(_ operation: (@escaping (Bool, String?) -> Void) -> Void) -> Bool {
        let done = expectation(description: "operation finished")
        var succeeded = false
        operation { ok, _ in
            succeeded = ok
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        return succeeded
    }

    /// Runs `body` with these variables set in the test host, then puts back what they were.
    func withEnvironment(_ variables: [String: String], _ body: () throws -> Void) rethrows {
        let earlier = variables.keys.map { ($0, getenv($0).map { String(cString: $0) }) }
        for (name, value) in variables { setenv(name, value, 1) }
        defer {
            for (name, value) in earlier {
                if let value { setenv(name, value, 1) } else { unsetenv(name) }
            }
        }
        try body()
    }

    /// Runs `body` with these variables removed from the test host, then puts back what they were.
    func withoutEnvironment(_ names: [String], _ body: () throws -> Void) rethrows {
        let earlier = names.map { ($0, getenv($0).map { String(cString: $0) }) }
        for name in names { unsetenv(name) }
        defer {
            for (name, value) in earlier {
                if let value { setenv(name, value, 1) } else { unsetenv(name) }
            }
        }
        try body()
    }

    /// The answers a test that drives the operations starts from, so the app never waits at a real alert: an error
    /// prints instead (MACRAR_DEBUG_CONFIRM), and a password or overwrite question the test does not answer itself is
    /// cancelled, which fails the test where it would have kept a dialog open.
    private static let debugAnswers = [
        "MACRAR_DEBUG_CONFIRM": "1", "MACRAR_DEBUG_PASSWORD": "__cancel__", "MACRAR_DEBUG_PASSWORD_RETRY": "__cancel__",
        "MACRAR_DEBUG_OVERWRITE": "cancel",
    ]

    /// What `body` prints, such as an alert MACRAR_DEBUG_CONFIRM sends to the standard output instead of the screen.
    /// The output goes to a file of its own meanwhile, then back where it went.
    func printed(_ body: () throws -> Void) rethrows -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MacRARTests-printed-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        fflush(stdout)
        let earlier = dup(STDOUT_FILENO)
        let descriptor = Darwin.open(file.path, O_WRONLY)
        dup2(descriptor, STDOUT_FILENO)
        close(descriptor)
        defer {
            fflush(stdout)
            dup2(earlier, STDOUT_FILENO)
            close(earlier)
        }
        try body()
        fflush(stdout)
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    func setDebugAnswers() {
        for (name, value) in Self.debugAnswers { setenv(name, value, 1) }
    }

    func clearDebugAnswers() {
        for name in Self.debugAnswers.keys { unsetenv(name) }
    }

    /// Runs Ops.compress to its completion and returns what it reports: whether it worked and the archive file the
    /// callers reveal in Finder and open.
    func compress(_ items: [String], _ options: CompressOptions) -> (ok: Bool, path: String) {
        let done = expectation(description: "compressed")
        var reported = (ok: false, path: "")
        Ops.compress(items: items, options: options, host: nil) { ok, path in
            reported = (ok, path)
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        return reported
    }

    /// The name a gzip stream keeps for what it packs (FNAME, RFC 1952).
    func gzipName(_ path: String) throws -> String? {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let head = try XCTUnwrap(try handle.read(upToCount: 1024))
        // ID1 ID2 CM FLG MTIME(4) XFL OS, then FNAME when FLG has it and no FEXTRA comes first
        guard head.count > 10, head[0] == 0x1f, head[1] == 0x8b, head[3] & 0x08 != 0, head[3] & 0x04 == 0 else { return nil }
        return String(bytes: head[10...].prefix { $0 != 0 }, encoding: .utf8)
    }
}
