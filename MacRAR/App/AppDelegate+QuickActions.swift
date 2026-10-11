import AppKit

/// The Finder Quick Actions as this copy offers them: installed from the menu, or a word on why not (Placement.swift).
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
