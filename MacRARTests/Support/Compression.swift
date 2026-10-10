import XCTest
@testable import MacRAR

extension XCTestCase {
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
