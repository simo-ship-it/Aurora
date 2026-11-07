import AppKit
import AuroraCore
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument {

    var text: String = ""
    private weak var editor: EditorViewController?
    weak var hostingWindowController: DocumentWindowController?
    private var enclosingFolderObserver: DirectoryChangeObserver?
    private var scheduledExternalReload: DispatchWorkItem?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        guard hostingWindowController == nil else { return }
        let pane = DocumentPaneViewController(document: self, editor: makeEditor())
        _ = DocumentWindowController(pane: pane)
        Workspace.shared.rememberDocument(fileURL)
        Workspace.shared.adoptIfEmpty(fileURL)
    }

    func makeEditor() -> EditorViewController {
        if let editor { return editor }
        // Il setter collega anche le notifiche di Annulla al conteggio delle
        // modifiche di NSDocument. Ogni editor nasce con il proprio gestore.
        hasUndoManager = true
        undoManager = UndoManager()
        let editor = EditorViewController()
        self.editor = editor
        editor.document = self
        _ = editor.view
        editor.text = text
        editor.onTextChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.text = editor.text
            // NSDocument osserva già il proprio UndoManager: contare anche qui
            // conterebbe due volte la stessa modifica e altererebbe Annulla.
        }
        return editor
    }

    override func showWindows() {
        if hostingWindowController == nil { makeWindowControllers() }
        hostingWindowController?.showWindow(nil)
        hostingWindowController?.activate(self)
    }

    override var windowForSheet: NSWindow? { hostingWindowController?.window ?? super.windowForSheet }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        hostingWindowController?.refreshDocumentState()
    }

    override func updateChangeCount(withToken token: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: token, for: saveOperation)
        hostingWindowController?.refreshDocumentState()
    }

    override func close() {
        hostingWindowController?.removePane(for: self)
        enclosingFolderObserver = nil
        scheduledExternalReload?.cancel()
        super.close()
    }

    /// Dopo un "Salva con nome" il file acquisisce finalmente un percorso:
    /// registriamolo appena AppKit lo aggiorna per poterlo ripristinare.
    override var fileURL: URL? {
        didSet {
            Workspace.shared.rememberDocument(fileURL)
            observeEnclosingFolder()
            DispatchQueue.main.async { [weak self] in self?.hostingWindowController?.refreshDocumentState() }
        }
    }

    deinit {
        scheduledExternalReload?.cancel()
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

    // MARK: - Modifiche esterne

    /// NSDocument è già un file presenter: questo copre gli editor che usano
    /// NSFileCoordinator. L'osservatore della cartella qui sotto copre anche
    /// quelli che salvano direttamente o sostituiscono il file in modo atomico.
    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        scheduleExternalReload()
    }

    private func observeEnclosingFolder() {
        guard let fileURL else {
            enclosingFolderObserver = nil
            return
        }
        enclosingFolderObserver = DirectoryChangeObserver(
            directoryURL: fileURL.deletingLastPathComponent(),
            label: fileURL.path) { [weak self] in
                self?.scheduleExternalReload()
            }
    }

    /// Accorpa le numerose notifiche che alcuni programmi generano mentre
    /// salvano. Il piccolo ritardo fa leggere il file solo quando la
    /// sostituzione atomica si è conclusa e mantiene l'editor reattivo.
    private func scheduleExternalReload() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduledExternalReload?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.reloadFromDiskIfNeeded()
            }
            self.scheduledExternalReload = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: work)
        }
    }

    private func reloadFromDiskIfNeeded() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              contents != text else { return }

        // Non sovrascriviamo una modifica locale ancora da salvare. AppKit la
        // conserverà e potrà usare la sua normale gestione dei conflitti; non
        // appena il documento è pulito, la prossima modifica esterna verrà
        // comunque recepita in automatico.
        guard !isDocumentEdited else { return }

        text = contents
        editor?.replaceTextPreservingViewState(with: contents)
        updateChangeCount(.changeCleared)
    }

}
