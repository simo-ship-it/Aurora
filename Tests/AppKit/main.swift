import AppKit

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let documents = AuroraDocumentController()
final class CheckApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
let checkDelegate = CheckApplicationDelegate()
app.delegate = checkDelegate
app.finishLaunching()
app.activate(ignoringOtherApps: true)
let domain = Bundle.main.bundleIdentifier!
precondition(domain == "io.github.simo-ship-it.Aurora.AppCheck")
UserDefaults.standard.removePersistentDomain(forName: domain)
let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURORA_APP_CHECK_ROOT"]!, isDirectory: true)
let fixtures = root.appendingPathComponent("Fixtures", isDirectory: true)
var checks = 0
final class WeakReference<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1
    print("PASS: \(name)")
}

func settle() async { try? await Task.sleep(nanoseconds: 150_000_000) }

@MainActor func open(_ url: URL) async -> MarkdownDocument {
    await withCheckedContinuation { continuation in
        documents.openDocument(withContentsOf: url, display: true) { document, _, error in
            check(error == nil && document is MarkdownDocument, "Apertura ordinaria \(url.lastPathComponent)")
            continuation.resume(returning: document as! MarkdownDocument)
        }
    }
}

@MainActor func save(_ document: MarkdownDocument) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        document.save(to: document.fileURL!, ofType: document.fileType!, for: .saveOperation) { error in
            check(error == nil, "Salvataggio \(document.displayName ?? "")")
            continuation.resume()
        }
    }
}

@MainActor func edit(_ pane: DocumentPaneViewController, suffix: String) async {
    pane.document.hostingWindowController?.activate(pane.document)
    let textView = pane.editor.textView!
    let undo = pane.document.undoManager!
    check(textView.undoManager === undo, "L’editor usa la cronologia del proprio documento")
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.insertText(suffix, replacementRange: textView.selectedRange())
    undo.endUndoGrouping()
    await settle()
    check(pane.document.isDocumentEdited, "La modifica rende il documento non salvato")
}

func views(in view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + views(in: $0) } }

