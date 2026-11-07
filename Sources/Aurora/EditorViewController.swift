import AppKit
import AuroraCore

/// Contiene l'area di scrittura in una colonna centrata. Tenendo premuto ⌥
/// compaiono due guide che ne permettono il ridimensionamento simmetrico.
final class EditorViewController: NSViewController, NSTextViewDelegate {

    private(set) var textView: MarkdownTextView!
    private var scrollView: NSScrollView!
    private let columnWidthOverlay = ColumnWidthOverlayView()
    private var flagsMonitor: Any?
    private var previewContentWidth: CGFloat?
    private var theme: Theme { Theme.current }

    weak var document: MarkdownDocument?
    var onTextChange: (() -> Void)?

    override func loadView() {
        // Stack TextKit 1: serve il layout manager per nascondere i glifi della sintassi.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.allowsNonContiguousLayout = false

        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                                    textContainer: container)
        textView.owningDocument = document
        textView.delegate = self
        textView.configure()

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        let root = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        columnWidthOverlay.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        root.addSubview(columnWidthOverlay)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            columnWidthOverlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            columnWidthOverlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            columnWidthOverlay.topAnchor.constraint(equalTo: root.topAnchor),
            columnWidthOverlay.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        columnWidthOverlay.onWidthPreview = { [weak self] width in
            self?.previewContentWidth = width
            self?.updateContentInsets()
        }
        columnWidthOverlay.onWidthCommit = { [weak self] width in
            guard let self else { return }
            self.previewContentWidth = nil
            if abs(Settings.shared.contentWidth - width) > 0.5 {
                Settings.shared.contentWidth = width
            } else {
                self.updateContentInsets()
            }
        }
        view = root

        NotificationCenter.default.addObserver(
            self, selector: #selector(visibleAreaChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .auroraThemeChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification, object: nil)

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            guard let self, self.view.window?.isKeyWindow == true else { return event }
            self.columnWidthOverlay.setOptionHeld(event.modifierFlags.contains(.option))
            return event
        }
    }

    @objc private func visibleAreaChanged() {
        textView.styler.restyleVisible()
    }

    /// Le impostazioni sono cambiate: font, misure e colori vanno riapplicati a
    /// tutto il documento, non solo alla parte visibile, perché l'altezza delle
    /// righe fuori campo decide dove ci si trova scorrendo.
    @objc private func themeChanged() {
        scrollView.backgroundColor = theme.background
        view.window?.backgroundColor = theme.background
        textView.applyTheme()
        updateContentInsets()
        textView.styler.invalidateCache()
        textView.styler.restyleAll()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        guard notification.object as? NSWindow === view.window,
              !columnWidthOverlay.isInteracting else { return }
        columnWidthOverlay.setOptionHeld(false)
    }

    deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        synchronizeDocumentWidth()
        updateContentInsets()
    }

    /// `NSScrollView` non forza sempre il `documentView` a seguire la propria
    /// larghezza durante lo zoom della finestra. Il contenitore di testo e le
    /// viste in linea (incluse le tabelle) dipendono invece proprio da questa
    /// misura, quindi la teniamo esplicitamente sincronizzata.
    private func synchronizeDocumentWidth() {
        let size = scrollView.contentSize
        guard size.width > 0, abs(textView.frame.width - size.width) > 0.5 else { return }
        textView.setFrameSize(NSSize(width: size.width,
                                     height: max(textView.frame.height, size.height)))
    }

    private func updateContentInsets() {
        let available = scrollView.contentSize.width
        let preferred = previewContentWidth ?? theme.maxContentWidth
        let content = min(preferred, max(0, available - theme.minSideMargin * 2))
        let horizontal = max(theme.minSideMargin, (available - content) / 2)
        let inset = NSSize(width: horizontal, height: theme.topInset)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
            textView.contentInsetsDidChange()
        }
        columnWidthOverlay.availableWidth = available
        columnWidthOverlay.preferredWidth = preferred
        columnWidthOverlay.minimumSideMargin = theme.minSideMargin
    }

    // MARK: - Contenuto

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            textView.styler.invalidateCache()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.styler.restyleAll()
            textView.undoManager?.removeAllActions()
        }
    }

    /// Aggiorna un file cambiato fuori da Aurora senza riportare l'utente
    /// all'inizio del documento. La selezione viene ridotta se il nuovo file
    /// è più corto, così resta sempre un intervallo valido.
    func replaceTextPreservingViewState(with newValue: String) {
        let selection = textView.selectedRange()
        let visibleOrigin = scrollView.contentView.bounds.origin

        textView.string = newValue
        textView.styler.invalidateCache()
        let location = min(selection.location, (newValue as NSString).length)
        let length = min(selection.length, (newValue as NSString).length - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
        textView.styler.restyleAll()
        textView.undoManager?.removeAllActions()

        // Il layout viene aggiornato nel ciclo corrente; rimandare lo scroll
        // di un passaggio evita che AppKit lo limiti usando l'altezza vecchia.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollView.contentView.scroll(to: visibleOrigin)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? {
        document?.undoManager
    }

    func textDidChange(_ notification: Notification) {
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView.normalizeSelectionOutsideTables()
        textView.styler.selectionChanged()
    }
}
