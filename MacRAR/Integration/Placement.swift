import Foundation

/// Where this copy of the app runs from, which decides whether it installs the Finder Quick Actions and offers the file
/// associations: only the copy in the Applications folder does. Workflows and associations that point at a copy on a
/// disk image break once it is ejected, and they would take the place of the ones for the copy in Applications.
extension QuickActions {
    enum Placement: Equatable {
        /// /Applications or ~/Applications
        case applications
        /// Where a download sits before it is moved: a disk image, Downloads, the Desktop, or the random folder
        /// Gatekeeper runs a quarantined app from (App Translocation)
        case downloaded
        /// Anywhere else, such as a build folder
        case elsewhere
    }

    static func placement(bundlePath: String, home: String) -> Placement {
        let path = (bundlePath as NSString).standardizingPath
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return .applications }
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
            || path.hasPrefix(home + "/Downloads/") || path.hasPrefix(home + "/Desktop/") {
            return .downloaded
        }
        return .elsewhere
    }

    /// This copy's placement. MACRAR_DEBUG_PLACEMENT=downloaded or elsewhere stands in for a copy run from there; it
    /// cannot make a copy pass for the one in Applications.
    static var placement: Placement {
        switch DebugVariable.placement.value() {
        case "downloaded": return .downloaded
        case "elsewhere": return .elsewhere
        default: return placement(bundlePath: Bundle.main.bundlePath, home: AppInfo.realHome)
        }
    }

    /// Only the copy in the Applications folder installs and renames the Finder Quick Actions and offers the file
    /// associations; a copy elsewhere, such as the test host, leaves the user's ~/Library/Services alone.
    static var ownedByThisCopy: Bool { placement == .applications }

    static let placementWarningOffKey = "QuickActionsPlacementWarningOff"
}