Task { @MainActor in
    do {
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        let leftFolder = fixtures.appendingPathComponent("Left", isDirectory: true)
        let rightFolder = fixtures.appendingPathComponent("Right", isDirectory: true)
        try FileManager.default.createDirectory(at: leftFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightFolder, withIntermediateDirectories: true)
        let leftURL = leftFolder.appendingPathComponent("Idee.md")
        let rightURL = rightFolder.appendingPathComponent("Appunti.md")
        let leftText = "# Idee da sviluppare\n\nDue documenti, un unico spazio di lavoro.\n\n## La struttura\n\n- Organizzare il testo\n- Confrontare le fonti\n- Scrivere senza cambiare finestra\n\n> Le idee migliori trovano spazio una accanto all’altra.\n"
        let rightText = "# Appunti di ricerca\n\nUn secondo documento resta indipendente dal primo.\n\n## Da ricordare\n\n- Scorrimento indipendente\n- Salvataggio del documento attivo\n- Divisore regolabile\n\n```swift\nlet views = [idee, appunti]\n```\n"
        try leftText.write(to: leftURL, atomically: true, encoding: .utf8)
        try rightText.write(to: rightURL, atomically: true, encoding: .utf8)
        Settings.shared.fontSize = 18
        Settings.shared.contentWidth = 720
        Settings.shared.appearance = .light
        NSApp.mainMenu = MainMenu.build()
        let left = await open(leftURL)
        let right = await open(rightURL)
        await settle()
        check(documents.documents.count == 2, "Soltanto i documenti di prova sono aperti")
        let host = left.hostingWindowController!
        let previousRightHost = WeakReference(right.hostingWindowController)
        let previousRightEditor = right.hostingWindowController!.panes[0].editor
        host.showWindow(nil)
        check(host.attach(right), "Affiancamento documento già aperto")
        await settle()
        check(host.isSplit && host.panes.count == 2, "Due riquadri nella stessa finestra")
        check(abs(host.panes[0].view.frame.width - host.panes[1].view.frame.width) < 2,
              "Ripartizione iniziale uniforme dello spazio")
        check(left.hostingWindowController === right.hostingWindowController, "Finestra condivisa")
        check(previousRightHost.value == nil, "Controller della vecchia finestra rilasciato")
        check(host.panes[1].editor === previousRightEditor, "Editor trasferito senza perdere lo stato")
        check(host.panes.allSatisfy { $0.editor.view.window === host.window }, "Entrambi gli editor visibili nello split")
        check(host.activeDocument === right, "Nuovo riquadro attivo")
        check(documents.currentDocument === right, "AppKit riconosce il documento attivo")
        let leftPane = host.panes[0]
        let rightPane = host.panes[1]
        host.activate(left)
        check(documents.currentDocument === left, "Cambio documento attivo a sinistra")
        host.window?.makeFirstResponder(rightPane.editor.textView)
        check(host.activeDocument === right, "Il fuoco nel testo cambia documento attivo")
        check((NSApp.target(forAction: #selector(NSDocument.save(_:))) as? MarkdownDocument) === right,
              "Il comando Salva raggiunge il documento a destra")
        check(leftPane.editor.textView.resolvedURL(for: "image.png") == leftFolder.appendingPathComponent("image.png"),
              "Immagini relative al documento sinistro anche quando è inattivo")
        check(rightPane.editor.textView.resolvedURL(for: "image.png") == rightFolder.appendingPathComponent("image.png"),
              "Immagini relative al documento destro")
        check(left.undoManager !== right.undoManager, "Cronologie di annullamento indipendenti")
        await edit(leftPane, suffix: "\nModifica sinistra.\n")
        await edit(rightPane, suffix: "\nModifica destra.\n")
        let changedRight = right.text
        left.undoManager?.undo()
        check(left.text == leftText && right.text == changedRight, "Annulla agisce soltanto sul documento sinistro")
        check(!left.isDocumentEdited, "Annullare tutte le modifiche ripristina lo stato salvato")
        left.undoManager?.redo()
        check(left.text.contains("Modifica sinistra.") && right.text == changedRight, "Ripristina indipendente")
        await settle()
        await save(left)
        await save(right)
        let savedLeft = try String(contentsOf: leftURL, encoding: .utf8)
        let savedRight = try String(contentsOf: rightURL, encoding: .utf8)
        check(savedLeft == left.text, "Contenuto sinistro salvato sul file corretto")
        check(savedRight == right.text, "Contenuto destro salvato sul file corretto")
        check(!left.isDocumentEdited && !right.isDocumentEdited, "Documenti puliti dopo il salvataggio")
        let externalLeft = left.text + "\nAggiornamento esterno.\n"
        try externalLeft.write(to: leftURL, atomically: true, encoding: .utf8)
        try? await Task.sleep(nanoseconds: 600_000_000)
        check(left.text == externalLeft && right.text == changedRight, "Aggiornamento esterno nel riquadro inattivo")
        let split = host.contentViewController as! NSSplitViewController
        split.splitView.setPosition(420, ofDividerAt: 0)
        await settle()
        check(split.splitView.subviews[0].frame.width >= 320 && split.splitView.subviews[1].frame.width >= 320,
              "Divisore regolabile con larghezze minime")
        let reopenedLeft = await open(leftURL)
        check(reopenedLeft === left && host.activeDocument === left && host.panes.count == 2,
              "Riaprire un file dello split seleziona il riquadro esistente")
        check(host.attach(left) && host.panes.count == 2, "Nessun riquadro duplicato per lo stesso documento")
        host.detach(right)
        await settle()
        check(!host.isSplit && right.hostingWindowController !== host, "Separazione in due finestre")
        check(right.hostingWindowController?.panes.first?.editor === previousRightEditor,
              "Separazione conserva editor e annullamenti")
        check(host.attach(right), "Nuovo affiancamento dopo la separazione")
        await settle()
        check(abs(host.panes[0].view.frame.width - host.panes[1].view.frame.width) < 2,
              "Ripartizione uniforme anche dopo la separazione")
        // Il salvataggio con nome resta legato al documento di ogni riquadro.
        let renamed = rightFolder.appendingPathComponent("Ricerca.md")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            right.save(to: renamed, ofType: right.fileType!, for: .saveAsOperation) { error in
                check(error == nil, "Salva con nome nel secondo riquadro")
                continuation.resume()
            }
        }
        await settle()
        check(right.fileURL == renamed && left.fileURL == leftURL, "Salva con nome non modifica il primo percorso")
        check(host.window?.title.contains("Ricerca") == true, "Titolo aggiornato dopo Salva con nome")
        if let path = ProcessInfo.processInfo.environment["AURORA_APP_CHECK_SCREENSHOT"],
           let view = host.window?.contentView {
            host.activate(left)
            view.layoutSubtreeIfNeeded()
            await settle()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            }
        }
        host.requestClose(left)
        await settle()
        check(!host.isSplit && host.activeDocument === right, "Chiusura di un riquadro mantiene l’altro aperto")
        check(!documents.documents.contains { $0 === left }, "Documento chiuso rimosso da AppKit")
        host.window?.performClose(nil)
        await settle()
        check(!documents.documents.contains { $0 === right }, "Chiusura ordinaria dell’ultimo riquadro")
        // Un pannello di chiusura annullato deve conservare entrambi i riquadri.
        let clean = try documents.makeUntitledDocument(ofType: "net.daringfireball.markdown") as! MarkdownDocument
        let unsaved = try documents.makeUntitledDocument(ofType: "net.daringfireball.markdown") as! MarkdownDocument
        documents.addDocument(clean)
        documents.addDocument(unsaved)
        clean.makeWindowControllers()
        clean.showWindows()
        let reviewHost = clean.hostingWindowController!
        check(reviewHost.attach(unsaved), "Affiancamento documento senza nome")
        await settle()
        await edit(reviewHost.panes[1], suffix: "Modifica da conservare.")
        await settle()
        check(unsaved.text.contains("Modifica da conservare."), "Modifica nel documento senza nome")
        reviewHost.window?.performClose(nil)
        await settle()
        for _ in 0..<20 {
            if reviewHost.window?.attachedSheet != nil { break }
            await settle()
        }
        guard let sheet = reviewHost.window?.attachedSheet else { check(false, "Pannello per le modifiche non salvate"); exit(1) }
        let cancel = views(in: sheet.contentView!).compactMap { $0 as? NSButton }.first {
            $0.keyEquivalent == "\u{1b}" || ["Cancel", "Annulla"].contains($0.title)
        }
        check(sheet is NSSavePanel || cancel != nil, "Chiusura richiede la scelta sulle modifiche non salvate")
        if let savePanel = sheet as? NSSavePanel { savePanel.cancel(nil) }
        else { cancel?.performClick(nil) }
        await settle()
        check(reviewHost.isSplit && documents.documents.contains { $0 === clean }
              && documents.documents.contains { $0 === unsaved }, "Annullare conserva entrambi i documenti")
        check(unsaved.text.contains("Modifica da conservare."), "Annullare conserva il testo non salvato")
        // Attendiamo che la chiusura animata del pannello sia completata,
        // proprio come fa l'interfaccia prima di accettare un altro comando.
        for _ in 0..<20 {
            if reviewHost.window?.attachedSheet == nil { break }
            await settle()
        }
        check(reviewHost.window?.attachedSheet == nil, "Pannello annullato correttamente dismesso")
        reviewHost.window?.performClose(nil)
        await settle()
        check(reviewHost.window?.attachedSheet != nil, "Si può chiedere nuovamente la chiusura dopo Annulla")
        if let panel = reviewHost.window?.attachedSheet as? NSSavePanel { panel.cancel(nil) }
        else if let content = reviewHost.window?.attachedSheet?.contentView {
            views(in: content).compactMap { $0 as? NSButton }.first {
                $0.keyEquivalent == "\u{1b}" || ["Cancel", "Annulla"].contains($0.title)
            }?.performClick(nil)
        }
        for _ in 0..<20 {
            if reviewHost.window?.attachedSheet == nil { break }
            await settle()
        }
        clean.close()
        unsaved.close()
        check(documents.documents.isEmpty, "Documenti di prova senza nome chiusi")
        let ordinary = await open(leftURL)
        check(ordinary.hostingWindowController?.panes.count == 1, "Apertura normale dopo l’uso dello split")
        let ordinaryHost = ordinary.hostingWindowController!
        let openedBeside: Bool = await withCheckedContinuation { continuation in
            ordinaryHost.openBeside(rightURL) { continuation.resume(returning: $0) }
        }
        await settle()
        check(openedBeside && ordinaryHost.isSplit, "Apertura affiancata di un nuovo file")
        check(ordinaryHost.activeDocument?.fileURL == rightURL, "Nuovo file affiancato attivo")
        check((NSApp.target(forAction: #selector(DocumentWindowController.focusOtherDocument(_:))) as? DocumentWindowController) === ordinaryHost,
              "Comando Passa all’altro documento raggiunge la finestra")
        ordinaryHost.focusOtherDocument(nil)
        check(ordinaryHost.activeDocument === ordinary, "Passaggio all’altro documento")
        ordinaryHost.window?.performClose(nil)
        await settle()
        check(documents.documents.isEmpty, "Chiusura dei due file aperti con Apri affiancato")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        print("\(checks) verifiche AppKit superate.")
        exit(0)
    } catch {
        fputs("FAIL: \(error)\n", stderr)
        exit(1)
    }
}
app.run()
