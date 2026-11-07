import AppKit
import UniformTypeIdentifiers

/// AppKit memorizza il documento della finestra quando questa diventa attiva.
/// Nello split il fuoco può cambiare senza un cambio di finestra: anche i
/// comandi globali e la cartella del pannello Apri devono seguire il riquadro.
final class AuroraDocumentController: NSDocumentController {
    override var currentDocument: NSDocument? {
        if let host = NSApp.keyWindow?.windowController as? DocumentWindowController { return host.activeDocument }
        if let host = NSApp.mainWindow?.windowController as? DocumentWindowController { return host.activeDocument }
        return super.currentDocument
    }

    override func document(for window: NSWindow) -> NSDocument? {
        (window.windowController as? DocumentWindowController)?.activeDocument ?? super.document(for: window)
    }
}

/// Una finestra può contenere due documenti, ma AppKit associa il controller
/// soltanto a quello attivo. I riquadri trattengono entrambi i documenti;
/// cambiare il fuoco sposta l'associazione, senza ricreare gli editor.
final class DocumentWindowController: NSWindowController, NSMenuItemValidation {
    private let splitController = DocumentSplitViewController()
    private(set) var panes: [DocumentPaneViewController] = []
    private var closeReview: DocumentCloseReview?
    private var openingCompanion = false
    private var isTearingDown = false
    private var splitButtonController: SplitViewButtonController?

    var activeDocument: MarkdownDocument? { document as? MarkdownDocument }
    var isSplit: Bool { panes.count == 2 }

