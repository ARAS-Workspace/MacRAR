import AppKit

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
        switch ProcessInfo.processInfo.environment["MACRAR_DEBUG_PLACEMENT"] {
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

extension AppDelegate {
    /// A downloaded copy, run before it was moved to the Applications folder, says once no other question is up why
    /// it has no Quick Actions, unless the user asked not to be told again.
    func warnAboutPlacementWhenIdle() {
        guard QuickActions.placement == .downloaded,
              !UserDefaults.standard.bool(forKey: QuickActions.placementWarningOffKey) else { return }
        Dialogs.whenIdle {
            let alert = NSAlert()
            alert.messageText = loc.t("quick_actions_need_applications_title", AppInfo.name)
            alert.informativeText = loc.t("quick_actions_need_applications_message", AppInfo.name, AppInfo.name)
            alert.addButton(withTitle: loc.t("ok"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = loc.t("dont_show_again")
            _ = Dialogs.ask(alert)
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: QuickActions.placementWarningOffKey)
            }
        }
    }

    /// The Quick Actions installed from the menu, into `directory`: only by the copy in the Applications folder. Any
    /// other copy says why instead of pointing the user's Quick Actions at itself.
    func installQuickActions(in directory: String = QuickActions.servicesDir, registerWithFinder: Bool = true) {
        guard QuickActions.ownedByThisCopy else {
            Dialogs.info(loc.t("quick_actions_need_applications_title", AppInfo.name),
                         loc.t("quick_actions_need_applications_message", AppInfo.name, AppInfo.name))
            return
        }
        let count = QuickActions.installAll(in: directory, registerWithFinder: registerWithFinder)
        Dialogs.info(loc.t("quick_actions_installed_title"), loc.t("quick_actions_installed_message", count))
    }
}
