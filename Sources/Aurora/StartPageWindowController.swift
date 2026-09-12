import AppKit

/// La libreria usa la cornice standard di macOS: titolo e comandi vivono nella
/// toolbar della finestra, mentre il contenuto resta dedicato ai file.
final class StartPageWindowController: NSWindowController, NSToolbarDelegate {

    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("AuroraLibraryToolbar")
        static let back = NSToolbarItem.Identifier("AuroraLibraryBack")
        static let finder = NSToolbarItem.Identifier("AuroraLibraryFinder")
        static let claude = NSToolbarItem.Identifier("AuroraLibraryClaude")
    }

    private let libraryController: StartPageViewController
    private let libraryToolbar = NSToolbar(identifier: ToolbarID.toolbar)
    // La configurazione iniziale contiene i comandi per permettere ad AppKit di
    // costruire subito una toolbar completa; lo stato radice li rimuove nel
    // ciclo successivo, senza lasciare una toolbar vuota che il sistema comprime.
    private var showsFolderCommands = true

    init() {
        let content = StartPageViewController()
        libraryController = content
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = localized("Favorites")
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 520, height: 400)
        window.contentViewController = content
        // `contentViewController` può ricreare la content view mentre la
        // finestra viene ripristinata. Ribadiamo qui lo stile, dopo averla
        // installata, perché il bordo resti ridimensionabile a ogni avvio.
        window.styleMask.insert(.resizable)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.setFrameAutosaveName("AuroraStartPageWindow")
        window.center()
        super.init(window: window)
        shouldCascadeWindows = false

        libraryToolbar.delegate = self
        libraryToolbar.displayMode = .iconOnly
        libraryToolbar.allowsUserCustomization = false
        libraryToolbar.autosavesConfiguration = false
        window.toolbar = libraryToolbar

        content.onNavigationChanged = { [weak self] title, isAtRoot in
            self?.updateToolbar(title: title, isAtRoot: isAtRoot)
        }
        content.publishNavigationState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Alla prima visualizzazione AppKit materializza gli elementi predefiniti
        // della toolbar; sincronizziamoli dopo che la finestra è effettivamente visibile.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildToolbar(isAtRoot: self.libraryController.isAtRoot)
        }
    }

    func addFavoriteFolder() {
        show()
        libraryController.chooseFavoriteFolder()
    }

    private func updateToolbar(title: String, isAtRoot: Bool) {
        window?.title = title
        guard showsFolderCommands == !isAtRoot else { return }
        showsFolderCommands = !isAtRoot

        // La toolbar aggiorna internamente il proprio modello durante gli eventi
        // di navigazione. Rimandare la mutazione al ciclo successivo evita che
        // AppKit scarti gli elementi inseriti mentre sta ancora validando il clic.
        DispatchQueue.main.async { [weak self] in
            self?.rebuildToolbar(isAtRoot: isAtRoot)
        }
    }

    private func rebuildToolbar(isAtRoot: Bool) {

        for identifier in [ToolbarID.back, ToolbarID.finder, ToolbarID.claude] {
            if let index = libraryToolbar.items.firstIndex(where: {
                $0.itemIdentifier == identifier
            }) {
                libraryToolbar.removeItem(at: index)
            }
        }
        guard !isAtRoot else { return }

        libraryToolbar.insertItem(withItemIdentifier: ToolbarID.back, at: 0)
        libraryToolbar.insertItem(withItemIdentifier: ToolbarID.finder,
                                  at: libraryToolbar.items.count)
        libraryToolbar.insertItem(withItemIdentifier: ToolbarID.claude,
                                  at: libraryToolbar.items.count)
        libraryToolbar.validateVisibleItems()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.back, .flexibleSpace, ToolbarID.finder, ToolbarID.claude]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.back, .flexibleSpace, ToolbarID.finder, ToolbarID.claude]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = libraryController

        switch identifier {
        case ToolbarID.back:
            item.label = localized("Back")
            item.paletteLabel = localized("Back")
            item.toolTip = localized("Back")
            item.image = toolbarImage("chevron.backward", label: localized("Back"))
            item.action = #selector(StartPageViewController.goBack(_:))
            item.isNavigational = true
        case ToolbarID.finder:
            item.label = localized("Open in Finder")
            item.paletteLabel = localized("Open in Finder")
            item.toolTip = localized("Open in Finder")
            item.image = toolbarImage("folder", label: localized("Open in Finder"))
            item.action = #selector(StartPageViewController.openCurrentInFinder(_:))
        case ToolbarID.claude:
            item.label = localized("Open in Claude Cowork")
            item.paletteLabel = localized("Open in Claude Cowork")
            item.toolTip = localized("Open in Claude Cowork")
            item.image = toolbarImage("sparkles", label: localized("Open in Claude Cowork"))
            item.action = #selector(StartPageViewController.openCurrentInClaude(_:))
            item.isEnabled = libraryController.canOpenClaude
        default:
            return nil
        }
        return item
    }

    private func toolbarImage(_ symbol: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
    }
}