    init(pane: DocumentPaneViewController) {
        let window = DocumentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        shouldCascadeWindows = true
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = Theme.current.background
        window.minSize = NSSize(width: 420, height: 320)
        splitController.splitView = DocumentDividerSplitView()
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 900, height: 760))
        window.center()
        window.setFrameAutosaveName("AuroraEditorWindow")
        window.tabbingMode = .preferred
        window.addTitlebarAccessoryViewController(WorkspaceButtonController())
        let splitButton = SplitViewButtonController(host: self)
        splitButtonController = splitButton
        window.addTitlebarAccessoryViewController(splitButton)
        install(pane)
        activate(pane.document, focusEditor: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    @discardableResult
    func attach(_ other: MarkdownDocument) -> Bool {
        if panes.contains(where: { $0.document === other }) {
            activate(other)
            return true
        }
        guard !isSplit, !isTearingDown, closeReview == nil else { return false }
        let pane: DocumentPaneViewController
        if let previous = other.hostingWindowController {
            guard !previous.openingCompanion, previous.closeReview == nil, previous.window?.attachedSheet == nil,
                  let existing = previous.removePane(for: other) else { return false }
            pane = existing
        } else {
            pane = DocumentPaneViewController(document: other, editor: other.makeEditor())
        }
        install(pane)
        splitController.balanceOnNextLayout = true
        if let window, !window.styleMask.contains(.fullScreen) {
            let limit = window.screen?.visibleFrame.width ?? 1200
            var frame = window.frame
            frame.size.width = min(limit, max(1100, frame.width))
            if let screen = window.screen { frame.origin.x = min(frame.minX, screen.visibleFrame.maxX - frame.width) }
            window.setFrame(frame, display: true)
        }
        splitController.view.needsLayout = true
        splitController.view.layoutSubtreeIfNeeded()
        activate(other)
        return true
    }

    private func install(_ pane: DocumentPaneViewController) {
        pane.document.hostingWindowController = self
        panes.append(pane)
        let item = NSSplitViewItem(viewController: pane)
        item.minimumThickness = 320
        item.canCollapse = false
        splitController.addSplitViewItem(item)
        refreshDocumentState()
    }

    func activate(_ selected: MarkdownDocument, focusEditor: Bool = true) {
        guard let pane = panes.first(where: { $0.document === selected }), !isTearingDown else { return }
        if activeDocument !== selected {
            // addWindowController rimuove automaticamente il controller dal
            // documento precedente: il menu Salva e i pannelli seguono il fuoco.
            selected.addWindowController(self)
            Workspace.shared.rememberDocument(selected.fileURL)
        }
        refreshDocumentState()
        if focusEditor { pane.editor.focus() }
    }

    func firstResponderChanged(_ responder: NSResponder?) {
        var view = responder as? NSView
        // Il field editor è condiviso dalla finestra: appartiene al documento
        // della cella che sta modificando, non a quello attivo in precedenza.
        if let text = responder as? NSTextView, text.isFieldEditor {
            view = text.delegate as? NSView ?? view
        }
        while let current = view {
            if let pane = panes.first(where: { $0.view === current }) {
                activate(pane.document, focusEditor: false)
                return
            }
            view = current.superview
        }
    }

    func refreshDocumentState() {
        for pane in panes { pane.updateHeader(isSplit: isSplit, isActive: pane.document === activeDocument) }
        let minimum = NSSize(width: isSplit ? 720 : 420, height: 320)
        if window?.minSize != minimum { window?.minSize = minimum }
        let tabbing: NSWindow.TabbingMode = isSplit ? .disallowed : .preferred
        if window?.tabbingMode != tabbing { window?.tabbingMode = tabbing }
        synchronizeWindowTitleWithDocumentName()
        setDocumentEdited(panes.contains { $0.document.isDocumentEdited })
        splitButtonController?.refresh()
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if isSplit { window?.title = panes.map { $0.document.displayName }.joined(separator: " · ") }
    }

    override func setDocumentEdited(_ dirtyFlag: Bool) {
        super.setDocumentEdited(panes.contains { $0.document.isDocumentEdited })
    }

    @objc func openSideBySide(_ sender: Any?) {
        guard let window, !isSplit, !openingCompanion, closeReview == nil,
              window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = activeDocument?.fileURL?.deletingLastPathComponent() ?? Workspace.shared.folder
        panel.prompt = localized("Open Side by Side")
        panel.message = localized("Choose a second document to display beside the current one.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openBeside(url)
        }
    }

    /// Usa lo stesso NSDocumentController dell'apertura ordinaria, così un file
    /// già aperto viene trasferito, con modifiche e annullamenti intatti.
    func openBeside(_ url: URL, completion: ((Bool) -> Void)? = nil) {
        guard !isSplit, !openingCompanion, !isTearingDown, closeReview == nil else {
            completion?(false)
            return
        }
        openingCompanion = true
        splitButtonController?.refresh()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) {
            [weak self] opened, _, error in
            guard let self else {
                opened?.makeWindowControllers()
                opened?.showWindows()
                completion?(false)
                return
            }
            self.openingCompanion = false
            self.splitButtonController?.refresh()
            if let error {
                NSApp.presentError(error)
                completion?(false)
                return
            }
            guard let other = opened as? MarkdownDocument else { completion?(false); return }
            let attached = self.attach(other)
            if !attached {
                other.makeWindowControllers()
                other.showWindows()
            }
            completion?(attached)
        }
    }

    @objc func focusOtherDocument(_ sender: Any?) {
        guard isSplit, let other = panes.first(where: { $0.document !== activeDocument }) else { return }
        activate(other.document)
    }

    @objc func separateDocuments(_ sender: Any?) {
        guard isSplit, let other = panes.first(where: { $0.document !== activeDocument }) else { return }
        detach(other.document)
    }

    func detach(_ selected: MarkdownDocument) {
        guard isSplit, closeReview == nil, !openingCompanion,
              let pane = removePane(for: selected) else { return }
        let separate = DocumentWindowController(pane: pane)
        separate.showWindow(nil)
        pane.editor.focus()
    }

    @discardableResult
    func removePane(for selected: MarkdownDocument) -> DocumentPaneViewController? {
        guard let index = panes.firstIndex(where: { $0.document === selected }) else { return nil }
        let pane = panes.remove(at: index)
        if activeDocument === selected { selected.removeWindowController(self) }
        splitController.removeSplitViewItem(splitController.splitViewItems[index])
        selected.hostingWindowController = nil
        if let remaining = panes.first {
            activate(remaining.document)
        } else {
            isTearingDown = true
            // Nessun documento è più associato: chiudere la cornice non deve
            // chiudere anche un documento che stiamo trasferendo altrove.
            window?.close()
        }
        return pane
    }

    func requestClose(_ selected: MarkdownDocument? = nil) {
        guard closeReview == nil, !openingCompanion, !isTearingDown,
              window?.attachedSheet == nil else { return }
        let documents = selected.map { [$0] } ?? panes.map(\.document)
        let previousResponder = window?.firstResponder
        guard window?.makeFirstResponder(nil) == true else { return }
        let review = DocumentCloseReview(documents: documents) { [weak self] approved in
            guard let self else { return }
            self.closeReview = nil
            if approved { documents.forEach { $0.close() } }
            else if let previousResponder { self.window?.makeFirstResponder(previousResponder) }
        }
        closeReview = review
        review.start()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !isTearingDown, closeReview == nil, !openingCompanion, window?.attachedSheet == nil else { return false }
        switch item.action {
        case #selector(openSideBySide(_:)): return !isSplit
        case #selector(separateDocuments(_:)), #selector(focusOtherDocument(_:)): return isSplit
        default: return true
        }
    }

    var canUseSplitButton: Bool {
        !isTearingDown && closeReview == nil && !openingCompanion && window?.attachedSheet == nil
    }
}

/// Le chiusure normali (pulsante rosso e ⌘W) revisionano entrambi i documenti
/// prima di rimuoverne uno. Annullare il secondo pannello conserva lo split.
private final class DocumentWindow: NSWindow {
    override func performClose(_ sender: Any?) {
        if let host = windowController as? DocumentWindowController { host.requestClose() }
        else { super.performClose(sender) }
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted { (windowController as? DocumentWindowController)?.firstResponderChanged(responder) }
        return accepted
    }
}

