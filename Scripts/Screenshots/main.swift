import AppKit

// Use the shipping document controllers and views, with a separate app identity.
let domain = Bundle.main.bundleIdentifier!
precondition(domain == "io.github.simo-ship-it.Aurora.Screenshots")
UserDefaults.standard.removePersistentDomain(forName: domain)
let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURORA_SCREENSHOT_ROOT"]!)
let italian = ProcessInfo.processInfo.environment["AURORA_SCREENSHOT_LANGUAGE"] == "it"
let suffix = italian ? "-it" : ""
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let documents = AuroraDocumentController()
final class ScreenshotDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
let delegate = ScreenshotDelegate()
app.delegate = delegate
app.finishLaunching()

func settle() async { try? await Task.sleep(nanoseconds: 350_000_000) }

@MainActor func open(_ name: String, text: String) async throws -> MarkdownDocument {
    let folder = root.appendingPathComponent(".build/Screenshots/\(italian ? "it" : "en")")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name + ".md")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return try await withCheckedThrowingContinuation { continuation in
        documents.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: document as! MarkdownDocument) }
        }
    }
}

@MainActor func capture(_ window: NSWindow, name: String) async throws {
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    await settle()
    let frameView = window.contentView!.superview!
    frameView.layoutSubtreeIfNeeded()
    frameView.displayIfNeeded()
    let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)!
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    let url = root.appendingPathComponent("docs/\(name)\(suffix).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    print("Captured \(url.path)")
}

Task { @MainActor in
    do {
        Settings.shared.fontSize = 17
        Settings.shared.lineHeight = 1.45
        Settings.shared.contentWidth = 740
        Settings.shared.appearance = .light
        NSApp.mainMenu = MainMenu.build()
        let welcome = italian ? """
        # Lo spazio per le tue idee

        Scrivi in **Markdown**, leggi un documento. Un editor nativo per macOS,
        con una sola area di scrittura e nessuna anteprima da affiancare.

        ## Dalla prima idea alla bozza

        - [x] Raccogliere gli appunti
        - [x] Dare una struttura al testo
        - [ ] Trovare le parole giuste

        > Concentrati su quello che vuoi dire.
        > Aurora si occupa della formattazione.

        ## I tuoi strumenti, a portata di mano

        | Formato | Scorciatoia |
        | --- | --- |
        | Grassetto | ⌘B |
        | Corsivo | ⌘I |
        | Collegamento | ⌘K |

        Testo *corsivo*, ==passaggi importanti== e `codice inline`.
        """ : """
        # A little room for your ideas

        Write in **Markdown**, read a document. A native editor for macOS,
        with one writing surface and no separate preview to manage.

        ## From the first idea to a draft

        - [x] Gather your notes
        - [x] Give the text a structure
        - [ ] Find the right words

        > Focus on what you want to say.
        > Aurora takes care of the formatting.

        ## Your tools, close at hand

        | Format | Shortcut |
        | --- | --- |
        | Bold | ⌘B |
        | Italic | ⌘I |
        | Link | ⌘K |

        A little *emphasis*, ==important passages== and `inline code`.
        """
        let first = try await open(italian ? "Benvenuto" : "Welcome", text: welcome + "\n")
        let host = first.hostingWindowController!
        host.window!.setContentSize(NSSize(width: 1000, height: 880))
        host.window!.center()
        host.panes[0].editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        try await capture(host.window!, name: "screenshot")
        Settings.shared.appearance = .dark
        try await capture(host.window!, name: "screenshot-dark")
        Settings.shared.appearance = .light
        let notes = italian ? """
        # Appunti di ricerca

        Due documenti, un unico spazio di lavoro.

        ## Cosa tenere vicino

        - Le fonti da confrontare
        - La scaletta della prossima bozza
        - Le idee da sviluppare

        ## Ogni documento è indipendente

        - [x] Scorrimento separato
        - [x] Salvataggio del file attivo
        - [x] Cronologia di annullamento dedicata

        > Trascina il divisore per fare spazio alle tue idee.
        """ : """
        # Research notes

        Two documents, one workspace.

        ## Keep these close

        - Sources to compare
        - An outline for the next draft
        - Ideas worth developing

        ## Each document stays independent

        - [x] Separate scrolling
        - [x] Save the active file
        - [x] An undo history of its own

        > Drag the divider to make room for your ideas.
        """
        let second = try await open(italian ? "Ricerca" : "Research", text: notes + "\n")
        precondition(host.attach(second))
        host.window!.setContentSize(NSSize(width: 1440, height: 880))
        host.window!.center()
        host.activate(first)
        try await capture(host.window!, name: "screenshot-split")
        first.close()
        second.close()
        UserDefaults.standard.removePersistentDomain(forName: domain)
        exit(0)
    } catch {
        fputs("Screenshot capture failed: \(error)\n", stderr)
        exit(1)
    }
}
app.run()
