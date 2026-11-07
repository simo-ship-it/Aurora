import AppKit

/// Il pulsante a forma di cartella in barra del titolo: apre l'albero della
/// cartella di lavoro.
final class WorkspaceButtonController: NSTitlebarAccessoryViewController {

    private let button = NSButton()
    private let finderButton = NSButton()
    private let claudeButton = NSButton()
    private let chatGPTButton = NSButton()
    private let popover = NSPopover()

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
        NotificationCenter.default.addObserver(
            self, selector: #selector(workspaceChanged),
            name: .auroraWorkspaceChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        configure(button, symbol: "folder", label: localized("Working folder"),
                  action: #selector(toggle(_:)))
        button.toolTip = localized("Files in the working folder")
        configure(finderButton, symbol: "finder", fallback: "folder.fill",
                  label: localized("Open Working Folder in Finder"),
                  action: #selector(openInFinder(_:)))
        configure(claudeButton, symbol: "sparkles",
                  label: localized("Open Working Folder in Claude Cowork"),
                  action: #selector(openInClaudeCowork(_:)))
        configure(chatGPTButton, symbol: "bubble.left.and.bubble.right",
                  label: localized("Open Working Folder in ChatGPT"),
                  action: #selector(openInChatGPT(_:)))

        let buttons = NSStackView(views: [button, finderButton, claudeButton, chatGPTButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false

        // L'accessorio della barra del titolo viene dimensionato da AppKit a
        // partire dal frame: le costanti di larghezza sul contenitore verrebbero
        // annullate dalla maschera di ridimensionamento.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 116, height: 28))
        container.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            buttons.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 22),
            finderButton.widthAnchor.constraint(equalToConstant: 26),
            finderButton.heightAnchor.constraint(equalToConstant: 22),
            claudeButton.widthAnchor.constraint(equalToConstant: 26),
            claudeButton.heightAnchor.constraint(equalToConstant: 22),
            chatGPTButton.widthAnchor.constraint(equalToConstant: 26),
            chatGPTButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        view = container
        updateAvailability()
    }

    private func configure(_ button: NSButton, symbol: String, fallback: String? = nil,
                           label: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            ?? fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: label) }
        button.imagePosition = .imageOnly
        button.contentTintColor = Theme.current.quoteText
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
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

    @objc private func openInFinder(_ sender: Any?) {
        guard let folder = Workspace.shared.folder else { NSSound.beep(); return }
        NSWorkspace.shared.open(folder)
    }

    @objc private func openInClaudeCowork(_ sender: Any?) {
        guard let folder = Workspace.shared.folder else { NSSound.beep(); return }
        var link = URLComponents()
        link.scheme = "claude"
        link.host = "cowork"
        link.path = "/new"
        link.queryItems = [URLQueryItem(name: "folder", value: folder.path)]
        guard let url = link.url else { NSSound.beep(); return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openInChatGPT(_ sender: Any?) {
        guard let folder = Workspace.shared.folder else { NSSound.beep(); return }
        ChatGPTLauncher.open(folder: folder)
    }

    @objc private func workspaceChanged() {
        updateAvailability()
    }

    private func updateAvailability() {
        guard isViewLoaded else { return }
        let hasFolder = Workspace.shared.folder != nil
        finderButton.isEnabled = hasFolder
        let cowork = URL(string: "claude://cowork/new")
        let hasClaude = cowork.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } != nil
        claudeButton.isEnabled = hasFolder && hasClaude
        chatGPTButton.isEnabled = hasFolder && ChatGPTLauncher.isAvailable
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
    var makeContextMenu: ((Int?) -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let index = row(at: point)
        guard index >= 0 else { return }
        if NSPointInRect(point, frameOfOutlineCell(atRow: index)) { return }
        onClickRow?(index)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = row(at: point)
        return makeContextMenu?(index >= 0 ? index : nil) ?? super.menu(for: event)
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
    private let actionsButton = NSButton()
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
        header.toolTip = localized("Choose the working folder")
        header.target = self
        header.action = #selector(chooseFolder(_:))
        header.translatesAutoresizingMaskIntoConstraints = false

        actionsButton.isBordered = false
        actionsButton.bezelStyle = .regularSquare
        actionsButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                      accessibilityDescription: localized("File actions"))
        actionsButton.imagePosition = .imageOnly
        actionsButton.contentTintColor = theme.quoteText
        actionsButton.toolTip = localized("File actions")
        actionsButton.setAccessibilityLabel(localized("File actions"))
        actionsButton.target = self
        actionsButton.action = #selector(showActions(_:))
        actionsButton.translatesAutoresizingMaskIntoConstraints = false

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
        outline.makeContextMenu = { [weak self] row in
            self?.makeContextMenu(at: row)
        }

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

        for subview in [header, actionsButton, separator, scroll, placeholder] {
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: actionsButton.leadingAnchor, constant: -4),

            actionsButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            actionsButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            actionsButton.widthAnchor.constraint(equalToConstant: 24),
            actionsButton.heightAnchor.constraint(equalToConstant: 22),

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(workspaceContentsChanged),
            name: .auroraWorkspaceContentsChanged, object: nil)
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    private func reload() {
        let workspace = Workspace.shared
        roots = workspace.folder.map(WorkspaceNode.contents(of:)) ?? []

        setHeaderTitle(workspace.folder?.lastPathComponent ?? localized("No Folder"))
        if workspace.folder == nil {
            placeholder.stringValue = localized("Click the name above to choose a folder.")
        } else if roots.isEmpty {
            placeholder.stringValue = localized("This folder contains no Markdown documents.")
        } else {
            placeholder.stringValue = ""
        }
        placeholder.isHidden = placeholder.stringValue.isEmpty
        outline.reloadData()
        restoreExpansion()
    }

    @objc private func workspaceContentsChanged() {
        reload()
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

    @objc private func showActions(_ sender: Any?) {
        let row = outline.selectedRow
        guard let menu = makeContextMenu(at: row >= 0 ? row : nil) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: actionsButton.bounds.height),
                   in: actionsButton)
    }

    private func makeContextMenu(at row: Int?) -> NSMenu? {
        guard let workspaceFolder = Workspace.shared.folder else { return nil }
        let node = row.flatMap { outline.item(atRow: $0) as? WorkspaceNode }
        if let row {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        let parent = node?.isFolder == true ? node!.url : node?.url.deletingLastPathComponent()
            ?? workspaceFolder
        let menu = NSMenu()
        addMenuItem(localized("New Folder"), #selector(createFolder(_:)), parent,
                    symbol: "folder.badge.plus", to: menu)
        guard let node else { return menu }

        menu.addItem(.separator())
        addMenuItem(localized("Rename…"), #selector(renameItem(_:)), node.url,
                    symbol: "pencil", to: menu)
        addMenuItem(localized("Move To…"), #selector(moveItem(_:)), node.url,
                    symbol: "folder", to: menu)
        addMenuItem(localized("Copy"), #selector(copyItem(_:)), node.url,
                    symbol: "doc.on.doc", to: menu)
        addMenuItem(localized("Duplicate"), #selector(duplicateItem(_:)), node.url,
                    symbol: "plus.square.on.square", to: menu)
        menu.addItem(.separator())
        addMenuItem(localized("Delete"), #selector(deleteItem(_:)), node.url,
                    symbol: "trash", to: menu)
        return menu
    }

    private func addMenuItem(_ title: String, _ action: Selector, _ object: URL,
                             symbol: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = object
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        menu.addItem(item)
    }

    @objc private func createFolder(_ sender: NSMenuItem) {
        guard let parent = sender.representedObject as? URL else { return }
        askForName(title: localized("New Folder"), defaultName: localized("New Folder"),
                   confirmation: localized("Create")) { [weak self] name in
            self?.performFileOperation {
                try WorkspaceFileOperations.shared.createFolder(named: name, in: parent)
            }
        }
    }

    @objc private func renameItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL else { return }
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        askForName(title: localized("Rename…"), defaultName: source.lastPathComponent,
                   confirmation: localized("Rename…")) { [weak self] proposedName in
            var name = proposedName
            if !isFolder, URL(fileURLWithPath: name).pathExtension.isEmpty,
               !source.pathExtension.isEmpty {
                name += "." + source.pathExtension
            }
            self?.performFileOperation {
                try WorkspaceFileOperations.shared.rename(source, to: name, isFolder: isFolder)
            }
        }
    }

    @objc private func moveItem(_ sender: NSMenuItem) {
        chooseDestination(for: sender, prompt: localized("Move To…")) { [weak self] source, destination in
            self?.performFileOperation {
                try WorkspaceFileOperations.shared.move([source], to: destination)
            }
        }
    }

    @objc private func copyItem(_ sender: NSMenuItem) {
        chooseDestination(for: sender, prompt: localized("Copy")) { [weak self] source, destination in
            self?.performFileOperation {
                try WorkspaceFileOperations.shared.copy([source], to: destination)
            }
        }
    }

    @objc private func duplicateItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL else { return }
        performFileOperation {
            try WorkspaceFileOperations.shared.duplicate([source])
        }
    }

    @objc private func deleteItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL else { return }
        performFileOperation {
            try WorkspaceFileOperations.shared.delete([source])
        }
    }

    private func chooseDestination(for sender: NSMenuItem, prompt: String,
                                   completion: @escaping (URL, URL) -> Void) {
        guard let source = sender.representedObject as? URL, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = localized("Choose the destination folder.")
        panel.directoryURL = source.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            completion(source, destination)
        }
    }

    private func askForName(title: String, defaultName: String, confirmation: String,
                            completion: @escaping (String) -> Void) {
        guard let window = view.window else { return }
        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = localized("Choose a name.")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: confirmation)
        alert.addButton(withTitle: localized("Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                NSSound.beep()
                self?.askForName(title: title, defaultName: field.stringValue,
                                 confirmation: confirmation, completion: completion)
                return
            }
            completion(name)
        }
    }

    private func performFileOperation(_ operation: () throws -> Void) {
        do {
            try operation()
            reload()
        } catch let error as WorkspaceFileOperationError {
            showError(error.localizedDescription)
        } catch {
            NSApp.presentError(error)
        }
    }

    private func showError(_ message: String) {
        guard let window = view.window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: localized("OK"))
        alert.beginSheetModal(for: window)
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
