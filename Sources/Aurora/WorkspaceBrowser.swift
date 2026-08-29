import AppKit

/// Il pulsante a forma di cartella in barra del titolo: apre l'albero della
/// cartella di lavoro.
final class WorkspaceButtonController: NSTitlebarAccessoryViewController {

    private let button = NSButton()
    private let popover = NSPopover()

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func loadView() {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: "folder",
                               accessibilityDescription: "Cartella di lavoro")
        button.imagePosition = .imageOnly
        button.contentTintColor = Theme.current.quoteText
        button.toolTip = "File della cartella di lavoro"
        button.target = self
        button.action = #selector(toggle(_:))
        button.translatesAutoresizingMaskIntoConstraints = false

        // L'accessorio della barra del titolo viene dimensionato da AppKit a
        // partire dal frame: le costanti di larghezza sul contenitore verrebbero
        // annullate dalla maschera di ridimensionamento.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        view = container
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        let browser = WorkspaceBrowserViewController()
        browser.onOpenDocument = { [weak self] in self?.popover.performClose(nil) }
        popover.contentViewController = browser
        popover.behavior = .transient
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

/// Una voce dell'albero. I figli si leggono dal disco solo quando la cartella
/// viene aperta: un albero profondo non costa niente finché resta chiuso.
final class WorkspaceNode: NSObject {

    let url: URL
    let isFolder: Bool

    private var loaded = false
    private var cached: [WorkspaceNode] = []

    init(url: URL, isFolder: Bool) {
        self.url = url
        self.isFolder = isFolder
    }

    var name: String { url.lastPathComponent }

    // Due nodi sono lo stesso nodo se puntano allo stesso percorso, anche se
    // costruiti in momenti diversi.
    override func isEqual(_ object: Any?) -> Bool {
        (object as? WorkspaceNode)?.url == url
    }

    override var hash: Int { url.hashValue }

    var children: [WorkspaceNode] {
        guard isFolder else { return [] }
        if !loaded {
            cached = WorkspaceNode.contents(of: url)
            loaded = true
        }
        return cached
    }

    /// Cartelle prima, poi i file leggibili, entrambi in ordine alfabetico.
    static func contents(of folder: URL) -> [WorkspaceNode] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var folders: [WorkspaceNode] = []
        var files: [WorkspaceNode] = []
        for url in items {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                folders.append(WorkspaceNode(url: url, isFolder: true))
            } else if Workspace.readableExtensions.contains(url.pathExtension.lowercased()) {
                files.append(WorkspaceNode(url: url, isFolder: false))
            }
        }
        let byName: (WorkspaceNode, WorkspaceNode) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return folders.sorted(by: byName) + files.sorted(by: byName)
    }
}

/// Riporta la riga cliccata invece di affidarsi a `target/action`, che dentro
/// un popover non arriva in modo affidabile. Il clic sul triangolo di apertura
/// resta ad AppKit, altrimenti la cartella verrebbe aperta e richiusa subito.
final class WorkspaceOutlineView: NSOutlineView {

    var onClickRow: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let index = row(at: point)
        guard index >= 0 else { return }
        if NSPointInRect(point, frameOfOutlineCell(atRow: index)) { return }
        onClickRow?(index)
    }
}