/// Anche lo spazio vuoto della libreria espone le azioni della cartella aperta.
private final class FolderCollectionView: NSCollectionView {
    var makeContextMenu: (() -> NSMenu?)?
    var acceptDroppedFiles: (([URL]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu?() ?? super.menu(for: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptDroppedFiles == nil ? [] : .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        return acceptDroppedFiles?(urls) ?? false
    }
}

private final class StartPageViewController: NSViewController, NSCollectionViewDataSource,
                                               NSCollectionViewDelegate {

    private let emptyLabel = NSTextField(labelWithString: "")
    private let collection = FolderCollectionView()
    private var favorites: [URL] = []
    private var nodes: [WorkspaceNode] = []
    private var navigation: [URL] = []
    private var selectedURLs = Set<URL>()
    var onNavigationChanged: ((String, Bool) -> Void)?

    private static let tileSize = NSSize(width: 120, height: 112)
    private static let tileIdentifier = NSUserInterfaceItemIdentifier("folderTile")

    override func loadView() {
        let root = NSView()

        let layout = FolderGridLayout()
        layout.itemSize = Self.tileSize

        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = false
        collection.backgroundColors = [.clear]
        collection.autoresizingMask = [.width]
        collection.makeContextMenu = { [weak self] in self?.makeCreationMenu() }
        collection.acceptDroppedFiles = { [weak self] urls in
            guard let self, let destination = self.navigation.last else { return false }
            return self.move(urls, to: destination)
        }
        collection.register(FolderTileItem.self, forItemWithIdentifier: Self.tileIdentifier)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .auroraFavoritesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .auroraThemeChanged, object: nil)
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func reload() {
        favorites = Workspace.shared.favoriteFolders
        if let folder = navigation.last {
            nodes = WorkspaceNode.contents(of: folder)
            selectedURLs.formIntersection(Set(nodes.map(\.url)))
        } else {
            nodes = []
            selectedURLs.removeAll()
        }
        publishNavigationState()
        emptyLabel.stringValue = navigation.isEmpty
            ? localized("No favorite folders. Right-click to add one.")
            : localized("This folder contains no Markdown documents.")
        emptyLabel.isHidden = navigation.isEmpty ? !favorites.isEmpty : !nodes.isEmpty
        collection.reloadData()
    }

    @objc private func themeChanged() {
        emptyLabel.textColor = .secondaryLabelColor
        collection.reloadData()
    }

    // MARK: - Griglia

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        navigation.isEmpty ? favorites.count : nodes.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.tileIdentifier, for: indexPath)
        guard let tile = item as? FolderTileItem else { return item }

        if navigation.isEmpty {
            let folder = favorites[indexPath.item]
            tile.configure(folder: folder,
                           open: { [weak self] in self?.enter(folder, asWorkspace: true) },
                           openFolder: { [weak self] in self?.openWorkspace(folder) },
                           remove: { [weak self] in self?.remove(folder) },
                           dragSources: [],
                           additionalMenu: nil)
        } else {
            let node = nodes[indexPath.item]
            let itemMenu = { [weak self] in self?.makeItemMenu(for: node.url) }
            let isSelected = selectedURLs.contains(node.url)
            let dragSources = isSelected ? operationTargets(for: node.url) : [node.url]
            if node.isFolder {
                tile.configure(folder: node.url,
                               open: { [weak self] in self?.enter(node.url, asWorkspace: false) },
                               openFolder: { [weak self] in self?.openWorkspace(node.url) },
                               drop: { [weak self] urls in self?.move(urls, to: node.url) ?? false },
                               dragSources: dragSources,
                               selected: isSelected,
                               toggleSelection: { [weak self] in self?.toggleSelection(node.url) },
                               additionalMenu: itemMenu)
            } else {
                tile.configure(document: node.url,
                               open: { [weak self] in self?.openDocument(node.url) },
                               dragSources: dragSources,
                               selected: isSelected,
                               toggleSelection: { [weak self] in self?.toggleSelection(node.url) },
                               additionalMenu: itemMenu)
            }
        }
        return tile
    }

