import AppKit
import AuroraCore
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument {

    /// Misura usata solo per una finestra nuova; AppKit ripristina poi quella
    /// che l'utente ha scelto grazie al nome di autosalvataggio del frame.
    private static let initialContentSize = NSSize(width: 900, height: 760)

    var text: String = ""
    private weak var editor: EditorViewController?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let editor = EditorViewController()
        self.editor = editor

        // La misura iniziale vive qui, dove la finestra viene creata. Impostarla
        // anche nel view controller fa ricalcolare il frame quando la sua vista
        // compare, producendo un ridimensionamento visibile dopo l'apertura.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)

        // La barra del titolo si fonde con la pagina, ma il nome del documento
        // e l'icona-proxy restano: servono per rinominare e trascinare il file.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = Theme.current.background
        window.minSize = NSSize(width: 420, height: 320)
        window.contentViewController = editor
        window.center()
        window.setFrameAutosaveName("AuroraEditorWindow")
        window.tabbingMode = .preferred
        window.addTitlebarAccessoryViewController(WorkspaceButtonController())

        // Senza una cartella scelta, il pulsante mostra quella del documento aperto.
        Workspace.shared.adoptIfEmpty(fileURL)

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        addWindowController(controller)

        editor.text = text
        editor.onTextChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.text = editor.text
            self.updateChangeCount(.changeDone)
        }
        DispatchQueue.main.async { editor.focus() }
    }

    // MARK: - Lettura e scrittura

    override func data(ofType typeName: String) throws -> Data {
        if let editor { text = editor.text }
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
        }
        return data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: nil)
        }
        text = contents
        editor?.text = contents
    }

}
