import Foundation

struct RarResult {
    let code: Int32
    let output: String
    var cancelled: Bool = false
    var passwordProblem: Bool = false
    var notAnArchive: Bool = false

    var ok: Bool { code == 0 || code == 1 }
    var wrongPassword: Bool {
        passwordProblem || code == 11 || output.contains("Incorrect password") || output.contains("Wrong password")
            || output.contains("Cannot open encrypted archive")
    }
    var notArchive: Bool {
        notAnArchive || output.contains("is not RAR archive") || output.contains("Cannot open the file as archive")
    }

    /// Short error text to show the user
    var errorSummary: String {
        let lines = output.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\u{8}", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter {
                !$0.hasPrefix("UNRAR ") && !$0.hasPrefix("RAR ") && !$0.hasPrefix("Trial version") && !$0.hasPrefix("Evaluation copy")
            }
        let interesting = lines.filter { line in
            line.contains("error") || line.contains("Error") || line.contains("ERROR") || line.contains("Incorrect")
                || line.contains("Wrong")
                || line.contains("failed") || line.contains("Failed") || line.contains("not RAR") || line.contains("Cannot")
                || line.contains("Can not")
                || line.contains("No files") || line.contains("Checksum") || line.contains("CRC") || line.contains("denied")
                || line.contains("Total errors")
                || line.contains("Unexpected end") || line.contains("Data Error") || line.contains("Unsupported")
        }
        let chosen = interesting.isEmpty ? Array(lines.suffix(6)) : Array(interesting.suffix(8))
        return chosen.joined(separator: "\n")
    }
}

extension RarResult {
    /// The 7-Zip library's outcome in the shape the operations already handle.
    init(_ outcome: SevenZipBridge.Outcome) {
        var lines = outcome.messages
        if !outcome.error.isEmpty, !lines.contains(where: { $0.contains(outcome.error) }) {
            lines.append("ERROR: " + outcome.error)
        }
        let code: Int32
        switch outcome.code {
        case .ok: code = 0
        case .warning: code = 1
        default: code = 2
        }
        self.init(code: code, output: lines.joined(separator: "\n"),
                  cancelled: outcome.code == .cancelled,
                  passwordProblem: outcome.code.isPasswordProblem,
                  notAnArchive: outcome.code == .notArchive)
    }
}