private final class DocumentDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { Theme.current.rule }
}

private final class DocumentPaneHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.current.codeBackground.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class DocumentSplitViewController: NSSplitViewController {
    var balanceOnNextLayout = false

    override func viewDidLayout() {
        super.viewDidLayout()
        guard balanceOnNextLayout, splitViewItems.count == 2, splitView.bounds.width > 0 else { return }
        balanceOnNextLayout = false
        splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
    }
}

final class DocumentPaneViewController: NSViewController {
    let document: MarkdownDocument
    let editor: EditorViewController
    private let header = DocumentPaneHeaderView()
    private let titleButton = NSButton()
    private let modifiedDot = NSTextField(labelWithString: "●")
    private var headerHeight: NSLayoutConstraint!

    init(document: MarkdownDocument, editor: EditorViewController) {
        self.document = document
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 760))
        addChild(editor)
        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.cell?.lineBreakMode = .byTruncatingMiddle
        titleButton.target = self
        titleButton.action = #selector(selectPane(_:))
        modifiedDot.font = .systemFont(ofSize: 7)
        modifiedDot.toolTip = localized("Unsaved Changes")
        let detachButton = makeButton("rectangle.on.rectangle", label: localized("Open in Separate Window"),
                                      action: #selector(detachPane(_:)))
        let closeButton = makeButton("xmark", label: localized("Close Document"), action: #selector(closePane(_:)))
        let separator = NSBox()
        separator.boxType = .separator
        for item in [header, editor.view] { item.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(item) }
        for item in [modifiedDot, titleButton, detachButton, closeButton, separator] {
            item.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(item)
        }
        headerHeight = header.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor), headerHeight,
            modifiedDot.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            modifiedDot.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            modifiedDot.widthAnchor.constraint(equalToConstant: 8),
            titleButton.leadingAnchor.constraint(equalTo: modifiedDot.trailingAnchor, constant: 4),
            titleButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleButton.trailingAnchor.constraint(equalTo: detachButton.leadingAnchor, constant: -4),
            detachButton.widthAnchor.constraint(equalToConstant: 24),
            detachButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            detachButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            editor.view.topAnchor.constraint(equalTo: header.bottomAnchor),
            editor.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            editor.view.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
    }

    func updateHeader(isSplit: Bool, isActive: Bool) {
        _ = view
        header.isHidden = !isSplit
        headerHeight.constant = isSplit ? 34 : 0
        titleButton.title = document.displayName
        titleButton.toolTip = document.fileURL?.path ?? document.displayName
        titleButton.font = .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular)
        titleButton.contentTintColor = isActive ? Theme.current.text : Theme.current.quoteText
        modifiedDot.isHidden = !document.isDocumentEdited
        modifiedDot.textColor = Theme.current.text
    }

    private func makeButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                              target: self, action: action)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    @objc private func selectPane(_ sender: Any?) { document.hostingWindowController?.activate(document) }
    @objc private func detachPane(_ sender: Any?) { document.hostingWindowController?.detach(document) }
    @objc private func closePane(_ sender: Any?) { document.hostingWindowController?.requestClose(document) }
}

private final class SplitViewButtonController: NSTitlebarAccessoryViewController {
    private weak var host: DocumentWindowController?
    private let button = NSButton()

    init(host: DocumentWindowController) {
        self.host = host
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 28))
        button.frame = NSRect(x: 2, y: 3, width: 26, height: 22)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        button.target = self
        button.action = #selector(toggleSplit(_:))
        container.addSubview(button)
        view = container
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        let label = host?.isSplit == true ? localized("Separate Documents") : localized("Open Side by Side…")
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.state = host?.isSplit == true ? .on : .off
        button.isEnabled = host?.canUseSplitButton == true
    }

    @objc private func toggleSplit(_ sender: Any?) {
        if host?.isSplit == true { host?.separateDocuments(sender) }
        else { host?.openSideBySide(sender) }
    }
}

/// Conservato dal controller della finestra anche quando canClose presenta
/// un pannello asincrono. Nessun documento viene chiuso finché tutti approvano.
private final class DocumentCloseReview: NSObject {
    private let documents: [MarkdownDocument]
    private let completion: (Bool) -> Void
    private var index = 0

    init(documents: [MarkdownDocument], completion: @escaping (Bool) -> Void) {
        self.documents = documents
        self.completion = completion
    }

    func start() { reviewNext() }

    private func reviewNext() {
        guard index < documents.count else { completion(true); return }
        documents[index].canClose(withDelegate: self,
                                  shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard shouldClose else { completion(false); return }
        index += 1
        reviewNext()
    }
}
