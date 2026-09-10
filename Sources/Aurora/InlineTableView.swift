import AppKit
import AuroraCore

/// La rappresentazione visibile di una tabella nel documento.
///
/// Ogni cella è un vero `NSTextField`: il testo Markdown resta sotto la vista,
/// completamente nascosto, e viene aggiornato quando termina la modifica.
final class InlineTableView: NSView, NSTextFieldDelegate {

    private(set) var sourceRange: NSRange
    private(set) var table: MarkdownTable
    private let onCommit: (MarkdownTable, NSRange) -> Void
    private let onActivate: (NSRange) -> Void
    private let onMoveOutside: (NSRange, Bool) -> Void
    private var fields: [[NSTextField]] = []
    private let addRowButton = NSButton()
    private let addColumnButton = NSButton()
    private var rowHoverTrackingArea: NSTrackingArea?
    private var columnHoverTrackingArea: NSTrackingArea?

    static let rowHeight: CGFloat = 44
    static let controlGutter: CGFloat = 28
    private static let horizontalInset: CGFloat = 14
    private static let verticalInset: CGFloat = 8
    private static let addButtonSize: CGFloat = 24

    init(frame: NSRect, sourceRange: NSRange, table: MarkdownTable,
         onActivate: @escaping (NSRange) -> Void,
         onMoveOutside: @escaping (NSRange, Bool) -> Void,
         onCommit: @escaping (MarkdownTable, NSRange) -> Void) {
        self.sourceRange = sourceRange
        self.table = table
        self.onActivate = onActivate
        self.onMoveOutside = onMoveOutside
        self.onCommit = onCommit
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(localized("Table"))
        buildFields()
        configureAddButton(addRowButton, label: localized("Add Row"),
                           action: #selector(addRow))
        configureAddButton(addColumnButton, label: localized("Add Column"),
                           action: #selector(addColumn))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override var isFlipped: Bool { true }

    var isEditing: Bool {
        fields.joined().contains { $0.currentEditor() != nil }
    }

    var editedTable: MarkdownTable {
        var updated = table
        guard let header = fields.first else { return updated }
        updated.headers = header.map(\.stringValue)
        updated.rows = fields.dropFirst().map { $0.map(\.stringValue) }
        return updated
    }

    private var tableBounds: NSRect {
        bounds.insetBy(dx: Self.controlGutter, dy: 0)
    }

    private func configureAddButton(_ button: NSButton, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .circular
        button.controlSize = .small
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.alphaValue = 0
        addSubview(button)
    }

    func applyTheme() {
        for (row, fieldRow) in fields.enumerated() {
            for field in fieldRow {
                field.font = row == 0
                    ? .systemFont(ofSize: Theme.current.bodySize, weight: .semibold)
                    : Theme.current.body
                field.textColor = Theme.current.text
            }
        }
        addRowButton.contentTintColor = Theme.current.text
        addColumnButton.contentTintColor = Theme.current.text
        needsDisplay = true
    }

    private func buildFields() {
        let values = [table.headers] + table.rows
        for (row, cells) in values.enumerated() {
            var fieldRow: [NSTextField] = []
            for (column, value) in cells.enumerated() {
                let field = NSTextField(string: value)
                field.isBordered = false
                field.drawsBackground = false
                field.focusRingType = .none
                field.lineBreakMode = .byTruncatingTail
                field.font = row == 0
                    ? .systemFont(ofSize: Theme.current.bodySize, weight: .semibold)
                    : Theme.current.body
                field.textColor = Theme.current.text
                field.delegate = self
                field.tag = row * max(1, table.columnCount) + column
                field.setAccessibilityLabel(row == 0
                    ? String(format: localized("Column %d"), column + 1)
                    : String(format: localized("Row %d, column %d"), row, column + 1))
                addSubview(field)
                fieldRow.append(field)
            }
            fields.append(fieldRow)
        }

        let ordered = fields.flatMap { $0 }
        for (current, next) in zip(ordered, ordered.dropFirst()) {
            current.nextKeyView = next
        }
        applyTheme()
    }

    override func layout() {
        super.layout()
        let tableBounds = tableBounds
        let columns = max(1, table.columnCount)
        let columnWidth = tableBounds.width / CGFloat(columns)
        for (row, fieldRow) in fields.enumerated() {
            for (column, field) in fieldRow.enumerated() {
                field.frame = NSRect(
                    x: tableBounds.minX + CGFloat(column) * columnWidth + Self.horizontalInset,
                    y: CGFloat(row) * Self.rowHeight + Self.verticalInset,
                    width: max(0, columnWidth - Self.horizontalInset * 2),
                    height: Self.rowHeight - Self.verticalInset * 2)
            }
        }

        let buttonSize = Self.addButtonSize
        addColumnButton.frame = NSRect(x: tableBounds.maxX - buttonSize / 2,
                                       y: (Self.rowHeight - buttonSize) / 2,
                                       width: buttonSize, height: buttonSize)
        addRowButton.frame = NSRect(x: tableBounds.minX - buttonSize / 2,
                                    y: tableBounds.maxY - Self.rowHeight / 2 - buttonSize / 2,
                                    width: buttonSize, height: buttonSize)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowHoverTrackingArea { removeTrackingArea(rowHoverTrackingArea) }
        if let columnHoverTrackingArea { removeTrackingArea(columnHoverTrackingArea) }

        let tableBounds = tableBounds
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        let rowArea = NSTrackingArea(
            rect: NSRect(x: tableBounds.minX - Self.controlGutter,
                         y: tableBounds.maxY - Self.rowHeight,
                         width: Self.controlGutter * 2, height: Self.rowHeight),
            options: options, owner: self, userInfo: nil)
        let columnArea = NSTrackingArea(
            rect: NSRect(x: tableBounds.maxX - Self.controlGutter,
                         y: tableBounds.minY,
                         width: Self.controlGutter * 2, height: Self.rowHeight),
            options: options, owner: self, userInfo: nil)
        addTrackingArea(rowArea)
        addTrackingArea(columnArea)
        rowHoverTrackingArea = rowArea
        columnHoverTrackingArea = columnArea
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === rowHoverTrackingArea { addRowButton.alphaValue = 1 }
        if event.trackingArea === columnHoverTrackingArea { addColumnButton.alphaValue = 1 }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === rowHoverTrackingArea { addRowButton.alphaValue = 0 }
        if event.trackingArea === columnHoverTrackingArea { addColumnButton.alphaValue = 0 }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let tableBounds = tableBounds
        Theme.current.codeBackground.setFill()
        NSBezierPath(roundedRect: tableBounds,
                     xRadius: Theme.current.surfaceRadius,
                     yRadius: Theme.current.surfaceRadius).fill()

        Theme.current.rule.withAlphaComponent(0.42).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        let columns = max(1, table.columnCount)
        let columnWidth = tableBounds.width / CGFloat(columns)
        for column in 1..<columns {
            let x = (tableBounds.minX + CGFloat(column) * columnWidth).rounded() + 0.5
            path.move(to: NSPoint(x: x, y: tableBounds.minY + 8))
            path.line(to: NSPoint(x: x, y: tableBounds.maxY - 8))
        }
        let visibleRows = table.rows.count + 1
        for row in 1..<visibleRows {
            let y = (tableBounds.minY + CGFloat(row) * Self.rowHeight).rounded() + 0.5
            path.move(to: NSPoint(x: tableBounds.minX + 8, y: y))
            path.line(to: NSPoint(x: tableBounds.maxX - 8, y: y))
        }
        path.stroke()
    }

    @objc private func addRow() {
        var updated = editedTable
        updated.resize(dataRows: updated.rows.count + 1, columns: updated.columnCount)
        commit(updated, rebuildView: true)
    }

    @objc private func addColumn() {
        var updated = editedTable
        let previousColumns = updated.columnCount
        updated.resize(dataRows: updated.rows.count, columns: previousColumns + 1)
        updated.headers[previousColumns] = String(format: localized("Column %d"), previousColumns + 1)
        commit(updated, rebuildView: true)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        // Il field editor condiviso della finestra, per impostazione predefinita,
        // salta la gerarchia della cella nella responder chain. Ricollegandolo
        // qui, i comandi Formato continuano a raggiungere `MarkdownTextView`.
        if let field = notification.object as? NSTextField,
           let editor = field.currentEditor() {
            editor.nextResponder = self
        }
        onActivate(sourceRange)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitChanges()
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField else { return false }
        let columns = max(1, table.columnCount)
        let row = field.tag / columns
        let lastRow = max(0, fields.count - 1)
        let lastField = max(0, fields.flatMap { $0 }.count - 1)

        let moveBefore = (commandSelector == #selector(NSResponder.moveUp(_:)) && row == 0)
            || (commandSelector == #selector(NSResponder.insertBacktab(_:)) && field.tag == 0)
        let moveAfter = (commandSelector == #selector(NSResponder.moveDown(_:)) && row == lastRow)
            || (commandSelector == #selector(NSResponder.insertTab(_:)) && field.tag == lastField)
        guard moveBefore || moveAfter else { return false }

        commitChanges()
        onMoveOutside(sourceRange, moveBefore)
        return true
    }

    private func commitChanges() {
        commit(editedTable)
    }

    private func commit(_ updated: MarkdownTable, rebuildView: Bool = false) {
        guard updated != table else { return }

        // Il testo Markdown può cambiare lunghezza a ogni cella. Conservare il
        // vecchio intervallo corromperebbe la tabella alla modifica successiva
        // prima che la vista venga ricostruita (per esempio usando Tab).
        let replacedRange = sourceRange
        onCommit(updated, replacedRange)
        sourceRange.length = updated.markdown.utf16.count
        // Durante l'editing le stesse celle mostrano già i nuovi valori e vanno
        // mantenute vive. Se cambiano righe o colonne, lasciare invece il vecchio
        // modello forza `MarkdownTextView` a ricostruire subito la griglia.
        if !rebuildView { table = updated }
        onActivate(sourceRange)
    }
}
