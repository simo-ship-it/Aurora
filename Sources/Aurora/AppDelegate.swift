import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var formattingKeyMonitor: Any?
    private var workspaceUndoKeyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Le preferenze costruiscono il tema: vanno lette prima che esista una
        // finestra, altrimenti la prima si aprirebbe con le misure predefinite
        // e cambierebbe aspetto sotto gli occhi.
        Settings.shared.apply()
        _ = NSDocumentController.shared          // registra l'architettura dei documenti
        NSApp.mainMenu = MainMenu.build()

        // Gli equivalenti di menu per + e - cambiano con il layout di tastiera.
        // Il monitor locale intercetta i due tasti prima del menu: ⌘+/⌘-
        // percorrono i livelli del titolo, mentre ⇧⌘+/⇧⌘- cambiano il corpo.
        formattingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard relevantModifiers == [.command]
                    || relevantModifiers == [.command, .shift] else { return event }

            let characters = [event.characters ?? "", event.charactersIgnoringModifiers ?? ""]
            let isPlus = event.keyCode == 24 || characters.contains("+") || characters.contains("=")
            let isMinus = event.keyCode == 27 || characters.contains("-") || characters.contains("_")
            guard isPlus || isMinus else { return event }

            if relevantModifiers == [.command, .shift] {
                Settings.shared.adjustFontSize(by: isPlus ? 1 : -1)
                return nil
            }

            let action = isPlus
                ? #selector(MarkdownTextView.promoteHeading(_:))
                : #selector(MarkdownTextView.demoteHeading(_:))
            return NSApp.sendAction(action, to: nil, from: nil) ? nil : event
        }

        // Le operazioni sulla cartella non appartengono a un documento e il
        // popover può chiudersi subito dopo averle eseguite. Intercettare qui
        // ⌘Z mantiene quindi l'annullamento disponibile anche dopo il popup.
        workspaceUndoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard modifiers == [.command],
                  event.charactersIgnoringModifiers?.lowercased() == "z",
                  WorkspaceFileOperations.shared.canUndo else { return event }
            return WorkspaceFileOperations.shared.undoLastOperation() ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let formattingKeyMonitor {
            NSEvent.removeMonitor(formattingKeyMonitor)
        }
        if let workspaceUndoKeyMonitor {
            NSEvent.removeMonitor(workspaceUndoKeyMonitor)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        // Un file aperto da Finder o ripristinato da AppKit ha precedenza
        // sull'ultimo documento memorizzato.
        guard NSDocumentController.shared.documents.isEmpty else { return }
        guard let lastDocument = Workspace.shared.lastDocumentURL else {
            openNewDocumentIfNeeded()
            return
        }
        guard FileManager.default.fileExists(atPath: lastDocument.path) else {
            Workspace.shared.forgetLastDocument()
            openNewDocumentIfNeeded()
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: lastDocument, display: true) {
            [weak self] _, _, error in
            if error != nil {
                Workspace.shared.forgetLastDocument()
                self?.openNewDocumentIfNeeded()
            }
        }
    }

    private func openNewDocumentIfNeeded() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        NSDocumentController.shared.newDocument(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// L'avvio sceglie il documento dopo il ripristino di AppKit.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Sceglie la cartella di lavoro, cioè quella che il pulsante in barra del
    /// titolo elenca. Non apre nessun documento: cambia il contesto, non la vista.
    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Open")
        panel.message = localized("Choose the folder to work in.")
        panel.directoryURL = Workspace.shared.folder
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Workspace.shared.open(url)
        }
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func increaseTextSize(_ sender: Any?) {
        Settings.shared.adjustFontSize(by: 1)
    }

    @objc func decreaseTextSize(_ sender: Any?) {
        Settings.shared.adjustFontSize(by: -1)
    }

    @objc func resetTextSize(_ sender: Any?) {
        Settings.shared.fontSize = Theme().bodySize
    }

}

