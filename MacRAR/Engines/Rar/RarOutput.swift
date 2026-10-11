import Foundation

/// What rar prints while it works, read into progress events however the bytes arrive. rar rewrites the end of a line
/// with backspaces: "Adding <file>" is followed on the same line by its percentages ("  0%", "  1%"…) and the line ends
/// only with "OK", while the pipe hands over whatever rar has written so far. The text before a line's first backspace
/// names the file and its last piece is the percentage. The percentage never goes back while the same file is named
/// (rar sweeps a packed file's share once more); a new name, such as the recovery record, counts on its own.
struct RarOutput {
    /// The finished lines as they ended up on screen, without the percentages: what a failed run reports
    private(set) var log = ""
    /// The line rar is still writing
    private var line = Data()
    private var file: String?
    private var percent = -1

    private static let verbs = [
        "Extracting", "Adding", "Testing", "Updating", "Creating", "Deleting", "Compressing", "Fresh", "Calculating",
    ]
    private static let percentRegex = NSRegularExpression(literal: #"^(\d{1,3})%( \d+)?$"#)
    private static let tailRegex = NSRegularExpression(literal: #"\s*(\d{1,3}%|OK|Failed|CRC failed)\s*$"#)

    /// The events in `data`, read after everything that came before it.
    mutating func read(_ data: Data) -> [RarJob.Event] {
        line.append(data)
        var events: [RarJob.Event] = []
        while let newline = line.firstIndex(of: 0x0A) {
            let text = Self.text(line[line.startIndex..<newline])
            line.removeSubrange(line.startIndex...newline)
            log += Self.screen(text) + "\n"
            events += parse(text, finished: true)
        }
        guard !line.isEmpty else { return events }
        events += parse(Self.text(line), finished: false)
        // A long run rewrites the percentage many times: keep the start of the line, which names the file, and the latest
        // state
        if line.count > 64 * 1024, let first = line.firstIndex(of: 0x08), let last = line.lastIndex(of: 0x08), first < last {
            line.removeSubrange(line.index(after: first)...last)
        }
        return events
    }

    /// The end of the output: a line rar left without a newline goes to the log as well.
    mutating func finish() {
        guard !line.isEmpty else { return }
        log += Self.screen(Self.text(line))
        line.removeAll()
    }

    private mutating func parse(_ text: String, finished: Bool) -> [RarJob.Event] {
        let pieces = Self.pieces(of: text)
        guard let head = pieces.first else { return [] }
        var events: [RarJob.Event] = []
        let rewritten = text.contains("\u{8}")
        // A name is whole once something follows it: rar pads it with the spaces its percentage writes over
        if finished || rewritten || text.hasSuffix("    "),
           let named = Self.name(in: head, endsWithStatus: finished && !rewritten), !continues(named) {
            file = named.name
            percent = -1
            events.append(.file(named.name))
        }
        // The latest percentage, also when the line has already ended with OK
        if let value = pieces.reversed().lazy.compactMap(Self.percentage).first, value > percent {
            percent = value
            events.append(.progress(value))
        }
        return events
    }

    /// Whether a line names the file already named: the same name, or the file going on in the next volume, which rar
    /// names without its folder
    private func continues(_ named: (name: String, nextVolume: Bool)) -> Bool {
        guard let file else { return false }
        return file == named.name || (named.nextVolume && file.hasSuffix("/" + named.name))
    }

    /// The file a line names before its first backspace: "Adding <file>", or "... <file>" when a file goes on in the
    /// next volume. None for the archive itself ("Creating archive", "Deleting from") or any other line. A line that
    /// ends with its status instead of rewriting it ("Adding <file>  OK", from older rar versions) loses that status;
    /// otherwise a name may well end with "100%" or "OK" itself.
    private static func name(in head: String, endsWithStatus: Bool) -> (name: String, nextVolume: Bool)? {
        let text = head.trimmingCharacters(in: .whitespaces)
        var candidate: String?
        let nextVolume = text.hasPrefix("... ")
        if nextVolume {
            candidate = String(text.dropFirst(4))
        } else if let verb = verbs.first(where: { text.hasPrefix($0 + " ") }) {
            let rest = text.dropFirst(verb.count).trimmingCharacters(in: .whitespaces)
            guard !rest.hasPrefix("from "), !rest.hasPrefix("archive ") else { return nil }
            candidate = rest
        }
        guard var name = candidate else { return nil }
        while endsWithStatus, let match = tailRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            name = (name as NSString).substring(to: match.range.location)
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, nextVolume)
    }

    private static func percentage(in piece: String) -> Int? {
        let text = piece.trimmingCharacters(in: .whitespaces)
        guard let match = percentRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    /// A line cut where rar wrote backspaces, without the empty pieces
    private static func pieces(of text: String) -> [String] {
        text.components(separatedBy: "\u{8}").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// What a line finally shows, without the percentages it went through
    private static func screen(_ text: String) -> String {
        pieces(of: text).filter { percentage(in: $0) == nil }.joined(separator: " ")
    }

    private static func text(_ bytes: Data) -> String { bytes.lossyUTF8 }
}
