import AppKit

/// The toolbar's items, as the toolbar saves its configuration.
private enum ToolbarItemID {
    static let open = NSToolbarItem.Identifier("open")
    static let newArchive = NSToolbarItem.Identifier("new")
    static let extractTo = NSToolbarItem.Identifier("extractTo")
    static let extractHere = NSToolbarItem.Identifier("extractHere")
    static let extractFolder = NSToolbarItem.Identifier("extractFolder")
    static let test = NSToolbarItem.Identifier("test")
    static let add = NSToolbarItem.Identifier("add")
    static let delete = NSToolbarItem.Identifier("delete")
    static let info = NSToolbarItem.Identifier("info")
    static let search = NSToolbarItem.Identifier("search")
}

extension ArchiveWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.open, ToolbarItemID.newArchive, .space, ToolbarItemID.extractTo, ToolbarItemID.extractHere,
            ToolbarItemID.extractFolder, .space, ToolbarItemID.test, ToolbarItemID.add, ToolbarItemID.delete, ToolbarItemID.info,
            .flexibleSpace, ToolbarItemID.search,
        ]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
    }
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if id == ToolbarItemID.search {
            let s = NSSearchToolbarItem(itemIdentifier: id)
            localize(s)
            s.searchField.target = self
            s.searchField.action = #selector(searchChanged(_:))
            s.searchField.sendsSearchStringImmediately = true
            s.searchField.sendsWholeSearchString = false
            return s
        }
        let buttons: [NSToolbarItem.Identifier: (symbol: String, action: Selector)] = [
            ToolbarItemID.open: ("folder", #selector(openArchive)),
            ToolbarItemID.newArchive: ("doc.zipper", #selector(newArchive)),
            ToolbarItemID.extractTo: ("square.and.arrow.down", #selector(extractTo)),
            ToolbarItemID.extractHere: ("arrow.down.doc", #selector(extractHere)),
            ToolbarItemID.extractFolder: ("folder.badge.plus", #selector(extractToFolder)),
            ToolbarItemID.test: ("checkmark.shield", #selector(testArchive)),
            ToolbarItemID.add: ("plus.rectangle.on.folder", #selector(addFiles)),
            ToolbarItemID.delete: ("trash", #selector(deleteSelected)),
            ToolbarItemID.info: ("info.circle", #selector(showInfo)),
        ]
        guard let button = buttons[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: button.symbol, accessibilityDescription: nil)
        item.target = self
        item.action = button.action
        item.isBordered = true
        localize(item)
        return item
    }

    /// The label, tooltip and placeholder of a toolbar item in the current language.
    func localize(_ item: NSToolbarItem) {
        if let search = item as? NSSearchToolbarItem {
            search.label = loc.t("search_label")
            search.searchField.placeholderString = loc.t("search_placeholder")
            return
        }
        let texts: [NSToolbarItem.Identifier: (label: String, tip: String)] = [
            ToolbarItemID.open: (loc.t("open"), loc.t("toolbar_open_tooltip")),
            ToolbarItemID.newArchive: (loc.t("toolbar_compress"), loc.t("toolbar_compress_tooltip")),
            ToolbarItemID.extractTo: (loc.t("toolbar_extract"), loc.t("toolbar_extract_tooltip")),
            ToolbarItemID.extractHere: (loc.t("toolbar_extract_here"), loc.t("toolbar_extract_here_tooltip")),
            ToolbarItemID.extractFolder: (loc.t("toolbar_extract_folder"), loc.t("toolbar_extract_folder_tooltip")),
            ToolbarItemID.test: (loc.t("toolbar_test"), loc.t("toolbar_test_tooltip")),
            ToolbarItemID.add: (loc.t("add"), loc.t("toolbar_add_tooltip")),
            ToolbarItemID.delete: (loc.t("delete"), loc.t("toolbar_delete_tooltip")),
            ToolbarItemID.info: (loc.t("toolbar_info"), loc.t("toolbar_info_tooltip")),
        ]
        guard let text = texts[item.itemIdentifier] else { return }
        item.label = text.label
        item.paletteLabel = text.label
        item.toolTip = text.tip
        item.image?.accessibilityDescription = text.label
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { validate(item.action) }
}
