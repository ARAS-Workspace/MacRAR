import AppKit

extension MenuSpec {
    /// The archive window's context menu: opening and looking at what is selected, extracting it, and deleting it.
    static func archiveContextMenu(loc: LocalizationManager) -> [Item] {
        [
            command(.openSelected, loc.t("open")),
            command(.quickLook, loc.t("action_quick_look")),
            .separator,
            command(.extractSelectedHere, loc.t("action_extract_selected_here")),
            command(.extractSelectedTo, loc.t("action_extract_selected_to")),
            .separator,
            command(.deleteSelected, loc.t("action_delete_from_archive")),
        ]
    }
}
