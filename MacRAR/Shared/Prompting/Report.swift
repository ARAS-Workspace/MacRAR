import Foundation

/// An error, with the tool's full output to copy when there is one, or a word of information.
struct Report: Equatable {
    enum Kind: Equatable { case error, info }
    var kind: Kind
    var title = ""
    var detail: String
    var details: String?
}
