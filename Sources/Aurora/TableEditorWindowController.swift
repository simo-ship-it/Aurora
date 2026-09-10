import AppKit
import AuroraCore

private final class TopAlignedGridView: NSGridView {
    override var isFlipped: Bool { true }
}

/// Una piccola griglia AppKit per creare e modificare una tabella senza dover
/// contare barre verticali nel testo. Alla conferma restituisce solo Markdown.
final class TableEditorWindowController: NSWindowController {

    private var table: MarkdownTable
    private let onApply: (MarkdownTable) -> Void
    private let rowsStepper = NSStepper()
    private let columnsStepper = NSStepper()
    private let rowsValue = NSTextField(string: "")
    private let columnsValue = NSTextField(string: "")
    private let gridScroll = NSScrollView()
    private var fields: [[NSTextField]] = []

    private static let initialDataRows = 2
    private static let initialColumns = 2
    private static let maximumDimension = 12
    private static let cellWidth: CGFloat = 132
    private static let cellHeight: CGFloat = 28
    private static let gridSpacing: CGFloat = 8

    static func newTable() -> MarkdownTable {
        let headers = (1...initialColumns).map { String(format: localized("Column %d"), $0) }
        return MarkdownTable(headers: headers,
                             rows: Array(repeating: Array(repeating: "", count: initialColumns),
                                         count: initialDataRows))
    }

    init(table: MarkdownTable, onApply: @escaping (MarkdownTable) -> Void) {
        self.table = table
        self.onApply = onApply

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = localized("Table")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = buildContent()
        rebuildGrid()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func beginSheet(for parent: NSWindow, onClose: @escaping () -> Void) {
        guard let window else { return }
        parent.beginSheet(window) { _ in onClose() }
    }

    private func buildContent() -> NSView {
        configure(rowsStepper, value: Double(table.rows.count), action: #selector(rowsChanged))
        configure(columnsStepper, value: Double(table.columnCount), action: #selector(columnsChanged))
        configure(rowsValue, value: table.rows.count, action: #selector(rowsValueChanged))
        configure(columnsValue, value: table.columnCount, action: #selector(columnsValueChanged))

        let dimensions = NSStackView(views: [
            label(localized("Rows:")), rowsValue, rowsStepper,
            spacer(),
            label(localized("Columns:")), columnsValue, columnsStepper
        ])
        dimensions.orientation = .horizontal
        dimensions.spacing = 8

        gridScroll.hasVerticalScroller = true
        gridScroll.hasHorizontalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.borderType = .bezelBorder
        gridScroll.widthAnchor.constraint(equalToConstant: 600).isActive = true
        gridScroll.heightAnchor.constraint(equalToConstant: 300).isActive = true

        let cancel = NSButton(title: localized("Cancel"), target: self, action: #selector(cancel))
        let apply = NSButton(title: localized("Apply"), target: self, action: #selector(apply))
        apply.keyEquivalent = "\r"
        let actions = NSStackView(views: [spacer(), cancel, apply])
        actions.orientation = .horizontal
        actions.spacing = 8

        let stack = NSStackView(views: [dimensions, gridScroll, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        return root
    }

    private func configure(_ stepper: NSStepper, value: Double, action: Selector) {
        stepper.minValue = 1
        stepper.maxValue = Double(Self.maximumDimension)
        stepper.increment = 1
        stepper.doubleValue = value
        stepper.target = self
        stepper.action = action
    }

    private func configure(_ field: NSTextField, value: Int, action: Selector) {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = NSNumber(value: Self.maximumDimension)
        field.formatter = formatter
        field.integerValue = value
        field.alignment = .right
        field.target = self
        field.action = action
        field.widthAnchor.constraint(equalToConstant: 38).isActive = true
    }

    private func label(_ value: String) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        return field
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        return view
    }

    private func rebuildGrid() {
        let columns = table.columnCount
        var rows: [[NSView]] = []
        fields = []

        for row in 0...table.rows.count {
            var fieldRow: [NSTextField] = []
            for column in 0..<columns {
                let value = row == 0 ? table.headers[column] : table.rows[row - 1][column]
                let field = NSTextField(string: value)
                field.placeholderString = row == 0 ? String(format: localized("Column %d"), column + 1) : ""
                field.font = row == 0 ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                                 : .systemFont(ofSize: NSFont.systemFontSize)
                field.widthAnchor.constraint(equalToConstant: Self.cellWidth).isActive = true
                field.heightAnchor.constraint(equalToConstant: Self.cellHeight).isActive = true
                fieldRow.append(field)
            }
            fields.append(fieldRow)
            rows.append(fieldRow)
        }

        let grid = TopAlignedGridView(views: rows)
        grid.rowSpacing = Self.gridSpacing
        grid.columnSpacing = Self.gridSpacing
        grid.layoutSubtreeIfNeeded()
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        gridScroll.documentView = grid

        rowsStepper.doubleValue = Double(table.rows.count)
        columnsStepper.doubleValue = Double(columns)
        rowsValue.stringValue = "\(table.rows.count)"
        columnsValue.stringValue = "\(columns)"
    }

    private func readFields() {
        guard !fields.isEmpty else { return }
        table.headers = fields[0].map(\.stringValue)
        table.rows = fields.dropFirst().map { $0.map(\.stringValue) }
    }

    private func resize(rows: Int, columns: Int) {
        readFields()
        let rows = min(Self.maximumDimension, max(1, rows))
        let columns = min(Self.maximumDimension, max(1, columns))
        let previousColumns = table.columnCount
        table.resize(dataRows: rows, columns: columns)
        if columns > previousColumns {
            for index in previousColumns..<columns {
                table.headers[index] = String(format: localized("Column %d"), index + 1)
            }
        }
        rebuildGrid()
    }

    @objc private func rowsChanged() {
        resize(rows: Int(rowsStepper.doubleValue), columns: table.columnCount)
    }

    @objc private func columnsChanged() {
        resize(rows: table.rows.count, columns: Int(columnsStepper.doubleValue))
    }

    @objc private func rowsValueChanged() {
        resize(rows: rowsValue.integerValue, columns: table.columnCount)
    }

    @objc private func columnsValueChanged() {
        resize(rows: table.rows.count, columns: columnsValue.integerValue)
    }

    @objc private func cancel() {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: .cancel)
    }

    @objc private func apply() {
        readFields()
        guard let window, let parent = window.sheetParent else { return }
        let result = table
        parent.endSheet(window, returnCode: .OK)
        onApply(result)
    }
}
