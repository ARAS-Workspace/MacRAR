import XCTest
@testable import MacRAR

/// rar's output read the way RarJob reads it, from what rar 7.23 wrote while adding large files: "Adding <file>" and its
/// percentages share a line that backspaces rewrite and only OK ends, and the pipe may cut it anywhere.
final class RarOutputTests: XCTestCase {
    private let first = "/x/large-1.bin"
    private let second = "/x/büyük dosya 3.bin"

    /// One string per write rar made.
    private var writes: [String] {
        [
            "\nRAR 7.23   Copyright (c) 1993-2026 Alexander Roshal   27 Jun 2026\nTrial version             Type 'rar -?' for help"
                + "\n\nEvaluation copy. Please register.\n\nCreating archive /x/large.rar\n",
            "\nAdding    \(first)     \u{8}\u{8}\u{8}\u{8}  0%",
            "\u{8}\u{8}\u{8}\u{8}  1%",
            "\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nAdding    \(second)     \u{8}\u{8}\u{8}\u{8} 18%",
            "\u{8}\u{8}\u{8}\u{8} 19%",
            "\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nDone\n",
        ]
    }

    private func read(_ chunks: [Data]) -> (events: [RarJob.Event], log: String) {
        var output = RarOutput()
        let events = chunks.flatMap { output.read($0) }
        output.finish()
        return (events, output.log)
    }

    private func names(_ events: [RarJob.Event]) -> [String] {
        events.compactMap { if case .file(let name) = $0 { return name } else { return nil } }
    }

    /// The name and the first percentage often arrive together, which left the progress window on "Preparing…" for the
    /// whole run: only the last piece of a line was read, a percentage or OK.
    func testEachFileIsNamedHoweverTheOutputIsCut() {
        let expected: [RarJob.Event] = [.file(first), .progress(0), .progress(1), .file(second), .progress(18), .progress(19)]
        XCTAssertEqual(read(writes.map { Data($0.utf8) }).events, expected, "write by write")

        let bytes = Data(writes.joined().utf8)
        XCTAssertEqual(read(bytes.map { Data([$0]) }).events, expected, "byte by byte, cutting the Turkish letters too")

        let atOnce = read([bytes]).events
        XCTAssertEqual(names(atOnce), [first, second], "all at once")
        XCTAssertEqual(atOnce.last, .progress(19))
    }

    /// Once a file is packed rar sweeps its share again from where the file began; the bar stays where it was. The
    /// recovery record that follows is named and counts from 0 on its own.
    func testPercentageNeverGoesBackOnTheSameFile() {
        let chunks = [
            "\nAdding    \(first)     \u{8}\u{8}\u{8}\u{8} 10%", "\u{8}\u{8}\u{8}\u{8} 50%",
            "\u{8}\u{8}\u{8}\u{8}  6%", "\u{8}\u{8}\u{8}\u{8} 31%", "\u{8}\u{8}\u{8}\u{8} 50%",
            "\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nAdding the data recovery record     \u{8}\u{8}\u{8}\u{8}  0%",
            "\u{8}\u{8}\u{8}\u{8} 50%",
            "\u{8}\u{8}\u{8}\u{8}100%\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nDone\n",
        ]
        XCTAssertEqual(read(chunks.map { Data($0.utf8) }).events, [
            .file(first), .progress(10), .progress(50),
            .file("the data recovery record"), .progress(0), .progress(50), .progress(100),
        ])
    }

    /// The output a failed run reports: every line as it finally read, without the percentages it went through, and a
    /// last line rar left without a newline.
    func testLogKeepsWhatTheLinesFinallySay() {
        let log = read((writes + ["ERROR: Write error in the file /x/large.rar"]).map { Data($0.utf8) }).log
        XCTAssertFalse(log.contains("%"), log)
        XCTAssertFalse(log.contains("\u{8}"), log)
        for line in ["Creating archive /x/large.rar", "Adding    \(second)", "Done", "ERROR: Write error in the file /x/large.rar"] {
            XCTAssertTrue(log.contains(line), line)
        }
    }

    /// A file that goes on in the next volume is named again without its folder after "Creating archive
    /// <name>.part2.rar"; it is still the same file, and its percentage goes on.
    func testAFileGoingOnInTheNextVolumeStaysTheSameFile() {
        let padding = String(repeating: " ", count: 52)
        let chunks = [
            "\nCreating archive /x/v.part1.rar\n\nAdding    /x/src/parça ğ.bin     \u{8}\u{8}\u{8}\u{8} 14%",
            "\u{8}\u{8}\u{8}\u{8} 43%",
            "\u{8}\u{8}\u{8}\u{8}    \n\nCreating archive /x/v.part2.rar\n\n...       parça ğ.bin\(padding)\u{8}\u{8}\u{8}\u{8} 58%",
            "\u{8}\u{8}\u{8}\u{8}    \n\nCreating archive /x/v.part3.rar\n\n...       parça ğ.bin\(padding)\u{8}\u{8}\u{8}\u{8} 99%",
            "\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nAdding    /x/src/a.txt     \u{8}\u{8}\u{8}\u{8}100%\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nDone\n",
        ]
        XCTAssertEqual(read(chunks.map { Data($0.utf8) }).events, [
            .file("/x/src/parça ğ.bin"), .progress(14), .progress(43), .progress(58), .progress(99),
            .file("/x/src/a.txt"), .progress(100),
        ])
    }

    /// rar d names each item it deletes on a line of its own; the archive it deletes from is not an item.
    func testDeletedItemsAreNamed() {
        let output = "\nDeleting from /x/a.rar\nDeleting a.txt\nDeleting sub/çalışma ğüş.txt\nDone\n"
        XCTAssertEqual(read([Data(output.utf8)]).events, [.file("a.txt"), .file("sub/çalışma ğüş.txt")])
    }

    /// A name may end the way rar's status does; only a line that ends with its status unrewritten, as older rar
    /// versions print it, loses that status.
    func testANameEndingLikeAStatusIsKept() {
        let rewritten = "\nAdding    /x/rapor 100%     \u{8}\u{8}\u{8}\u{8}  5%\u{8}\u{8}\u{8}\u{8}\u{8}  OK \n"
        XCTAssertEqual(names(read([Data(rewritten.utf8)]).events), ["/x/rapor 100%"])
        let older = "\nAdding    /x/rapor 100%     OK \n"
        XCTAssertEqual(names(read([Data(older.utf8)]).events), ["/x/rapor"], "the older form cannot tell them apart")
    }

    /// A long run rewrites the percentage tens of thousands of times on one line; the line is cut down as it grows but
    /// keeps the name it started with, for the progress and for the log.
    func testALongLineKeepsItsName() {
        var bytes = Data("\nAdding    /x/long.bin     ".utf8)
        for step in 0..<12_000 { bytes += Data("\u{8}\u{8}\u{8}\u{8}\(String(format: "%3d", step / 300))%".utf8) }
        bytes += Data("\u{8}\u{8}\u{8}\u{8}\u{8}  OK \nDone\n".utf8)
        XCTAssertGreaterThan(bytes.count, 64 * 1024)
        let chunks = stride(from: 0, to: bytes.count, by: 4096).map { bytes.subdata(in: $0..<min($0 + 4096, bytes.count)) }
        let (events, log) = read(chunks)
        XCTAssertEqual(names(events), ["/x/long.bin"])
        XCTAssertEqual(events.last, .progress(39))
        XCTAssertTrue(log.contains("Adding    /x/long.bin"), log)
    }
}