enum MainMenu {

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(applicationMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(formatMenu())
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        return main
    }

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?,
                            _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                            tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        menu.addItem(item)
        return item
    }

    private static func applicationMenu() -> NSMenuItem {
        submenu("Aurora") { menu in
            add(menu, localized("About Aurora"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.addItem(.separator())
            add(menu, localized("Settings…"), #selector(AppDelegate.showSettings(_:)), ",")
            menu.addItem(.separator())
            add(menu, localized("Hide Aurora"), #selector(NSApplication.hide(_:)), "h")
            add(menu, localized("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            add(menu, localized("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
            menu.addItem(.separator())
            add(menu, localized("Quit Aurora"), #selector(NSApplication.terminate(_:)), "q")
        }
    }

    private static func fileMenu() -> NSMenuItem {
        submenu(localized("File")) { menu in
            add(menu, localized("New"), #selector(NSDocumentController.newDocument(_:)), "n")
            add(menu, localized("Open…"), #selector(NSDocumentController.openDocument(_:)), "o")
            add(menu, localized("Open Side by Side…"), #selector(DocumentWindowController.openSideBySide(_:)), "\\")
            add(menu, localized("Open Folder…"), #selector(AppDelegate.openFolder(_:)), "o", [.command, .shift])
            let recents = NSMenuItem(title: localized("Open Recent"), action: nil, keyEquivalent: "")
            let recentsMenu = NSMenu(title: localized("Open Recent"))
            recentsMenu.addItem(withTitle: localized("Clear Menu"),
                                action: #selector(NSDocumentController.clearRecentDocuments(_:)),
                                keyEquivalent: "")
            recents.submenu = recentsMenu
            menu.addItem(recents)
            menu.addItem(.separator())
            add(menu, localized("Close"), #selector(NSWindow.performClose(_:)), "w")
            add(menu, localized("Save"), #selector(NSDocument.save(_:)), "s")
            add(menu, localized("Save As…"), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
            add(menu, localized("Revert to Saved"), #selector(NSDocument.revertToSaved(_:)))
            menu.addItem(.separator())
            add(menu, localized("Print…"), #selector(NSView.printView(_:)), "p")
        }
    }

    private static func editMenu() -> NSMenuItem {
        submenu(localized("Edit")) { menu in
            add(menu, localized("Undo"), Selector(("undo:")), "z")
            add(menu, localized("Redo"), Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            add(menu, localized("Cut"), #selector(NSText.cut(_:)), "x")
            add(menu, localized("Copy"), #selector(NSText.copy(_:)), "c")
            add(menu, localized("Paste"), #selector(NSText.paste(_:)), "v")
            add(menu, localized("Select All"), #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())
            let find = NSMenuItem(title: localized("Find"), action: nil, keyEquivalent: "")
            let findMenu = NSMenu(title: localized("Find"))
            add(findMenu, localized("Find…"), #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue))
            add(findMenu, localized("Find Next"), #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue))
            add(findMenu, localized("Find Previous"), #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: Int(NSFindPanelAction.previous.rawValue))
            add(findMenu, localized("Use Selection for Find"), #selector(NSTextView.performFindPanelAction(_:)), "e", tag: Int(NSFindPanelAction.setFindString.rawValue))
            find.submenu = findMenu
            menu.addItem(find)
            menu.addItem(.separator())
            add(menu, localized("Check Spelling While Typing"),
                #selector(NSTextView.toggleContinuousSpellChecking(_:)), "")
        }
    }

    private static func formatMenu() -> NSMenuItem {
        submenu(localized("Format")) { menu in
            add(menu, localized("Bold"), #selector(MarkdownTextView.toggleBold(_:)), "b")
            add(menu, localized("Italic"), #selector(MarkdownTextView.toggleItalic(_:)), "i")
            add(menu, localized("Underline"), #selector(MarkdownTextView.toggleUnderline(_:)), "u")
            add(menu, localized("Strikethrough"), #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift])
            add(menu, localized("Highlight"), #selector(MarkdownTextView.toggleHighlight(_:)), "h", [.command, .shift])
            add(menu, localized("Inline Code"), #selector(MarkdownTextView.toggleInlineCode(_:)), "`", [.command])
            menu.addItem(.separator())
            add(menu, localized("Paragraph"), #selector(MarkdownTextView.setHeadingLevel(_:)), "0", tag: 0)
            for level in 1...6 {
                add(menu, String(format: localized("Heading %d"), level),
                    #selector(MarkdownTextView.setHeadingLevel(_:)), "\(level)", tag: level)
            }
            menu.addItem(.separator())
            add(menu, localized("Promote Heading"),
                #selector(MarkdownTextView.promoteHeading(_:)), "+")
            add(menu, localized("Demote Heading"),
                #selector(MarkdownTextView.demoteHeading(_:)), "-")
            menu.addItem(.separator())
            add(menu, localized("Bulleted List"), #selector(MarkdownTextView.toggleBulletList(_:)), "u", [.command, .shift])
            add(menu, localized("Ordered List"), #selector(MarkdownTextView.toggleOrderedList(_:)))
            add(menu, localized("Task List"), #selector(MarkdownTextView.toggleTaskList(_:)), "t", [.command, .shift])
            add(menu, localized("Blockquote"), #selector(MarkdownTextView.toggleBlockquote(_:)), "'", [.command, .shift])
            add(menu, localized("Code Block"), #selector(MarkdownTextView.insertCodeBlock(_:)), "k", [.command, .option])
            add(menu, localized("Table…"), #selector(MarkdownTextView.insertTable(_:)), "t", [.command, .option])
            add(menu, localized("Edit Table…"), #selector(MarkdownTextView.editTable(_:)))
            menu.addItem(.separator())
            add(menu, localized("Link…"), #selector(MarkdownTextView.insertLink(_:)), "k")
            add(menu, localized("Image…"), #selector(MarkdownTextView.insertImage(_:)))
            add(menu, localized("Horizontal Rule"), #selector(MarkdownTextView.insertHorizontalRule(_:)))
        }
    }

    private static func viewMenu() -> NSMenuItem {
        submenu(localized("View")) { menu in
            add(menu, localized("Focus Other Document"),
                #selector(DocumentWindowController.focusOtherDocument(_:)), "\t", [.control])
            add(menu, localized("Separate Documents"), #selector(DocumentWindowController.separateDocuments(_:)))
            menu.addItem(.separator())
            add(menu, localized("Increase Text Size"),
                #selector(AppDelegate.increaseTextSize(_:)), "+", [.command, .shift])
            add(menu, localized("Decrease Text Size"),
                #selector(AppDelegate.decreaseTextSize(_:)), "-", [.command, .shift])
            add(menu, localized("Actual Text Size"),
                #selector(AppDelegate.resetTextSize(_:)))
            menu.addItem(.separator())
            add(menu, localized("Toggle Full Screen"),
                #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }
    }

    private static func windowMenu() -> NSMenuItem {
        let item = submenu(localized("Window")) { menu in
            add(menu, localized("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
            add(menu, localized("Zoom"), #selector(NSWindow.performZoom(_:)))
            menu.addItem(.separator())
            add(menu, localized("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        }
        NSApp.windowsMenu = item.submenu
        return item
    }
}
