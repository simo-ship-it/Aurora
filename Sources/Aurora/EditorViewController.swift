import AppKit
import AuroraCore

/// Contiene l'area di scrittura: colonna centrata a larghezza fissa, come in Typora.
final class EditorViewController: NSViewController, NSTextViewDelegate {

    /// La misura con cui si apre una finestra nuova. Sta qui e non nella
    /// finestra perché è una scelta sul testo: quanto ne sta sotto gli occhi.
    static let preferredSize = NSSize(width: 900, height: 760)

    private(set) var textView: MarkdownTextView!
    private var scrollView: NSScrollView!
    private var theme: Theme { Theme.current }

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
        textView.configure()
        textView.delegate = self

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

        view = scrollView

        NotificationCenter.default.addObserver(
            self, selector: #selector(visibleAreaChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .auroraThemeChanged, object: nil)
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateContentInsets()
    }

    private func updateContentInsets() {
        let available = scrollView.contentSize.width
        let content = min(theme.maxContentWidth, available - theme.minSideMargin * 2)
        let horizontal = max(theme.minSideMargin, (available - content) / 2)
        let inset = NSSize(width: horizontal, height: theme.topInset)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
            textView.needsDisplay = true
        }
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

    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView.styler.selectionChanged()
    }
}
