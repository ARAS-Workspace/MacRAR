import Foundation

enum RarRunner {
    /// The switch that has rar ask for the password, which RarJob writes to its standard input. Given on the command
    /// line it reached rar decomposed, as Process passes arguments, so a password holding letters such as ü or ş locked
    /// the archive with other bytes than the ones typed, and it showed in the process list. No switch at all when there
    /// is no password: given "-p-", rar takes "-" for the password.
    static func passwordSwitch(_ pw: String?, encryptHeaders: Bool = false) -> [String] {
        guard let pw, !pw.isEmpty else { return [] }
        return [encryptHeaders ? "-hp" : "-p"]
    }

    /// rar's add command for the chosen items: each under its own name (-ep1), without asking (-y). Never -r: with it rar
    /// reads every chosen file name as a mask for the folders below it, so it also added (and with -df deleted)
    /// same-named files nobody chose, and it missed a file whose name holds letters such as ü or ş composed on disk, as
    /// Process hands names over decomposed and rar compares bytes. A chosen folder is added with everything in it all the
    /// same.
    static let addArguments = ["a", "-ep1", "-y"]

    /// Names inside an archive, written for rar to read with "-scfl @list": UTF-8, one a line, byte for byte as the archive
    /// holds them. Given as arguments they reached rar decomposed, as Process passes them, so a name stored with letters
    /// such as ü or ş composed matched nothing. The list's argument, and the folder to remove once rar is done.
    static func nameList(_ names: [String]) throws -> (argument: String, folder: String) {
        let folder = TempDirs.make("rar-names")
        let list = (folder as NSString).appendingPathComponent("names.txt")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try Data(names.map { $0 + "\n" }.joined().utf8).write(to: URL(fileURLWithPath: list))
        return ("@" + list, folder)
    }

    static func makeProcess(_ args: [String], cwd: String?) -> Process {
        let process = Process()
        process.executableURL = RarTools.rarURL ?? URL(fileURLWithPath: "/nonexistent/rar")
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.standardInput = FileHandle.nullDevice
        return process
    }
}