    // MARK: - Azioni discrete

    fileprivate func chooseFavoriteFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Add Favorite…")
        panel.message = localized("Choose the folder to work in.")
        panel.directoryURL = Workspace.shared.folder
        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Workspace.shared.addFavorite(url)
            self?.reload()
        }
    }

    private func enter(_ folder: URL, asWorkspace: Bool) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { NSSound.beep(); return }
        if asWorkspace { Workspace.shared.open(folder) }
        selectedURLs.removeAll()
        navigation.append(folder)
        reload()
    }

    private func remove(_ folder: URL) {
        Workspace.shared.removeFavorite(folder)
    }

    /// Apre una cartella come fa il comando File > Apri cartella, poi crea la
    /// pagina vuota su cui iniziare a scrivere. La libreria scompare soltanto
    /// quando la finestra dell'editor è stata creata correttamente.
    private func openWorkspace(_ folder: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { NSSound.beep(); return }

        Workspace.shared.open(folder)
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            view.window?.orderOut(nil)
        } catch {
            NSApp.presentError(error)
        }
    }

    private func openDocument(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) {
            [weak self] document, _, _ in
            if document != nil { self?.view.window?.orderOut(nil) }
        }
    }

    // MARK: - Creazione

    private func makeCreationMenu() -> NSMenu? {
        let menu = NSMenu()
        if navigation.isEmpty {
            addMenuItem(localized("Add Favorite…"), #selector(addFavorite(_:)), nil,
                        symbol: "folder.badge.plus", to: menu)
        } else {
            addMenuItem(localized("New Document"), #selector(createDocument(_:)), nil,
                        symbol: "doc.badge.plus", to: menu)
            addMenuItem(localized("New Folder"), #selector(createFolder(_:)), nil,
                        symbol: "folder.badge.plus", to: menu)
        }
        return menu
    }

    private func makeItemMenu(for url: URL) -> NSMenu? {
        let menu = makeCreationMenu() ?? NSMenu()
        menu.addItem(.separator())
        if operationTargets(for: url).count == 1 {
            addMenuItem(localized("Rename…"), #selector(renameItem(_:)), url,
                        symbol: "pencil", to: menu)
        }
        addMenuItem(localized("Duplicate"), #selector(duplicateItem(_:)), url,
                    symbol: "doc.on.doc", to: menu)
        addMenuItem(localized("Move To…"), #selector(moveItem(_:)), url,
                    symbol: "folder", to: menu)
        menu.addItem(.separator())
        addMenuItem(localized("Move to Trash"), #selector(trashItem(_:)), url,
                    symbol: "trash", to: menu)
        return menu
    }

    private func addMenuItem(_ title: String, _ action: Selector, _ url: URL?,
                             symbol: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        menu.addItem(item)
    }

    @objc private func addFavorite(_ sender: Any?) {
        chooseFavoriteFolder()
    }

    @objc private func renameItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL else { return }
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        askForName(title: localized("Rename…"), defaultName: source.lastPathComponent) {
            [weak self] proposedName in
            guard let self else { return }
            var name = proposedName
            if !isFolder, URL(fileURLWithPath: name).pathExtension.isEmpty,
               !source.pathExtension.isEmpty {
                name += "." + source.pathExtension
            }
            let destination = source.deletingLastPathComponent()
                .appendingPathComponent(name, isDirectory: isFolder)
            guard source.standardizedFileURL != destination.standardizedFileURL else { return }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                self.showAlreadyExists()
                return
            }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                self.reload()
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    @objc private func duplicateItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL else { return }
        do {
            for item in operationTargets(for: source) {
                try FileManager.default.copyItem(at: item, to: availableCopyURL(for: item))
            }
            selectedURLs.removeAll()
            reload()
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc private func moveItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL,
              let window = view.window else { return }
        let sources = operationTargets(for: source)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Move")
        panel.message = localized("Choose the destination folder.")
        panel.directoryURL = source.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            _ = self?.move(sources, to: destination)
        }
    }

    @objc private func trashItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        do {
            for item in operationTargets(for: url) {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item, resultingItemURL: &resultingURL)
            }
            selectedURLs.removeAll()
            reload()
        } catch {
            NSApp.presentError(error)
        }
    }

    @discardableResult
    private func move(_ sources: [URL], to destinationFolder: URL) -> Bool {
        let folder = destinationFolder.standardizedFileURL
        var planned: [(URL, URL)] = []
        for source in sources {
            let source = source.standardizedFileURL
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            if source.deletingLastPathComponent() == folder { continue }
            if folder.path == source.path || folder.path.hasPrefix(source.path + "/") {
                NSSound.beep()
                return false
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                showAlreadyExists()
                return false
            }
            planned.append((source, destination))
        }
        guard !planned.isEmpty else { return false }
        do {
            for (source, destination) in planned {
                try FileManager.default.moveItem(at: source, to: destination)
            }
            selectedURLs.removeAll()
            reload()
            return true
        } catch {
            NSApp.presentError(error)
            reload()
            return false
        }
    }

    private func availableCopyURL(for source: URL) -> URL {
        let parent = source.deletingLastPathComponent()
        let ext = source.pathExtension
        let stem = ext.isEmpty ? source.lastPathComponent
                               : source.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let suffix = number == 1 ? localized("copy")
                                     : String(format: localized("copy %d"), number)
            let name = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            let candidate = parent.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func operationTargets(for clickedURL: URL) -> [URL] {
        guard selectedURLs.contains(clickedURL), !selectedURLs.isEmpty else {
            return [clickedURL]
        }
        return selectedURLs.sorted { $0.path < $1.path }
    }

    private func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
        collection.reloadData()
    }

    @objc private func createDocument(_ sender: Any?) {
        guard let parent = navigation.last else { return }
        askForName(title: localized("New Document"), defaultName: localized("Untitled")) {
            [weak self] name in
            guard let self else { return }
            var fileName = name
            if !Workspace.readableExtensions.contains(
                URL(fileURLWithPath: fileName).pathExtension.lowercased()) {
                fileName += ".md"
            }
            let url = parent.appendingPathComponent(fileName, isDirectory: false)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                self.showAlreadyExists()
                return
            }
            guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
                NSSound.beep()
                return
            }
            self.reload()
        }
    }

    @objc private func createFolder(_ sender: Any?) {
        guard let parent = navigation.last else { return }
        askForName(title: localized("New Folder"), defaultName: localized("New Folder")) {
            [weak self] name in
            guard let self else { return }
            let url = parent.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                self.showAlreadyExists()
                return
            }
            do {
                try FileManager.default.createDirectory(at: url,
                                                        withIntermediateDirectories: false)
                self.reload()
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private func askForName(title: String, defaultName: String,
                            completion: @escaping (String) -> Void) {
        guard let window = view.window else { return }
        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = localized("Choose a name.")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: localized("Create"))
        alert.addButton(withTitle: localized("Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                NSSound.beep()
                self?.askForName(title: title, defaultName: field.stringValue,
                                 completion: completion)
                return
            }
            completion(name)
        }
    }

    private func showAlreadyExists() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = localized("An item with this name already exists.")
        alert.addButton(withTitle: localized("OK"))
        alert.beginSheetModal(for: window)
    }

    @objc fileprivate func goBack(_ sender: Any?) {
        guard !navigation.isEmpty else { return }
        selectedURLs.removeAll()
        navigation.removeLast()
        reload()
    }

    fileprivate func publishNavigationState() {
        onNavigationChanged?(navigation.last?.lastPathComponent ?? localized("Favorites"),
                             navigation.isEmpty)
    }

    fileprivate var canOpenClaude: Bool {
        guard let cowork = URL(string: "claude://cowork/new") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: cowork) != nil
    }

    fileprivate var isAtRoot: Bool { navigation.isEmpty }

    @objc fileprivate func openCurrentInFinder(_ sender: Any?) {
        guard let folder = navigation.last else { return }
        NSWorkspace.shared.open(folder)
    }

    @objc fileprivate func openCurrentInClaude(_ sender: Any?) {
        guard let folder = navigation.last else { return }
        var link = URLComponents()
        link.scheme = "claude"
        link.host = "cowork"
        link.path = "/new"
        link.queryItems = [URLQueryItem(name: "folder", value: folder.path)]
        guard let url = link.url else { NSSound.beep(); return }
        NSWorkspace.shared.open(url)
    }
}

