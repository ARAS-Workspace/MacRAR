import AppKit

/// The menu bar's menus: the app, File, Edit, View, Window and Help.
extension MenuSpec {
    init(loc: LocalizationManager, appName: String = AppInfo.name) {
        menus = [
            Self.appMenu(loc, appName), Self.fileMenu(loc), Self.editMenu(loc), Self.viewMenu(loc), Self.windowMenu(loc),
            Self.helpMenu(loc, appName),
        ]
    }

    /// About, updates, Settings, associations and Quick Actions, then hiding and quitting.
    private static func appMenu(_ loc: LocalizationManager, _ appName: String) -> Menu {
        Menu(title: "", role: nil, items: [
            command(.showAbout, loc.t("menu_about", appName)),
            command(.checkForUpdates, loc.t("menu_check_for_updates")),
            .separator,
            command(.showSettings, loc.t("menu_settings"), Shortcut(",")),
            .separator,
            command(.showAssociations, loc.t("action_file_associations")),
            command(.installQuickActions, loc.t("menu_install_quick_actions")),
            .separator,
            standard(#selector(NSApplication.hide(_:)), loc.t("menu_hide_app", appName), Shortcut("h")),
            standard(
                #selector(NSApplication.hideOtherApplications(_:)), loc.t("menu_hide_others"), Shortcut("h", [.command, .option])),
            standard(#selector(NSApplication.unhideAllApplications(_:)), loc.t("menu_show_all")),
            .separator,
            standard(#selector(NSApplication.terminate(_:)), loc.t("menu_quit_app", appName), Shortcut("q")),
        ])
    }

    /// Opening, creating, extracting, testing and changing archives.
    private static func fileMenu(_ loc: LocalizationManager) -> Menu {
        Menu(title: loc.t("menu_file"), role: nil, items: [
            command(.openArchive, loc.t("action_open_archive"), Shortcut("o")),
            command(.newArchive, loc.t("action_new_archive"), Shortcut("n")),
            .submenu(.openRecent, title: loc.t("menu_open_recent")),
            .separator,
            command(.extractHere, loc.t("action_extract_here"), Shortcut("e")),
            command(.extractToFolder, loc.t("action_extract_to_folder"), Shortcut("e", [.command, .option])),
            command(.extractTo, loc.t("action_extract_to"), Shortcut("e", [.command, .shift])),
            command(.extractSelectedHere, loc.t("action_extract_selected_here")),
            command(.extractSelectedTo, loc.t("action_extract_selected_to")),
            .separator,
            command(.testArchive, loc.t("action_test_archive"), Shortcut("t")),
            command(.showInfo, loc.t("action_archive_info"), Shortcut("i")),
            .separator,
            command(.addFiles, loc.t("action_add_files"), Shortcut("a", [.command, .shift])),
            command(.deleteSelected, loc.t("action_delete_selected"), Shortcut("\u{8}")),
            .separator,
            standard(#selector(NSWindow.performClose(_:)), loc.t("menu_close"), Shortcut("w")),
        ])
    }

    /// The standard editing commands, for the search field and the dialogs' text fields.
    private static func editMenu(_ loc: LocalizationManager) -> Menu {
        Menu(title: loc.t("menu_edit"), role: nil, items: [
            standard(Selector(("undo:")), loc.t("menu_undo"), Shortcut("z")),
            standard(Selector(("redo:")), loc.t("menu_redo"), Shortcut("z", [.command, .shift])),
            .separator,
            standard(#selector(NSText.cut(_:)), loc.t("menu_cut"), Shortcut("x")),
            standard(#selector(NSText.copy(_:)), loc.t("menu_copy"), Shortcut("c")),
            standard(#selector(NSText.paste(_:)), loc.t("menu_paste"), Shortcut("v")),
            standard(#selector(NSText.selectAll(_:)), loc.t("menu_select_all"), Shortcut("a")),
        ])
    }

    /// Quick Look, expanding and collapsing the tree, refreshing, and showing the archive in Finder.
    private static func viewMenu(_ loc: LocalizationManager) -> Menu {
        Menu(title: loc.t("menu_view"), role: nil, items: [
            command(.quickLook, loc.t("action_quick_look"), Shortcut(" ", [])),
            .separator,
            command(.expandAll, loc.t("action_expand_all"),
                    Shortcut(String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option])),
            command(.collapseAll, loc.t("action_collapse_all"),
                    Shortcut(String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option])),
            .separator,
            command(.refresh, loc.t("action_refresh"), Shortcut("r")),
            command(.revealArchive, loc.t("action_show_in_finder"), Shortcut("r", [.command, .shift])),
        ])
    }

    /// The Window menu, which AppKit fills with the open windows.
    private static func windowMenu(_ loc: LocalizationManager) -> Menu {
        Menu(title: loc.t("menu_window"), role: .windows, items: [
            standard(#selector(NSWindow.performMiniaturize(_:)), loc.t("menu_minimize"), Shortcut("m")),
            standard(#selector(NSWindow.performZoom(_:)), loc.t("menu_zoom")),
            .separator,
            standard(#selector(NSApplication.arrangeInFront(_:)), loc.t("menu_bring_all_to_front")),
        ])
    }

    /// The README in the app's language and the changelog (Help.swift).
    private static func helpMenu(_ loc: LocalizationManager, _ appName: String) -> Menu {
        Menu(title: loc.t("menu_help"), role: .help, items: [
            command(.openHelp, loc.t("menu_help_app", appName), Shortcut("?")),
            command(.openReleaseNotes, loc.t("menu_release_notes")),
        ])
    }
}
