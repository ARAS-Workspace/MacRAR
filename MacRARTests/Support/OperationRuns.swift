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

    /// Runs `body` with these variables set in the test host, then removes them.
    func withEnvironment(_ variables: [String: String], _ body: () throws -> Void) rethrows {
        for (name, value) in variables { setenv(name, value, 1) }
        defer { for name in variables.keys { unsetenv(name) } }
        try body()
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
}