/// AppKit tende ad allargare lo spazio fra gli elementi di un flow layout per
/// riempire ogni riga. Durante il live resize questo sposta tutte le icone a
/// ogni singolo pixel. Qui passo e posizioni restano fissi: cambia soltanto il
/// numero di colonne quando una tessera non entra più.
private final class FolderGridLayout: NSCollectionViewLayout {

    var itemSize = NSSize(width: 136, height: 144)
    var horizontalSpacing: CGFloat = 20
    var verticalSpacing: CGFloat = 24
    private let topInset: CGFloat = 4
    private let bottomInset: CGFloat = 24
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize = NSSize.zero
    private var columnCount = 1

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        let width = max(itemSize.width, collectionView.bounds.width)
        let columns = columns(for: width)
        columnCount = columns
        let count = collectionView.numberOfItems(inSection: 0)

        attributes = (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            let item = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(item: index, section: 0))
            item.frame = NSRect(
                x: CGFloat(column) * (itemSize.width + horizontalSpacing),
                y: topInset + CGFloat(row) * (itemSize.height + verticalSpacing),
                width: itemSize.width,
                height: itemSize.height)
            return item
        }

        let rows = count == 0 ? 0 : (count + columns - 1) / columns
        let height = topInset + CGFloat(rows) * itemSize.height
            + CGFloat(max(0, rows - 1)) * verticalSpacing + bottomInset
        contentSize = NSSize(width: width, height: height)
    }

    override var collectionViewContentSize: NSSize {
        var size = contentSize
        if let collectionView {
            size.width = max(itemSize.width, collectionView.bounds.width)
        }
        return size
    }

    override func layoutAttributesForElements(in rect: NSRect)
        -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath)
        -> NSCollectionViewLayoutAttributes? {
        attributes.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        columns(for: newBounds.width) != columnCount
    }

    private func columns(for width: CGFloat) -> Int {
        max(1, Int((max(itemSize.width, width) + horizontalSpacing) /
                   (itemSize.width + horizontalSpacing)))
    }
}

