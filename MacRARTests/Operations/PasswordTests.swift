import XCTest
@testable import MacRAR

/// Passwords through the app's own flows, for 7-Zip (7z, ZIP) and RAR (RARLAB's rar), locking the files only or their
/// names too. Every kind of password a person may type, from plain ASCII to Turkish letters, spaces at either end, a
/// leading "-" or "@", quotes and a backslash, an emoji and 200 characters, locks the archive with the bytes typed: it
/// lists, extracts and tests with them in the app and in rar, takes additions and deletions under that one password,
/// never shows in rar's arguments or the process list, stays apart from other jobs running at once, and an archive
/// locked the earlier way opens with the password as typed. The second copy of the app, as the Quick Actions run it,
/// does the same. Questions get the debug answers (setDebugAnswers), never a real dialog.
final class PasswordTests: XCTestCase {
    private var workspace: Workspace!
    private var rar: RarTool?
    private var savedArguments: [String: Any]?

    override func setUpWithError() throws {
        workspace = try Workspace()
        rar = try? RarTool.locate()
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        savedArguments = arguments
        if let rar { usingRar(at: rar.url.path) }
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        if let savedArguments {
            UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            UserDefaults.standard.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        }
        workspace = nil
    }

    // MARK: What is locked, and with what

    /// A password with Turkish letters, composed, as typing gives it.
    static let turkish = "Şifre İğüöçı"

