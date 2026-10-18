import XCTest
@testable import MacRAR

/// The tree an archive window shows, built from the names the archive lists.
final class ArchiveTreeTests: XCTestCase {
    private func entry(_ name: String) -> ArchiveEntry { ArchiveEntry(name: name, isDirectory: false) }

    /// A name starting with "/", which tar archives can hold and 7-Zip lists as it is, sits where 7-Zip extracts it,
    /// at the top, and keeps its own name for the operations: building the tree looked for the folder "/" above
    /// "/", without end, and the window never opened.
    func testANameStartingWithASlashSitsAtTheTop() {
        let root = Node.buildTree([entry("/abs.txt"), entry("/dir/b.txt"), entry("abs.txt")])
        XCTAssertEqual(root.children.map(\.name), ["dir", "abs.txt", "abs.txt"])
        XCTAssertEqual(Set(root.children.map(\.path)), ["/dir", "/abs.txt", "abs.txt"])
        XCTAssertEqual(root.children.first?.children.map(\.path), ["/dir/b.txt"])
    }

    /// An extracted item is where 7-Zip writes it, which opening it, Quick Look and a drag read: its name without
    /// empty, "." and ".." parts, always inside the folder it was extracted into.
    func testAnExtractedItemIsWhereSevenZipWritesIt() {
        let cases = ["dir/../../x.txt": "/t/dir/x.txt", "./a.txt": "/t/a.txt", "/abs.txt": "/t/abs.txt", "a//b": "/t/a/b",
                     "plain/name.txt": "/t/plain/name.txt", ".": "/t"]
        for (name, expected) in cases {
            XCTAssertEqual(ArchiveWindowController.extracted(Node(name: "", path: name, isDir: false), in: "/t"), expected, name)
        }
    }
}