/// L'albero dentro il popover: un clic su una cartella la apre sul posto,
/// un clic su un file lo apre nell'editor.
final class WorkspaceBrowserViewController: NSViewController,
                                            NSOutlineViewDataSource, NSOutlineViewDelegate {

    var onOpenDocument: (() -> Void)?

    private var roots: [WorkspaceNode] = []
    private var isRestoring = false
    private let header = NSButton()
    private let outline = WorkspaceOutlineView()
    private let placeholder = NSTextField(labelWithString: "")
    private var theme: Theme { Theme.current }

    private static let size = NSSize(width: 300, height: 420)

    override func loadView() {
        // La radice tiene la maschera di ridimensionamento e un frame vero:
        // con il frame a zero i sottoinsiemi si disegnerebbero lo stesso, ma il
        // hit-testing del mouse cadrebbe fuori dai bounds e non li raggiungerebbe.
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))

        // Il nome della cartella è anche il modo per cambiarla: il doppio
        // chevron è il segnale che macOS usa per "premi per scegliere".
        header.isBordered = false
        header.image = NSImage(systemSymbolName: "chevron.up.chevron.down",
                               accessibilityDescription: nil)
        header.imagePosition = .imageRight
        header.imageHugsTitle = true
        header.alignment = .left
        header.contentTintColor = theme.quoteText
        header.toolTip = "Scegli la cartella di lavoro"
        header.target = self
        header.action = #selector(chooseFolder(_:))
        header.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("voce"))
        column.resizingMask = .autoresizingMask
        column.width = Self.size.width - 16
        column.minWidth = 80
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 28
        outline.indentationPerLevel = 14
        outline.indentationMarkerFollowsCell = true
        outline.backgroundColor = .clear
        outline.style = .inset
        outline.selectionHighlightStyle = .regular
        outline.autoresizingMask = [.width]
        outline.dataSource = self
        outline.delegate = self
        outline.onClickRow = { [weak self] row in self?.activateRow(row) }

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textColor = theme.quoteText
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        for subview in [header, separator, scroll, placeholder] {
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),

            placeholder.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            placeholder.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20)
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = Self.size
        reload()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    private func reload() {
        let workspace = Workspace.shared
        roots = workspace.folder.map(WorkspaceNode.contents(of:)) ?? []

        setHeaderTitle(workspace.folder?.lastPathComponent ?? "Nessuna cartella")
        if workspace.folder == nil {
            placeholder.stringValue = "Premi il nome qui sopra per scegliere una cartella."
        } else if roots.isEmpty {
            placeholder.stringValue = "Questa cartella non contiene documenti Markdown."
        } else {
            placeholder.stringValue = ""
        }
        placeholder.isHidden = placeholder.stringValue.isEmpty
        outline.reloadData()
        restoreExpansion()
    }

    /// Riapre le cartelle che erano aperte, dai genitori ai figli: una cartella
    /// annidata esiste nell'albero solo dopo che il suo genitore è stato aperto.
    private func restoreExpansion() {
        isRestoring = true
        defer { isRestoring = false }

        var queue = roots
        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard node.isFolder, Workspace.shared.isExpanded(node.url) else { continue }
            outline.expandItem(node)
            queue.append(contentsOf: node.children)
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isRestoring, let node = notification.userInfo?["NSObject"] as? WorkspaceNode else { return }
        Workspace.shared.setExpanded(true, for: node.url)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isRestoring, let node = notification.userInfo?["NSObject"] as? WorkspaceNode else { return }
        Workspace.shared.setExpanded(false, for: node.url)
    }

    private func setHeaderTitle(_ title: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        header.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: theme.text,
            .paragraphStyle: paragraph
        ])
    }

    @objc private func chooseFolder(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openFolder(sender)
    }

    // MARK: - Albero

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? WorkspaceNode else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? WorkspaceNode else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? WorkspaceNode)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? WorkspaceNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("voce")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(icon)
            cell.addSubview(label)
            cell.imageView = icon
            cell.textField = label

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.imageView?.image = NSImage(systemSymbolName: node.isFolder ? "folder" : "doc.text",
                                        accessibilityDescription: nil)
        cell.imageView?.contentTintColor = theme.quoteText
        cell.textField?.stringValue = node.name
        cell.textField?.font = .systemFont(ofSize: 13)
        cell.textField?.textColor = theme.text
        return cell
    }

    private func activateRow(_ row: Int) {
        guard let node = outline.item(atRow: row) as? WorkspaceNode else { return }

        if node.isFolder {
            if outline.isItemExpanded(node) {
                outline.collapseItem(node)
            } else {
                outline.expandItem(node)
            }
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: node.url, display: true) { _, _, _ in }
        onOpenDocument?()
    }
}