/// Clic destro: la rimozione resta accessibile, ma non riempie la libreria di
/// comandi che l'utente usa raramente.
private final class FolderTileItem: NSCollectionViewItem {

    private let tile = FolderTileButton()

    override func loadView() { view = tile }

    func configure(folder: URL, open: @escaping () -> Void,
                   openFolder: @escaping () -> Void,
                   remove: (() -> Void)? = nil,
                   drop: (([URL]) -> Bool)? = nil,
                   dragSources: [URL] = [],
                   selected: Bool = false,
                   toggleSelection: (() -> Void)? = nil,
                   additionalMenu: (() -> NSMenu?)? = nil) {
        let exists = FileManager.default.fileExists(atPath: folder.path)
        tile.configure(title: folder.lastPathComponent,
                       symbol: exists ? "folder.fill" : "folder.badge.questionmark",
                       color: exists ? .controlAccentColor : .secondaryLabelColor,
                       dragSources: dragSources, action: open,
                       openFolder: openFolder, remove: remove,
                       drop: drop, selected: selected, toggleSelection: toggleSelection,
                       additionalMenu: additionalMenu)
    }

    func configure(document: URL, open: @escaping () -> Void,
                   dragSources: [URL] = [],
                   selected: Bool = false,
                   toggleSelection: (() -> Void)? = nil,
                   additionalMenu: (() -> NSMenu?)? = nil) {
        tile.configure(title: document.deletingPathExtension().lastPathComponent,
                       symbol: "doc.text", color: .secondaryLabelColor,
                       dragSources: dragSources, action: open,
                       openFolder: nil, remove: nil,
                       drop: nil, selected: selected, toggleSelection: toggleSelection,
                       additionalMenu: additionalMenu)
    }
}

private final class FolderTileButton: NSButton {