    /// The passwords, each with what it stands for.
    static let passwords: [(kind: String, value: String)] = [
        ("plain ASCII", "pw"),
        ("one character", "x"),
        ("Turkish letters", turkish),
        ("spaces at both ends", "  boşluk  "),
        ("a leading dash", "-gizli"),
        ("a leading at sign", "@liste"),
        ("quotes and a backslash", #"tırnak "çift" 'tek' \ $HOME"#),
        ("an emoji", "kilit 🔐 açık"),
        ("200 Turkish characters", String(repeating: "ğ1", count: 100)),
        ("200 ASCII characters", String(repeating: "Ab1-", count: 50)),
    ]

    enum Lock: CaseIterable, CustomStringConvertible {
        case rarFiles, rarNames, sevenZipFiles, sevenZipNames, zip

        var format: ArchiveFormat {
            switch self {
            case .rarFiles, .rarNames: return .rar5
            case .sevenZipFiles, .sevenZipNames: return .sevenZip
            case .zip: return .zip
            }
        }
        var namesToo: Bool { self == .rarNames || self == .sevenZipNames }
        var description: String {
            switch self {
            case .rarFiles: return "rar-files"
            case .rarNames: return "rar-names"
            case .sevenZipFiles: return "7z-files"
            case .sevenZipNames: return "7z-names"
            case .zip: return "zip"
            }
        }

        /// Whether the format can lock an archive with the password so that it opens as typed; the app explains why not
        /// before anything is written (Ops.passwordProblem, testPasswordsAFormatCannotTakeAreExplained)
        func takes(_ password: String) -> Bool { Ops.passwordProblem(password, format: format) == nil }
    }

    /// The locks this Mac can make: the RAR ones need RARLAB's rar (External/fetch-rar.sh).
    var locks: [Lock] { Lock.allCases.filter { rar != nil || !$0.format.isRar } }

    let contents = ["a.txt", "sub/b.bin", "sub/çalışma ğüş.txt"]

    // MARK: Every password, every lock

    func testEveryPasswordLocksTheArchiveAsTyped() throws {
        for lock in locks {
            for (index, password) in Self.passwords.enumerated() where lock.takes(password.value) {
                try assertLocksAsTyped(lock, password.value, case: "\(lock)-\(index)", context: "\(lock), \(password.kind)")
            }
        }
    }

    private func assertLocksAsTyped(_ lock: Lock, _ password: String, case name: String, context: String) throws {
        let archive = try make(lock, password, in: name)
        // Locked: no listing without the password when the names are, no file readable without it otherwise
        switch ArchiveReader.list(archive, password: nil) {
        case .wrongPassword:
            XCTAssertTrue(lock.namesToo, context)
        case .ok(let info):
            XCTAssertFalse(lock.namesToo, context)
            XCTAssertTrue(info.entries.filter { !$0.isDirectory }.allSatisfy(\.encrypted), context)
        case .error(let result):
            XCTFail("\(context): \(result.output)")
        }

        let opened = open(archive, typing: password)
        let info = try XCTUnwrap(opened.info, context)
        XCTAssertEqual(scalars(opened.password), lock.namesToo ? scalars(password) : nil, context)
        let extracted = try extract(info, password: password, into: "\(name)-out")
        XCTAssertTrue(extracted.ok, context)
        XCTAssertEqual(scalars(extracted.password), scalars(password), "\(context): the password was changed on the way")
        XCTAssertTrue(sameContents(in: "\(name)-out"), context)
        XCTAssertTrue(finished { Ops.test(info: info, password: password, host: nil, completion: $0) }, context)
        XCTAssertTrue(opensWhole(archive, with: password), context)

        // A wrong one is asked again, and the right one then extracts
        try withEnvironment([.passwordRetry: password]) {
            XCTAssertTrue(try extract(info, password: password + "!", into: "\(name)-again").ok, context)
        }
        XCTAssertTrue(sameContents(in: "\(name)-again"), context)
    }

    // MARK: Adding and deleting

    /// Additions and deletions keep the archive under its one password: a mistyped password is asked again, cancelling
    /// writes nothing, and the archive opens whole afterwards.
    func testAddingAndDeletingKeepOnePassword() throws {
        try workspace.writeComposed(Data("eklenen\n".utf8), to: "more/eklenen ğ.txt")
        try Data("yazım hatası\n".utf8).write(to: workspace.url("more/typo.txt"))
        try Data("vazgeçildi\n".utf8).write(to: workspace.url("more/cancelled.txt"))
        for lock in locks {
            for password in [Self.turkish, "kilit 🔐 açık", "  boşluk  ", "pw"] where lock.takes(password) {
                let context = "\(lock), \(password)"
                let archive = try make(lock, password, in: "edit-\(lock)-\(password.unicodeScalars.count)")
                func listing() throws -> ArchiveInfo { try XCTUnwrap(open(archive, typing: password).info, context) }
                func more(_ name: String) -> [String] { [workspace.path("more/\(name)")] }

                var info = try listing()
                XCTAssertTrue(finished { Ops.add(info: info, items: more("eklenen ğ.txt"), password: password, host: nil, completion: $0) },
                              context)
                let mistyped = password + "!"
                info = try listing()
                withEnvironment([.passwordRetry: password]) {
                    XCTAssertTrue(finished { Ops.add(info: info, items: more("typo.txt"), password: mistyped, host: nil, completion: $0) },
                                  "\(context): a mistyped password")
                }
                info = try listing()
                let cancelled = more("cancelled.txt")
                XCTAssertFalse(finished { Ops.add(info: info, items: cancelled, password: mistyped, host: nil, completion: $0) },
                               "\(context): cancelled")
                info = try listing()
                XCTAssertTrue(finished { Ops.delete(info: info, names: ["a.txt"], password: password, host: nil, completion: $0) }, context)

                let names = Set(try listing().entries.map(\.name))
                XCTAssertTrue(names.isSuperset(of: ["eklenen ğ.txt", "typo.txt", "sub/b.bin"]), "\(context): \(names)")
                XCTAssertTrue(names.isDisjoint(with: ["cancelled.txt", "a.txt"]), "\(context): \(names)")
                XCTAssertTrue(opensWhole(archive, with: password), "\(context): the archive is not under one password")
            }
        }
    }

    // MARK: Archives locked the earlier way

    /// Earlier versions, and the original app, handed rar and 7zz the password on their command line, decomposed. Such an
    /// archive does not open with the bytes typed; it opens with the password as typed all the same, everywhere in the
    /// app, and stays under its own form when it is added to.
    func testArchivesLockedTheEarlierWayOpenWithThePasswordAsTyped() throws {
        let typed = Self.turkish
        let decomposed = typed.decomposedStringWithCanonicalMapping
        for lock in locks where lock != .zip {
            let context = "\(lock)"
            let archive = try makeTheEarlierWay(lock, typed, in: "earlier-\(lock)")
            XCTAssertEqual(run(.test(archive: archive, password: typed)).code, .wrongPassword, "\(context): not locked the earlier way")

            let opened = open(archive, typing: typed)
            let info = try XCTUnwrap(opened.info, context)
            if lock.namesToo { XCTAssertEqual(scalars(opened.password), scalars(decomposed), context) }
            let extracted = try extract(info, password: typed, into: "earlier-\(lock)-out")
            XCTAssertTrue(extracted.ok, context)
            XCTAssertEqual(scalars(extracted.password), scalars(decomposed), context)
            XCTAssertTrue(sameContents(in: "earlier-\(lock)-out"), context)
            XCTAssertTrue(finished { Ops.test(info: info, password: typed, host: nil, completion: $0) }, context)

            let more = [workspace.path("src/a.txt")]
            XCTAssertTrue(finished { Ops.add(info: info, items: more, password: typed, host: nil, completion: $0) }, context)
            let added = try XCTUnwrap(open(archive, typing: typed).info, context)
            XCTAssertTrue(finished { Ops.delete(info: added, names: ["sub/b.bin"], password: typed, host: nil, completion: $0) }, context)
            XCTAssertTrue(opensWhole(archive, with: decomposed), "\(context): the archive is not under its own password")
        }
    }

    // MARK: Out of sight

    /// A stand-in rar records its arguments and its standard input while the app creates, adds to and deletes from
    /// RAR archives: each password arrives on the input byte for byte, and only "-p" or "-hp", without it, among the
    /// arguments.
    func testRarGetsThePasswordByteForByteAndNeverInItsArguments() throws {
        guard rar != nil else { throw XCTSkip("RARLAB's rar is not fetched; run External/fetch-rar.sh") }
        let real = try make(.rarNames, Self.turkish, in: "real")
        let realInfo = try XCTUnwrap(open(real, typing: Self.turkish).info)
        let record = try workspace.makeDirectory("record")
        let standIn = workspace.url("stand-in-rar")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(record)/arguments'
        cat > '\(record)/input'
        printf '\\nDone\\n'
        """.write(to: standIn, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: standIn.path)
        usingRar(at: standIn.path)

        for (index, password) in Self.passwords.enumerated() {
            var options = CompressOptions(archivePath: workspace.path("stand-in-\(index).rar"))
            options.format = .rar5
            options.password = password.value
            options.encryptNames = index.isMultiple(of: 2)
            let runs: [(String, () -> Bool)] = [
                ("create", { self.compress(self.workspace.sources, options).ok }),
                ("add", { self.finished { Ops.add(info: realInfo, items: [self.workspace.path("src/a.txt")], password: password.value,
                                                  host: nil, completion: $0) } }),
                ("delete", { self.finished { Ops.delete(info: realInfo, names: ["a.txt"], password: password.value, host: nil,
                                                        completion: $0) } }),
            ]
            for (operation, run) in runs {
                let context = "\(operation), \(password.kind)"
                XCTAssertTrue(run(), context)
                let input = try XCTUnwrap(FileManager.default.contents(atPath: "\(record)/input"), context)
                XCTAssertEqual(input, Data((password.value + "\n").utf8), "\(context): not the bytes typed")
                let arguments = try String(contentsOfFile: "\(record)/arguments", encoding: .utf8).components(separatedBy: "\n")
                XCTAssertTrue(arguments.contains("-p") || arguments.contains("-hp"), "\(context): \(arguments)")
                XCTAssertFalse(arguments.contains { ($0.hasPrefix("-p") && $0 != "-p") || ($0.hasPrefix("-hp") && $0 != "-hp") },
                               "\(context): \(arguments)")
                if password.value.count > 2 { XCTAssertFalse(arguments.contains { $0.contains(password.value) }, context) }
            }
        }
    }

    /// While rar packs the large files under a password, the process list shows rar with "-hp" and never the password;
    /// the large archives, RAR and 7z with their names locked, come back whole with the password as typed.
    func testLargeArchivesKeepThePasswordOutOfSightAndComeBackWhole() throws {
        let files = try LargeFiles.locate()
        for lock in locks where lock.namesToo {
            var options = CompressOptions(archivePath: workspace.path("large-\(lock).\(lock.format.ext)"))
            options.format = lock.format
            options.password = Self.turkish
            options.encryptNames = true
            var finished = false, packed = false
            var seen: [String] = []
            Ops.compress(items: files, options: options, host: nil) { ok, _ in
                packed = ok
                finished = true
            }
            while !finished {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                if lock.format.isRar, let arguments = runningRarArguments() { seen.append(arguments) }
            }
            XCTAssertTrue(packed, "\(lock)")
            if lock.format.isRar {
                XCTAssertTrue(seen.contains { $0.contains(" -hp ") }, "rar was never seen running: \(seen)")
                XCTAssertFalse(seen.contains { $0.contains("Şifre") || $0.contains("ifre") }, "\(seen)")
            }

            let info = try XCTUnwrap(open(options.archivePath, typing: Self.turkish).info, "\(lock)")
            XCTAssertTrue(try extract(info, password: Self.turkish, into: "large-\(lock)-out").ok, "\(lock)")
            for file in files {
                let name = (file as NSString).lastPathComponent
                XCTAssertEqual(try LargeFiles.digest(workspace.path("large-\(lock)-out/\(name)")), try LargeFiles.digest(file), name)
            }
            try FileManager.default.removeItem(atPath: options.archivePath)
            try FileManager.default.removeItem(atPath: workspace.path("large-\(lock)-out"))
        }
    }

    // MARK: At once

    /// Jobs running at the same time, each with its own password, never take another's: each archive opens with its
    /// own password only, and they all extract at once again.
    func testJobsRunningTogetherKeepTheirOwnPasswords() throws {
        let jobs: [(lock: Lock, password: String)] = zip(locks, ["Şifre bir", "şifre İki", "üç 🔐", "  dört", "five -"]).map { job in
            (job.0, job.0.takes(job.1) ? job.1 : "zip five")
        }
        let archives = jobs.map { workspace.path("together-\($0.lock).\($0.lock.format.ext)") }
        let packed = jobs.map { expectation(description: "\($0.lock) packed") }
        for (index, job) in jobs.enumerated() {
            var options = CompressOptions(archivePath: archives[index])
            options.format = job.lock.format
            options.password = job.password
            options.encryptNames = job.lock.namesToo
            Ops.compress(items: workspace.sources, options: options, host: nil) { ok, _ in
                XCTAssertTrue(ok, "\(job.lock)")
                packed[index].fulfill()
            }
        }
        wait(for: packed, timeout: 120)
        let used = jobs.map(\.password)
        for (index, archive) in archives.enumerated() {
            for (other, password) in used.enumerated() {
                XCTAssertEqual(opensWhole(archive, with: password), index == other, "\(archive) with the password of \(archives[other])")
            }
        }

        let extracted = archives.map { expectation(description: "\($0) extracted") }
        for (index, archive) in archives.enumerated() {
            let info = try XCTUnwrap(open(archive, typing: used[index]).info)
            let destination = try workspace.makeDirectory("together-out-\(index)")
            Ops.extract(.init(info: info, names: nil, dest: destination), password: used[index], host: nil) { ok, _ in
                XCTAssertTrue(ok, archive)
                extracted[index].fulfill()
            }
        }
        wait(for: extracted, timeout: 120)
        for index in archives.indices { XCTAssertTrue(sameContents(in: "together-out-\(index)"), archives[index]) }
    }
}

// MARK: - The Quick Actions, and what is still wrong

extension PasswordTests {
    /// The second copy of the app, as the Quick Actions run it, given the password byte for byte (launchApp): it
    /// creates each kind of archive with it, extracts and tests with the password typed at its question, asks again
    /// after a wrong one, and opens an archive locked the earlier way.
    func testQuickActionsTakeThePasswordAsTyped() throws {
        for lock in locks {
            let password = lock == .zip ? "pass word ~!" : Self.turkish
            let context = "\(lock)"
            let folder = try workspace.makeDirectory("quick-\(lock)")
            let file = "\(folder)/a.txt"
            try FileManager.default.copyItem(atPath: workspace.path("src/a.txt"), toPath: file)
            let tool = lock.format.isRar ? ["-RarPath", try XCTUnwrap(rar).url.path] : []
            var settings: [DebugVariable: String] = [.format: lock.format.ext, .password: password]
            if lock.namesToo { settings[.encryptNames] = "1" }
            let made = try launchApp(tool + ["--compress", file], environment: settings)
            XCTAssertEqual(made.status, 0, "\(context): \(made.output)")
            let archive = "\(folder)/a.\(lock.format.ext)"
            XCTAssertTrue(opensWhole(archive, with: password), context)

            let typedRight: [DebugVariable: String] = [.password: password]
            let typedWrongFirst: [DebugVariable: String] = [.password: password + "!", .passwordRetry: password]
            for answers in [typedRight, typedWrongFirst] {
                try FileManager.default.removeItem(atPath: file)
                let extracted = try launchApp(tool + ["--extract-here", archive], environment: answers)
                XCTAssertEqual(extracted.status, 0, "\(context): \(extracted.output)")
                XCTAssertEqual(FileManager.default.contents(atPath: file), workspace.contents("src/a.txt"), "\(context): \(answers.keys)")
            }
            let tested = try launchApp(tool + ["--test", archive], environment: [.password: password])
            XCTAssertTrue(tested.output.contains(try english("test_passed_title")), "\(context): \(tested.output)")
        }

        for lock in locks where lock != .zip {
            let archive = try makeTheEarlierWay(lock, Self.turkish, in: "quick-earlier-\(lock)")
            let tool = lock.format.isRar ? ["-RarPath", try XCTUnwrap(rar).url.path] : []
            let extracted = try launchApp(tool + ["--extract-folder", archive], environment: [.password: Self.turkish])
            XCTAssertEqual(extracted.status, 0, "\(lock): \(extracted.output)")
            XCTAssertTrue(sameContents(in: "quick-earlier-\(lock)/earlier"), "\(lock)")
        }
    }

    /// Long passwords lock as far as each format takes them. rar uses the first 127 characters of a longer one and
    /// 7-Zip reads a RAR archive the same way, so 1000 characters still open it in both, and emoji past the 127th change
    /// nothing; 7z takes thousands; ZIP with AES takes 99.
    func testLongPasswordsLockAsFarAsTheFormatGoes() throws {
        let long: [(Lock, String)] = [
            (.rarFiles, String(repeating: "Şifre İğüöçı ", count: 80)),
            (.rarNames, String(repeating: "ğ", count: 1000)),
            (.rarFiles, String(repeating: "a", count: 127) + String(repeating: "🔐", count: 100)),
            (.sevenZipFiles, String(repeating: "Şifre 🔐 ", count: 500)),
            (.sevenZipNames, String(repeating: "ş", count: 4000)),
            (.zip, String(String(repeating: "Ab1-", count: 25).dropLast())),
        ]
        for (index, (lock, password)) in long.enumerated() where locks.contains(lock) {
            let context = "\(lock), \(password.unicodeScalars.count) characters"
            let archive = try make(lock, password, in: "long-\(index)")
            XCTAssertTrue(opensWhole(archive, with: password), context)
            let info = try XCTUnwrap(open(archive, typing: password).info, context)
            XCTAssertTrue(try extract(info, password: password, into: "long-\(index)-out").ok, context)
            XCTAssertTrue(sameContents(in: "long-\(index)-out"), context)
        }
    }

    /// A password a format cannot take so that the archive opens as typed is explained before anything is written, in
    /// the app's own words, where 7-Zip stopped with "E_INVALIDARG" or rar locked an archive the app could not open:
    /// ZIP with AES takes 99 characters at most; rar uses the first 127 characters, counted in Unicode scalars, while
    /// 7-Zip counts UTF-16 units, an emoji taking two. A password on either side of each limit goes through the second
    /// copy of the app, as a Quick Action runs it.
    func testPasswordsAFormatCannotTakeAreExplained() throws {
        struct Limit {
            let lock: Lock
            let password: String
            /// The en.json key of the explanation, nil for a password the format takes
            let explained: String?
        }
        let emoji = "🔐"
        var limits = [
            Limit(lock: .zip, password: String(repeating: "a", count: 99), explained: nil),
            Limit(lock: .zip, password: String(repeating: "a", count: 100), explained: "zip_password_too_long"),
            Limit(lock: .zip, password: "şifre", explained: "zip_password_not_ascii"),
        ]
        if rar != nil {
            limits += [
                Limit(lock: .rarFiles, password: String(repeating: emoji, count: 63), explained: nil),
                Limit(lock: .rarFiles, password: String(repeating: emoji, count: 64), explained: "rar_password_emoji_counted_twice"),
                Limit(lock: .rarNames, password: String(repeating: "a", count: 126) + emoji, explained: "rar_password_emoji_counted_twice"),
                Limit(lock: .rarNames, password: String(repeating: "a", count: 127) + emoji, explained: nil),
            ]
        }
        for (index, limit) in limits.enumerated() {
            let (lock, password, explained) = (limit.lock, limit.password, limit.explained)
            let context = "\(lock), \(password.unicodeScalars.count) characters, \(password.utf16.count) UTF-16 units"
            let folder = try workspace.makeDirectory("limits-\(index)")
            let file = "\(folder)/a.txt"
            try FileManager.default.copyItem(atPath: workspace.path("src/a.txt"), toPath: file)
            let archive = "\(folder)/a.\(lock.format.ext)"
            var settings: [DebugVariable: String] = [.format: lock.format.ext, .password: password]
            if lock.namesToo { settings[.encryptNames] = "1" }
            let tool = lock.format.isRar ? ["-RarPath", try XCTUnwrap(rar).url.path] : []
            let made = try launchApp(tool + ["--compress", file], environment: settings)
            XCTAssertEqual(made.status, 0, "\(context): \(made.output)")
            if let explained {
                XCTAssertTrue(made.output.contains("\(try english("compress_failed_title")): \(try english(explained))"),
                              "\(context): \(made.output)")
                XCTAssertFalse(FileManager.default.fileExists(atPath: archive), "\(context): the archive was written")
                XCTAssertFalse(lock.takes(password), context)
            } else {
                XCTAssertTrue(opensWhole(archive, with: password), context)
                XCTAssertTrue(lock.takes(password), context)
            }
        }
    }

    /// A refused password leaves nothing at the destination: the password is found on the smallest encrypted file before
    /// anything is written. 7-Zip used to begin RAR and ZIP items, empty, and the folders of 7z ones, before it found the
    /// password wrong; an archive whose names are locked is refused before anything is written anyway.
    func testARefusedPasswordLeavesNothingBehind() throws {
        for lock in locks where !lock.namesToo {
            let archive = try make(lock, "pw", in: "refused-\(lock)")
            let info = try XCTUnwrap(open(archive, typing: "pw").info)
            XCTAssertFalse(try extract(info, password: "wrong", into: "refused-\(lock)-out").ok, "\(lock)")
            XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: workspace.path("refused-\(lock)-out")), [], "\(lock)")
        }
    }

    /// Answering Overwrite and then giving a wrong password leaves the file that was to be replaced as it was. For RAR and
    /// ZIP, 7-Zip used to empty it before it found the password wrong, and once the question that follows was cancelled
    /// the file was lost.
    func testARefusedPasswordKeepsTheFileItWouldReplace() throws {
        let mine = Data("kendi dosyam\n".utf8)
        for lock in locks where !lock.namesToo {
            let archive = try make(lock, "pw", in: "kept-\(lock)")
            let info = try XCTUnwrap(open(archive, typing: "pw").info)
            let destination = try workspace.makeDirectory("kept-\(lock)-out")
            try mine.write(to: URL(fileURLWithPath: "\(destination)/a.txt"))
            try withEnvironment([.overwrite: "overwrite"]) {
                XCTAssertFalse(try extract(info, password: "wrong", into: "kept-\(lock)-out").ok, "\(lock)")
            }
            XCTAssertEqual(FileManager.default.contents(atPath: "\(destination)/a.txt"), mine, "\(lock)")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination), ["a.txt"], "\(lock)")
        }
    }
}

// MARK: - Helpers

extension PasswordTests {
    /// Points the app at this rar through the RarPath setting in the argument domain (never saved).
    func usingRar(at path: String) {
        let defaults = UserDefaults.standard
        let arguments = savedArguments ?? defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(["RarPath": path]) { $1 }, forName: UserDefaults.argumentDomain)
    }

    /// Ops.compress locks the workspace sources with `password`; the archive's path.
    func make(_ lock: Lock, _ password: String, in folder: String) throws -> String {
        let directory = try workspace.makeDirectory(folder)
        var options = CompressOptions(archivePath: "\(directory)/locked.\(lock.format.ext)")
        options.format = lock.format
        options.level = 1
        options.password = password
        options.encryptNames = lock.namesToo
        let made = compress(workspace.sources, options)
        XCTAssertTrue(made.ok, "\(lock), \(password)")
        return made.path
    }

    /// An archive locked the way earlier versions locked it: the password reached rar and 7zz decomposed. RarTool passes
    /// it through Process, as those versions did; 7-Zip is given the decomposed bytes.
    func makeTheEarlierWay(_ lock: Lock, _ password: String, in folder: String) throws -> String {
        let directory = try workspace.makeDirectory(folder)
        let archive = "\(directory)/earlier.\(lock.format.ext)"
        if lock.format.isRar {
            let switches = RarRunner.addArguments + ["-ma5", (lock.namesToo ? "-hp" : "-p") + password, "--", archive]
            let made = try XCTUnwrap(rar).run(switches + workspace.sources, in: directory)
            XCTAssertEqual(made.status, 0, made.output)
        } else {
            var options = SevenZipBridge.UpdateOptions(format: "7z", password: password.decomposedStringWithCanonicalMapping)
            options.encryptHeaders = lock.namesToo
            update(archive, workspace.sources, options)
        }
        return archive
    }

    /// Ops.listInteractive with `password` typed at its question: the listing and the password it went on with.
    func open(_ archive: String, typing password: String) -> (info: ArchiveInfo?, password: String?) {
        var used: String?
        var info: ArchiveInfo?
        withEnvironment([.password: password]) { info = Ops.listInteractive(archive: archive, password: &used) }
        return (info, used)
    }

    /// Ops.extract into a folder of the workspace: whether it worked and the password it went on with.
    func extract(_ info: ArchiveInfo, password: String?, into folder: String) throws -> (ok: Bool, password: String?) {
        let destination = try workspace.makeDirectory(folder)
        let done = expectation(description: "extracted")
        var outcome: (ok: Bool, password: String?) = (false, nil)
        Ops.extract(.init(info: info, names: nil, dest: destination), password: password, host: nil) { ok, used in
            outcome = (ok, used)
            done.fulfill()
        }
        wait(for: [done], timeout: 300)
        return outcome
    }

    func sameContents(in folder: String) -> Bool {
        contents.allSatisfy { FileManager.default.contents(atPath: workspace.path("\(folder)/\($0)")) == workspace.contents("src/\($0)") }
    }

    /// Whether the archive tests whole with exactly these bytes, in the app's 7-Zip and, for RAR, in rar itself.
    func opensWhole(_ archive: String, with password: String) -> Bool {
        guard run(.test(archive: archive, password: password)).code == .ok else { return false }
        guard archive.hasSuffix(".rar"), rar != nil else { return true }
        let job = RarJob()
        let done = expectation(description: "rar tested")
        var tested = false
        job.start(["t", "-p", "--", archive], password: password) { result in
            tested = result.ok
            done.fulfill()
        }
        withExtendedLifetime(job) { wait(for: [done], timeout: 300) }
        return tested
    }

    /// The command line of a rar the test host is running, as the process list shows it.
    func runningRarArguments() -> String? {
        func output(_ tool: String, _ arguments: [String]) -> String? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return process.terminationStatus == 0 && !text.isEmpty ? text : nil
        }
        guard let pid = output("/usr/bin/pgrep", ["-P", "\(getpid())", "-x", "rar"])?.components(separatedBy: "\n").first else {
            return nil
        }
        return output("/bin/ps", ["-ww", "-o", "args=", "-p", pid])
    }

    func scalars(_ text: String?) -> [Unicode.Scalar]? { text.map { Array($0.unicodeScalars) } }
}
