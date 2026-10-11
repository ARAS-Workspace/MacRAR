import Foundation

extension Data {
    /// The bytes as UTF-8 text, a byte that is not UTF-8 read as U+FFFD. rar's output is read this way: the pipe hands
    /// it over in pieces cut anywhere, so what has arrived of a line can end halfway through a letter such as ş, and
    /// the failable String(bytes:encoding:) the lint rule prefers would drop the whole line rather than that letter.
    var lossyUTF8: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: self, as: UTF8.self)
    }
}

extension NSRegularExpression {
    /// A pattern written in the source: one that does not compile is a mistake in the code, not something to recover
    /// from.
    convenience init(literal pattern: String) {
        do {
            try self.init(pattern: pattern)
        } catch {
            preconditionFailure("\(pattern): \(error)")
        }
    }
}
