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
    /// MACRAR_DEBUG_CONFIRM prints the alerts that report a result, MACRAR_DEBUG_UNSEEN keeps the copy's windows
    /// unseen, and the argument domain keeps the result from being revealed in Finder; "-Key value" pairs in
    /// `arguments` set further defaults for that copy only. The copy is started with posix_spawn rather than Process,
    /// which hands arguments and the environment over decomposed (NFD): what reaches the copy is byte for byte what the
    /// test gives, such as a password typed with letters like ü or ş.
    func launchApp(_ arguments: [String], environment: [DebugVariable: String] = [:], timeout: TimeInterval = 60,
                   file: StaticString = #filePath, line: UInt = #line) throws -> AppExit {
        let executable = try XCTUnwrap(Bundle.main.executablePath)
        let argv = [executable, "-RevealAfterExtract", "NO", "-RevealAfterCompress", "NO"] + arguments
        // A fresh environment: the test host's XCTest variables would load the tests into the copy as well
        let debug: [DebugVariable: String] = [
            .language: "en", .noUpdateCheck: "1", .confirm: "1", .unseen: "1",
            // Questions the test leaves unanswered are cancelled rather than shown in the copy. With .format,
            // .password is the password the archive is made with instead, so it is left to the test.
            .passwordRetry: "__cancel__", .overwrite: "cancel",
        ]
        let variables = ["HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin"]
            .merging(debug.merging(environment[.format] == nil ? [.password: "__cancel__"] : [:]) { $1 }.byName) { $1 }
            .merging(environment.byName) { $1 }.map { "\($0.key)=\($0.value)" }

        let started = Date()
        let (pid, output) = try spawn(argv, variables)
        // Read while the copy runs, so it never waits on a full pipe
        let collected = Collected()
        let reader = FileHandle(fileDescriptor: output, closeOnDealloc: true)
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            collected.data = reader.readDataToEndOfFile()
            read.signal()
        }
        var status: Int32 = 0
        while waitpid(pid, &status, WNOHANG) == 0 {
            if Date().timeIntervalSince(started) > timeout {
                kill(pid, SIGTERM)
                waitpid(pid, &status, 0)
                XCTFail("MacRAR \(arguments.joined(separator: " ")) did not finish", file: file, line: line)
                break
            }
            usleep(20_000)
        }
        read.wait()
        // WIFEXITED and WEXITSTATUS: the exit code of a copy that exited, -1 for one a signal ended
        let exitCode = status & 0x7f == 0 ? (status >> 8) & 0xff : -1
        return AppExit(status: exitCode, output: String(bytes: collected.data, encoding: .utf8) ?? "",
                       seconds: Date().timeIntervalSince(started))
    }

    /// Starts `argv` with exactly these variables, reading /dev/null and writing its output and errors into the pipe
    /// returned.
    private func spawn(_ argv: [String], _ variables: [String]) throws -> (pid: pid_t, output: Int32) {
        var output: [Int32] = [0, 0]
        guard pipe(&output) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output[1], 1)
        posix_spawn_file_actions_adddup2(&actions, output[1], 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Only the descriptors set above reach the copy
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        let cArguments = argv.map { strdup($0) } + [nil]
        let cVariables = variables.map { strdup($0) } + [nil]
        defer { (cArguments + cVariables).forEach { free($0) } }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, argv[0], &actions, &attributes, cArguments, cVariables)
        close(output[1])
        guard spawned == 0 else {
            close(output[0])
            throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EIO)
        }
        return (pid, output[0])
    }

    /// A string from en.json, the language the copies run in.
    func english(_ key: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "en", withExtension: "json", subdirectory: "translations"))
        let table = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        return try XCTUnwrap(table[key], key)
    }
}

/// What a copy wrote, filled in on the queue that reads it.
private final class Collected: @unchecked Sendable {
    var data = Data()
}
