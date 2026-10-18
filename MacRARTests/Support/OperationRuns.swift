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
    func withEnvironment(_ variables: [DebugVariable: String], _ body: () throws -> Void) rethrows {
        let earlier = variables.keys.map { ($0.rawValue, getenv($0.rawValue).map { String(cString: $0) }) }
        for (variable, value) in variables { setenv(variable.rawValue, value, 1) }
        defer {
            for (name, value) in earlier {
                if let value { setenv(name, value, 1) } else { unsetenv(name) }
            }
        }
        try body()
    }

    /// Runs `body` with these variables removed from the test host, then puts back what they were.
    func withoutEnvironment(_ variables: [DebugVariable], _ body: () throws -> Void) rethrows {
        let earlier = variables.map { ($0.rawValue, getenv($0.rawValue).map { String(cString: $0) }) }
        for variable in variables { unsetenv(variable.rawValue) }
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
    private static let debugAnswers: [DebugVariable: String] = [
        .confirm: "1", .password: "__cancel__", .passwordRetry: "__cancel__", .overwrite: "cancel",
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

    /// What stands behind the debug answers while they are set: an unseen screen instead of the alerts and panels, so
    /// that a question no variable answers fails the test instead of coming up.
    private static var screen: UnseenScreen?

    func setDebugAnswers() {
        for (variable, value) in Self.debugAnswers { setenv(variable.rawValue, value, 1) }
        let screen = UnseenScreen()
        Self.screen = screen
        Dialogs.prompter = DebugPrompter(base: screen)
    }

    func clearDebugAnswers() {
        for variable in Self.debugAnswers.keys { unsetenv(variable.rawValue) }
        XCTAssertEqual(Self.screen?.reached ?? [], [], "a question no debug variable answers came up")
        Self.screen = nil
        Dialogs.prompter = Dialogs.defaultPrompter
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

extension Dictionary where Key == DebugVariable, Value == String {
    /// The variables under their names, as an environment holds them.
    var byName: [String: String] { [String: String](uniqueKeysWithValues: map { ($0.key.rawValue, $0.value) }) }
}