    private let iconCanvas = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isTileSelected = false
    private var onOpen: (() -> Void)?
    private var onOpenFolder: (() -> Void)?
    private var onRemove: (() -> Void)?
    private var onDrop: (([URL]) -> Bool)?
    private var onToggleSelection: (() -> Void)?
    private var makeAdditionalMenu: (() -> NSMenu?)?
    private var draggedURLs: [URL] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        target = self
        action = #selector(open(_:))
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 8

        iconCanvas.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconCanvas)
        iconCanvas.addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconCanvas.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            iconCanvas.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconCanvas.widthAnchor.constraint(equalToConstant: 72),
            iconCanvas.heightAnchor.constraint(equalToConstant: 60),

            iconView.centerXAnchor.constraint(equalTo: iconCanvas.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCanvas.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 54),

            nameLabel.topAnchor.constraint(equalTo: iconCanvas.bottomAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func configure(title: String, symbol: String, color: NSColor,
                   dragSources: [URL],
                   action: @escaping () -> Void, openFolder: (() -> Void)?,
                   remove: (() -> Void)?, drop: (([URL]) -> Bool)?,
                   selected: Bool, toggleSelection: (() -> Void)?,
                   additionalMenu: (() -> NSMenu?)?) {
        nameLabel.stringValue = title
        nameLabel.textColor = .labelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
        iconView.contentTintColor = color
        onOpen = action
        onOpenFolder = openFolder
        onRemove = remove
        onDrop = drop
        onToggleSelection = toggleSelection
        makeAdditionalMenu = additionalMenu
        draggedURLs = dragSources
        isTileSelected = selected
        updateBackground()
        if remove != nil {
            toolTip = localized("Click to select this folder. Right-click to remove it.")
        } else {
            toolTip = title
        }
        setAccessibilityLabel(title)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        let color: NSColor
        if isTileSelected {
            color = .selectedContentBackgroundColor.withAlphaComponent(0.18)
        } else if isPointerInside {
            color = .labelColor.withAlphaComponent(0.055)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
    }

    /// Le viste decorative non devono sottrarre il clic al pulsante che le
    /// contiene: tutta la tessera resta un unico bersaglio.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arriva nel sistema di coordinate del superview. Lasciamo che
        // AppKit faccia conversioni e controlli di visibilità, poi riportiamo
        // qualsiasi figlio decorativo al pulsante vero e proprio.
        super.hitTest(point) == nil ? nil : self
    }

    @objc private func open(_ sender: Any?) { onOpen?() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let onOpenFolder {
            onOpenFolder()
            return
        }
        if event.modifierFlags.contains(.shift), let onToggleSelection {
            onToggleSelection()
            return
        }
        guard let window else { onOpen?(); return }
        let origin = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                onOpen?()
                return
            }
            let dx = next.locationInWindow.x - origin.x
            let dy = next.locationInWindow.y - origin.y
            if hypot(dx, dy) >= 4, !draggedURLs.isEmpty {
                beginDrag(with: next)
                return
            }
        }
    }

    private func beginDrag(with event: NSEvent) {
        let items = draggedURLs.map { url -> NSDraggingItem in
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            item.setDraggingFrame(iconCanvas.frame, contents: iconView.image)
            return item
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDrop == nil ? [] : .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        return onDrop?(urls) ?? false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard onOpenFolder != nil || onRemove != nil || makeAdditionalMenu != nil else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = makeAdditionalMenu?() ?? NSMenu()
        if !menu.items.isEmpty, onOpenFolder != nil || onRemove != nil {
            menu.addItem(.separator())
        }
        if onOpenFolder != nil {
            let openItem = NSMenuItem(title: localized("Open Folder"),
                                      action: #selector(openFolder(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.image = menuImage("folder", label: localized("Open Folder"))
            menu.addItem(openItem)
        }
        if onRemove != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let removeItem = NSMenuItem(title: localized("Remove Favorite"),
                                        action: #selector(removeFavorite(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.image = menuImage("minus.circle", label: localized("Remove Favorite"))
            menu.addItem(removeItem)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openFolder(_ sender: Any?) { onOpenFolder?() }
    @objc private func removeFavorite(_ sender: Any?) { onRemove?() }

    private func menuImage(_ symbol: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }
}

extension FolderTileButton: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}
