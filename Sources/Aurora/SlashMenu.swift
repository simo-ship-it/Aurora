import AppKit
import AuroraCore

/// Una voce del menu che si apre digitando "/".
///
/// Ogni voce rimanda a un comando che esiste già nell'editor: il menu è una
/// scorciatoia per raggiungerli scrivendo, non una seconda implementazione.
struct SlashCommand {

    let title: String
    /// La sintassi Markdown che la voce produce. Serve da promemoria e da
    /// secondo criterio di ricerca: chi la conosce può digitarla direttamente.
    let hint: String
    let symbol: String
    let action: Selector
    let tag: Int

    /// Il titolo arriva in inglese e viene tradotto qui: `matches` confronta
    /// così la scritta che l'utente ha davvero davanti, e la ricerca funziona
    /// nella lingua in cui il menu è mostrato.
    init(_ title: String, _ hint: String, _ symbol: String, _ action: Selector, tag: Int = 0) {
        self.title = localized(title)
        self.hint = hint
        self.symbol = symbol
        self.action = action
        self.tag = tag
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return title.range(of: query, options: options) != nil
            || hint.range(of: query, options: options) != nil
    }

    private static let heading = #selector(MarkdownTextView.setHeadingLevel(_:))

    static let all: [SlashCommand] = [
        SlashCommand("Heading 1", "#", "textformat.size.larger", heading, tag: 1),
        SlashCommand("Heading 2", "##", "textformat.size", heading, tag: 2),
        SlashCommand("Heading 3", "###", "textformat.size.smaller", heading, tag: 3),
        SlashCommand("Heading 4", "####", "textformat.size.smaller", heading, tag: 4),
        SlashCommand("Heading 5", "#####", "textformat.size.smaller", heading, tag: 5),
        SlashCommand("Heading 6", "######", "textformat.size.smaller", heading, tag: 6),
        SlashCommand("Paragraph", localized("plain text"), "text.alignleft", heading, tag: 0),
        SlashCommand("Bulleted List", "-", "list.bullet",
                     #selector(MarkdownTextView.toggleBulletList(_:))),
        SlashCommand("Task List", "- [ ]", "checklist",
                     #selector(MarkdownTextView.toggleTaskList(_:))),
        SlashCommand("Blockquote", ">", "text.quote",
                     #selector(MarkdownTextView.toggleBlockquote(_:))),
        SlashCommand("Code Block", "```", "curlybraces",
                     #selector(MarkdownTextView.insertCodeBlock(_:))),
        SlashCommand("Horizontal Rule", "---", "minus",
                     #selector(MarkdownTextView.insertHorizontalRule(_:))),
        SlashCommand("Link", localized("[text](url)"), "link",
                     #selector(MarkdownTextView.insertLink(_:))),
        SlashCommand("Bold", "**", "bold",
                     #selector(MarkdownTextView.toggleBold(_:))),
        SlashCommand("Italic", "*", "italic",
                     #selector(MarkdownTextView.toggleItalic(_:))),
        SlashCommand("Strikethrough", "~~", "strikethrough",
                     #selector(MarkdownTextView.toggleStrikethrough(_:))),
        SlashCommand("Highlight", "==", "highlighter",
                     #selector(MarkdownTextView.toggleHighlight(_:))),
        SlashCommand("Inline Code", "`", "chevron.left.forwardslash.chevron.right",
                     #selector(MarkdownTextView.toggleInlineCode(_:)))
    ]
}

/// Pannello che non diventa mai chiave: mentre è aperto continui a scrivere nel
/// testo, e i tasti di navigazione restano da gestire all'editor.
private final class SlashPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Sfondo stondato del pannello.
private final class SlashBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let theme = Theme.current
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: 10, yRadius: 10)
        theme.background.setFill()
        shape.fill()
        theme.rule.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}

/// Riga evidenziata con l'accento dell'app invece del blu di sistema.
private final class SlashRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1),
                                 xRadius: 6, yRadius: 6)
        Theme.current.accent.withAlphaComponent(0.18).setFill()
        shape.fill()
    }
}

/// Tabella che riporta la riga cliccata: dentro un pannello senza fuoco
/// `target/action` non è affidabile.
private final class SlashTable: NSTableView {
    var onClickRow: ((Int) -> Void)?

    /// Il pannello non diventa mai chiave, quindi per AppKit ogni clic è un
    /// "primo clic": senza questo, la tabella li rifiuterebbe tutti.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let index = row(at: point)
        if index >= 0 { onClickRow?(index) }
    }
}

final class SlashMenuController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    var onPick: ((SlashCommand) -> Void)?

    private let panel = SlashPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
    private let table = SlashTable()
    private var shown: [SlashCommand] = []
    private var theme: Theme { Theme.current }

    private static let rowHeight: CGFloat = 32
    private static let width: CGFloat = 300
    private static let padding: CGFloat = 8
    private static let maxVisibleRows = 8

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        build()
    }

    private func build() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("voce"))
        column.width = Self.width - Self.padding * 2
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.backgroundColor = .clear
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.onClickRow = { [weak self] row in self?.pick(row) }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let background = SlashBackground()
        background.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.padding),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.padding),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.padding),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.padding)
        ])
        panel.contentView = background
    }

    // MARK: - Comparsa e aggiornamento

    /// Mostra o aggiorna il menu. Restituisce `false` se nessun comando
    /// corrisponde: chi chiama lo prende come segnale per chiudere.
    @discardableResult
    func present(query: String, below caret: NSRect, in host: NSWindow?) -> Bool {
        shown = SlashCommand.all.filter { $0.matches(query) }
        guard !shown.isEmpty else { return false }

        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        let rows = min(shown.count, Self.maxVisibleRows)
        let height = CGFloat(rows) * Self.rowHeight + Self.padding * 2
        var frame = NSRect(x: caret.minX, y: caret.minY - height - 6,
                           width: Self.width, height: height)

        if let screen = host?.screen ?? NSScreen.main {
            let limits = screen.visibleFrame
            frame.origin.x = min(max(limits.minX + 8, frame.origin.x), limits.maxX - Self.width - 8)
            // Se sotto non ci sta, il menu si apre sopra il cursore.
            if frame.minY < limits.minY + 8 { frame.origin.y = caret.maxY + 6 }
        }
        panel.setFrame(frame, display: true)

        if !panel.isVisible {
            host?.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
        return true
    }

    func dismiss() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveSelection(by delta: Int) {
        guard !shown.isEmpty else { return }
        let current = table.selectedRow < 0 ? 0 : table.selectedRow
        let next = min(max(0, current + delta), shown.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    func confirmSelection() {
        pick(table.selectedRow)
    }

    private func pick(_ row: Int) {
        guard row >= 0, row < shown.count else { return }
        onPick?(shown[row])
    }

    // MARK: - Elenco

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SlashRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("voce")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let icon = NSImageView()
            let title = NSTextField(labelWithString: "")
            let hint = NSTextField(labelWithString: "")
            for view in [icon, title, hint] { view.translatesAutoresizingMaskIntoConstraints = false }
            hint.alignment = .right
            hint.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            cell.addSubview(icon)
            cell.addSubview(title)
            cell.addSubview(hint)
            cell.imageView = icon
            cell.textField = title

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                hint.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
                hint.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                hint.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.viewWithTag(0)?.identifier = nil
            hint.identifier = NSUserInterfaceItemIdentifier("promemoria")
        }

        let command = shown[row]
        cell.imageView?.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = theme.quoteText
        cell.textField?.stringValue = command.title
        cell.textField?.font = .systemFont(ofSize: 13)
        cell.textField?.textColor = theme.text
        if let hint = cell.subviews.compactMap({ $0 as? NSTextField })
            .first(where: { $0.identifier?.rawValue == "promemoria" }) {
            hint.stringValue = command.hint
            hint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            hint.textColor = theme.quoteText
        }
        return cell
    }
}
