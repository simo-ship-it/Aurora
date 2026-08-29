import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSDocumentController.shared          // registra l'architettura dei documenti
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    /// Sceglie la cartella di lavoro, cioè quella che il pulsante in barra del
    /// titolo elenca. Non apre nessun documento: cambia il contesto, non la vista.
    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Apri"
        panel.message = "Scegli la cartella su cui lavorare."
        panel.directoryURL = Workspace.shared.folder
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Workspace.shared.open(url)
        }
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
            add(menu, "Informazioni su Aurora", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.addItem(.separator())
            add(menu, "Nascondi Aurora", #selector(NSApplication.hide(_:)), "h")
            add(menu, "Nascondi altre", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            add(menu, "Mostra tutte", #selector(NSApplication.unhideAllApplications(_:)))
            menu.addItem(.separator())
            add(menu, "Esci da Aurora", #selector(NSApplication.terminate(_:)), "q")
        }
    }

    private static func fileMenu() -> NSMenuItem {
        submenu("File") { menu in
            add(menu, "Nuovo", #selector(NSDocumentController.newDocument(_:)), "n")
            add(menu, "Apri…", #selector(NSDocumentController.openDocument(_:)), "o")
            add(menu, "Apri cartella…", #selector(AppDelegate.openFolder(_:)), "o", [.command, .shift])
            let recents = NSMenuItem(title: "Apri recenti", action: nil, keyEquivalent: "")
            let recentsMenu = NSMenu(title: "Apri recenti")
            recentsMenu.addItem(withTitle: "Svuota menu",
                                action: #selector(NSDocumentController.clearRecentDocuments(_:)),
                                keyEquivalent: "")
            recents.submenu = recentsMenu
            menu.addItem(recents)
            menu.addItem(.separator())
            add(menu, "Chiudi", #selector(NSWindow.performClose(_:)), "w")
            add(menu, "Salva", #selector(NSDocument.save(_:)), "s")
            add(menu, "Salva con nome…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
            add(menu, "Ripristina versione salvata", #selector(NSDocument.revertToSaved(_:)))
            menu.addItem(.separator())
            add(menu, "Stampa…", #selector(NSView.printView(_:)), "p")
        }
    }

    private static func editMenu() -> NSMenuItem {
        submenu("Modifica") { menu in
            add(menu, "Annulla", Selector(("undo:")), "z")
            add(menu, "Ripristina", Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Taglia", #selector(NSText.cut(_:)), "x")
            add(menu, "Copia", #selector(NSText.copy(_:)), "c")
            add(menu, "Incolla", #selector(NSText.paste(_:)), "v")
            add(menu, "Seleziona tutto", #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())
            let find = NSMenuItem(title: "Cerca", action: nil, keyEquivalent: "")
            let findMenu = NSMenu(title: "Cerca")
            add(findMenu, "Cerca…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue))
            add(findMenu, "Successivo", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue))
            add(findMenu, "Precedente", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: Int(NSFindPanelAction.previous.rawValue))
            add(findMenu, "Usa selezione per cercare", #selector(NSTextView.performFindPanelAction(_:)), "e", tag: Int(NSFindPanelAction.setFindString.rawValue))
            find.submenu = findMenu
            menu.addItem(find)
            menu.addItem(.separator())
            add(menu, "Controllo ortografia durante la scrittura",
                #selector(NSTextView.toggleContinuousSpellChecking(_:)), "")
        }
    }

    private static func formatMenu() -> NSMenuItem {
        submenu("Formato") { menu in
            add(menu, "Grassetto", #selector(MarkdownTextView.toggleBold(_:)), "b")
            add(menu, "Corsivo", #selector(MarkdownTextView.toggleItalic(_:)), "i")
            add(menu, "Barrato", #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift])
            add(menu, "Evidenziato", #selector(MarkdownTextView.toggleHighlight(_:)), "h", [.command, .shift])
            add(menu, "Codice inline", #selector(MarkdownTextView.toggleInlineCode(_:)), "`", [.command])
            menu.addItem(.separator())
            add(menu, "Paragrafo", #selector(MarkdownTextView.setHeadingLevel(_:)), "0", tag: 0)
            for level in 1...6 {
                add(menu, "Titolo \(level)", #selector(MarkdownTextView.setHeadingLevel(_:)),
                    "\(level)", tag: level)
            }
            menu.addItem(.separator())
            add(menu, "Elenco puntato", #selector(MarkdownTextView.toggleBulletList(_:)), "u", [.command, .shift])
            add(menu, "Elenco di attività", #selector(MarkdownTextView.toggleTaskList(_:)), "t", [.command, .shift])
            add(menu, "Citazione", #selector(MarkdownTextView.toggleBlockquote(_:)), "'", [.command, .shift])
            add(menu, "Blocco di codice", #selector(MarkdownTextView.insertCodeBlock(_:)), "k", [.command, .option])
            menu.addItem(.separator())
            add(menu, "Collegamento…", #selector(MarkdownTextView.insertLink(_:)), "k")
            add(menu, "Linea orizzontale", #selector(MarkdownTextView.insertHorizontalRule(_:)), "-", [.command, .shift])
        }
    }

    private static func viewMenu() -> NSMenuItem {
        submenu("Vista") { menu in
            add(menu, "Attiva/disattiva schermo intero",
                #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }
    }

    private static func windowMenu() -> NSMenuItem {
        let item = submenu("Finestra") { menu in
            add(menu, "Riduci a icona", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(menu, "Zoom", #selector(NSWindow.performZoom(_:)))
            menu.addItem(.separator())
            add(menu, "Porta tutto in primo piano", #selector(NSApplication.arrangeInFront(_:)))
        }
        NSApp.windowsMenu = item.submenu
        return item
    }
}
