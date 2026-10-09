import XCTest
@testable import MacRAR

final class SevenZipBridgeTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
    }

    override func tearDown() {
        workspace = nil
    }

    func testVersionCarriesTheForkSuffix() {
        XCTAssertTrue(SevenZipBridge.version.contains("+MacRAR.Patch."), SevenZipBridge.version)
    }

    func testSevenZipRoundTrip() throws {
        let archive = workspace.path("plain.7z")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "7z", level: 5, solid: 1))

        let listing = try SevenZipBridge.list(archive, password: nil).get()
        XCTAssertEqual(listing.type, "7z")
        XCTAssertTrue(listing.solid)
        XCTAssertFalse(listing.headersEncrypted)
        XCTAssertEqual(Set(listing.items.map(\.path)), ["a.txt", "sub", "sub/b.bin", "sub/çalışma ğüş.txt"])

        let destination = try workspace.makeDirectory("out")
        let extract = run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: nil))
        XCTAssertEqual(extract.code, .ok, extract.error)
        XCTAssertEqual(workspace.contents("out/sub/b.bin"), workspace.contents("src/sub/b.bin"))
        XCTAssertEqual(workspace.contents("out/sub/çalışma ğüş.txt"), workspace.contents("src/sub/çalışma ğüş.txt"))

        XCTAssertEqual(run(.test(archive: archive, password: nil)).code, .ok)
    }

    func testSelectedItemsOnly() throws {
        let archive = workspace.path("plain.7z")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "7z"))
        let destination = try workspace.makeDirectory("selected")
        let outcome = run(.extract(archive: archive, destination: destination, items: ["sub"], overwrite: .overwrite, password: nil))
        XCTAssertEqual(outcome.code, .ok, outcome.error)
        XCTAssertTrue(workspace.exists("selected/sub/b.bin"))
        XCTAssertFalse(workspace.exists("selected/a.txt"))
    }

    func testOverwritePolicies() throws {
        let archive = workspace.path("plain.7z")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "7z"))
        let destination = try workspace.makeDirectory("out")
        try Data("changed".utf8).write(to: workspace.url("out/a.txt"))

        func extract(_ overwrite: SevenZipBridge.Overwrite) -> SevenZipBridge.Code {
            run(.extract(archive: archive, destination: destination, items: ["a.txt"], overwrite: overwrite, password: nil)).code
        }

        XCTAssertEqual(extract(.skip), .ok)
        XCTAssertEqual(workspace.contents("out/a.txt"), Data("changed".utf8))

        XCTAssertEqual(extract(.rename), .ok)
        XCTAssertTrue(workspace.exists("out/a_1.txt"))

        XCTAssertEqual(extract(.overwrite), .ok)
        XCTAssertEqual(workspace.contents("out/a.txt"), workspace.contents("src/a.txt"))
    }

    func testEncryptedHeadersNeedTheRightPassword() throws {
        let archive = workspace.path("secret.7z")
        var options = SevenZipBridge.UpdateOptions(format: "7z", password: "sır-parola")
        options.encryptHeaders = true
        update(archive, workspace.sources, options)

        if case .failure(let failure) = SevenZipBridge.list(archive, password: nil) {
            XCTAssertEqual(failure.code, .passwordRequired)
        } else {
            XCTFail("listing without a password succeeded")
        }
        if case .failure(let failure) = SevenZipBridge.list(archive, password: "wrong") {
            XCTAssertEqual(failure.code, .wrongPassword)
        } else {
            XCTFail("listing with a wrong password succeeded")
        }
        let listing = try SevenZipBridge.list(archive, password: "sır-parola").get()
        XCTAssertTrue(listing.headersEncrypted)

        let destination = try workspace.makeDirectory("out")
        let wrong = run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: "wrong"))
        XCTAssertEqual(wrong.code, .wrongPassword)
        let right = run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: "sır-parola"))
        XCTAssertEqual(right.code, .ok, right.error)
        XCTAssertEqual(workspace.contents("out/sub/b.bin"), workspace.contents("src/sub/b.bin"))
    }

    func testZipAESKeepsNamesReadable() throws {
        let archive = workspace.path("secret.zip")
        var options = SevenZipBridge.UpdateOptions(format: "zip", password: "zip-pass")
        options.zipAES256 = true
        update(archive, workspace.sources, options)

        let listing = try SevenZipBridge.list(archive, password: nil).get()
        let files = listing.items.filter { !$0.isDirectory }
        XCTAssertEqual(files.count, 3)
        XCTAssertTrue(files.allSatisfy(\.encrypted))
        XCTAssertTrue(files.allSatisfy { $0.method.contains("AES") })

        let destination = try workspace.makeDirectory("out")
        XCTAssertEqual(
            run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: nil)).code,
            .passwordRequired)
        XCTAssertEqual(
            run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: "zip-pass")).code, .ok)
    }

    func testCompressedTarIsReadAsTheTarInside() throws {
        let tar = workspace.path("pack.tar")
        update(tar, workspace.sources, SevenZipBridge.UpdateOptions(format: "tar"))
        let archive = workspace.path("pack.tar.gz")
        update(archive, [tar], SevenZipBridge.UpdateOptions(format: "gzip"))

        let listing = try SevenZipBridge.list(archive, password: nil).get()
        XCTAssertEqual(listing.type, "tar")
        XCTAssertEqual(listing.container, "gzip")
        XCTAssertEqual(listing.items.count, 4)

        let destination = try workspace.makeDirectory("out")
        let outcome = run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: nil))
        XCTAssertEqual(outcome.code, .ok, outcome.error)
        XCTAssertEqual(workspace.contents("out/sub/b.bin"), workspace.contents("src/sub/b.bin"))
    }

    func testSplitVolumes() throws {
        var options = SevenZipBridge.UpdateOptions(format: "7z", level: 0)
        options.volumeSize = 300_000
        update(workspace.path("vol.7z"), workspace.sources, options)
        XCTAssertTrue(workspace.exists("vol.7z.004"))

        let listing = try SevenZipBridge.list(workspace.path("vol.7z.001"), password: nil).get()
        XCTAssertGreaterThanOrEqual(listing.volumes, 4)
    }

    func testDeleteThenAdd() throws {
        let archive = workspace.path("plain.7z")
        let options = SevenZipBridge.UpdateOptions(format: "7z")
        update(archive, workspace.sources, options)

        let delete = run(.delete(archive: archive, items: ["a.txt"], password: nil, encryptHeaders: false))
        XCTAssertEqual(delete.code, .ok, delete.error)
        XCTAssertEqual(try SevenZipBridge.list(archive, password: nil).get().items.count, 3)

        update(archive, [workspace.path("src/a.txt")], options)
        XCTAssertEqual(try SevenZipBridge.list(archive, password: nil).get().items.count, 4)
    }

    func testNotAnArchive() {
        if case .failure(let failure) = SevenZipBridge.list(workspace.path("src/a.txt"), password: nil) {
            XCTAssertEqual(failure.code, .notArchive)
        } else {
            XCTFail("a text file listed as an archive")
        }
    }

    func testCancelStopsTheOperation() throws {
        let archive = workspace.path("plain.7z")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "7z"))
        let destination = try workspace.makeDirectory("out")
        let outcome = run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: nil),
                          cancelled: true)
        XCTAssertEqual(outcome.code, .cancelled)
    }

    func testProgressAndItemsReachTheMainQueue() throws {
        let job = SevenZipBridge.Job()
        var fractions: [Double] = []
        var items: [String] = []
        job.onProgress = { fraction in
            XCTAssertTrue(Thread.isMainThread)
            fractions.append(fraction)
        }
        job.onItem = { items.append($0) }
        let done = expectation(description: "finished")
        job.start(.update(archive: workspace.path("p.7z"), sources: workspace.sources, options: .init(format: "7z"))) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        XCTAssertFalse(fractions.isEmpty)
        XCTAssertEqual(fractions, fractions.sorted())
        XCTAssertTrue(items.contains { $0.hasSuffix("b.bin") }, "\(items)")
    }
}
