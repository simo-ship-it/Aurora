import AppKit

/// Una libreria essenziale: le cartelle sono l'interfaccia, non un dettaglio
/// da nascondere in una finestra di dialogo. Il primo riquadro le aggiunge.
final class StartPageWindowController: NSWindowController {

    init() {
        let content = StartPageViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Aurora"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = Theme.current.background
        window.minSize = NSSize(width: 480, height: 360)
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class StartPageViewController: NSViewController, NSCollectionViewDataSource,
                                               NSCollectionViewDelegateFlowLayout {

    private let titleLabel = NSTextField(labelWithString: "Aurora")
    private let backButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let collection = NSCollectionView()
    private var titleLeadingWithoutBack: NSLayoutConstraint!
    private var titleLeadingWithBack: NSLayoutConstraint!
    private var favorites: [URL] = []
    private var nodes: [WorkspaceNode] = []
    private var navigation: [URL] = []
    private var theme: Theme { Theme.current }

    private static let tileSize = NSSize(width: 136, height: 144)
    private static let tileIdentifier = NSUserInterfaceItemIdentifier("folderTile")

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = theme.background.cgColor

        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        titleLabel.textColor = theme.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)

        backButton.isBordered = false
        backButton.image = NSImage(systemSymbolName: "chevron.left",
                                   accessibilityDescription: localized("Back"))
        backButton.imagePosition = .imageOnly
        backButton.contentTintColor = theme.text
        backButton.toolTip = localized("Back")
        backButton.target = self
        backButton.action = #selector(goBack(_:))
        backButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backButton)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = Self.tileSize
        layout.minimumInteritemSpacing = 18
        layout.minimumLineSpacing = 20
        layout.sectionInset = NSEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)

        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = false
        collection.backgroundColors = [.clear]
        collection.register(FolderTileItem.self, forItemWithIdentifier: Self.tileIdentifier)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = theme.quoteText
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        titleLeadingWithoutBack = titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor,
                                                                       constant: 54)
        titleLeadingWithBack = titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor,
                                                                    constant: 8)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
            backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
            backButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),

            titleLeadingWithoutBack,
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -54),

            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 54),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -54),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -42),

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
        } else {
            nodes = []
        }
        updateHeader()
        emptyLabel.stringValue = localized("This folder contains no Markdown documents.")
        emptyLabel.isHidden = navigation.isEmpty || !nodes.isEmpty
        collection.reloadData()
    }

    @objc private func themeChanged() {
        view.layer?.backgroundColor = theme.background.cgColor
        titleLabel.textColor = theme.text
        backButton.contentTintColor = theme.text
        emptyLabel.textColor = theme.quoteText
        collection.reloadData()
    }

    // MARK: - Griglia

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if navigation.isEmpty {
            // La prima tessera è l'unico invito all'azione. Anche con una
            // libreria vuota la schermata resta intenzionale, non spoglia.
            return favorites.count + 1
        }
        return nodes.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.tileIdentifier, for: indexPath)
        guard let tile = item as? FolderTileItem else { return item }

        if navigation.isEmpty {
            if indexPath.item == 0 {
                tile.configureAdd { [weak self] in self?.chooseFavoriteFolder() }
            } else {
                let folder = favorites[indexPath.item - 1]
                tile.configure(folder: folder, color: folderColor(for: indexPath.item - 1),
                               open: { [weak self] in self?.enter(folder, asWorkspace: true) },
                               openFolder: { [weak self] in self?.openWorkspace(folder) },
                               remove: { [weak self] in self?.remove(folder) })
            }
        } else {
            let node = nodes[indexPath.item]
            if node.isFolder {
                tile.configure(folder: node.url, color: folderColor(for: indexPath.item),
                               open: { [weak self] in self?.enter(node.url, asWorkspace: false) },
                               openFolder: { [weak self] in self?.openWorkspace(node.url) })
            } else {
                tile.configure(document: node.url) { [weak self] in self?.openDocument(node.url) }
            }
        }
        return tile
    }

    func collectionView(_ collectionView: NSCollectionView,
                        layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        Self.tileSize
    }

    private func folderColor(for index: Int) -> NSColor {
        let colors: [NSColor] = [
            Theme.dynamic(light: NSColor(calibratedRed: 0.38, green: 0.68, blue: 0.96, alpha: 1),
                          dark: NSColor(calibratedRed: 0.35, green: 0.62, blue: 0.88, alpha: 1)),
            Theme.dynamic(light: NSColor(calibratedRed: 0.48, green: 0.76, blue: 0.67, alpha: 1),
                          dark: NSColor(calibratedRed: 0.40, green: 0.69, blue: 0.60, alpha: 1)),
            Theme.dynamic(light: NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.47, alpha: 1),
                          dark: NSColor(calibratedRed: 0.88, green: 0.55, blue: 0.40, alpha: 1)),
            Theme.dynamic(light: NSColor(calibratedRed: 0.75, green: 0.60, blue: 0.94, alpha: 1),
                          dark: NSColor(calibratedRed: 0.66, green: 0.50, blue: 0.85, alpha: 1))
        ]
        return colors[index % colors.count]
    }

    // MARK: - Azioni discrete

    private func chooseFavoriteFolder() {
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

    @objc private func goBack(_ sender: Any?) {
        guard !navigation.isEmpty else { return }
        navigation.removeLast()
        reload()
    }

    private func updateHeader() {
        titleLabel.stringValue = navigation.last?.lastPathComponent ?? "Aurora"
        backButton.isHidden = navigation.isEmpty
        titleLeadingWithoutBack.isActive = navigation.isEmpty
        titleLeadingWithBack.isActive = !navigation.isEmpty
    }
}

/// Clic destro: la rimozione resta accessibile, ma non riempie la libreria di
/// comandi che l'utente usa raramente.
private final class FolderTileItem: NSCollectionViewItem {

    private let tile = FolderTileButton()

    override func loadView() { view = tile }

    func configureAdd(action: @escaping () -> Void) {
        tile.configure(title: localized("Add"), symbol: "plus", color: Theme.current.quoteText,
                       isAdd: true, action: action, openFolder: nil, remove: nil)
    }

    func configure(folder: URL, color: NSColor, open: @escaping () -> Void,
                   openFolder: @escaping () -> Void,
                   remove: (() -> Void)? = nil) {
        let exists = FileManager.default.fileExists(atPath: folder.path)
        tile.configure(title: folder.lastPathComponent,
                       symbol: exists ? "folder.fill" : "folder.badge.questionmark",
                       color: exists ? color : Theme.current.quoteText,
                       isAdd: false, action: open, openFolder: openFolder, remove: remove)
    }

    func configure(document: URL, open: @escaping () -> Void) {
        tile.configure(title: document.deletingPathExtension().lastPathComponent,
                       symbol: "doc.text.fill", color: Theme.current.quoteText,
                       isAdd: false, action: open, openFolder: nil, remove: nil)
    }
}

private final class FolderTileButton: NSButton {

    private let iconCanvas = NSView()
    private let addBackground = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var onOpen: (() -> Void)?
    private var onOpenFolder: (() -> Void)?
    private var onRemove: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        target = self
        action = #selector(open(_:))

        iconCanvas.translatesAutoresizingMaskIntoConstraints = false
        addBackground.wantsLayer = true
        addBackground.layer?.cornerRadius = 20
        addBackground.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconCanvas)
        iconCanvas.addSubview(addBackground)
        iconCanvas.addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconCanvas.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconCanvas.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconCanvas.widthAnchor.constraint(equalToConstant: 100),
            iconCanvas.heightAnchor.constraint(equalToConstant: 84),

            addBackground.centerXAnchor.constraint(equalTo: iconCanvas.centerXAnchor),
            addBackground.centerYAnchor.constraint(equalTo: iconCanvas.centerYAnchor),
            addBackground.widthAnchor.constraint(equalToConstant: 72),
            addBackground.heightAnchor.constraint(equalToConstant: 72),

            iconView.centerXAnchor.constraint(equalTo: iconCanvas.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCanvas.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 92),
            iconView.heightAnchor.constraint(equalToConstant: 76),

            nameLabel.topAnchor.constraint(equalTo: iconCanvas.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func configure(title: String, symbol: String, color: NSColor, isAdd: Bool,
                   action: @escaping () -> Void, openFolder: (() -> Void)?,
                   remove: (() -> Void)?) {
        nameLabel.stringValue = title
        nameLabel.textColor = Theme.current.text
        let configuration = NSImage.SymbolConfiguration(pointSize: isAdd ? 28 : 58,
                                                        weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
        iconView.contentTintColor = color
        addBackground.isHidden = !isAdd
        addBackground.layer?.backgroundColor = Theme.current.inlineCodeBackground.cgColor
        onOpen = action
        onOpenFolder = openFolder
        onRemove = remove
        if isAdd {
            toolTip = localized("Add Favorite…")
        } else if remove != nil {
            toolTip = localized("Click to select this folder. Right-click to remove it.")
        } else {
            toolTip = title
        }
        setAccessibilityLabel(title)
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
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard onOpenFolder != nil || onRemove != nil else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        if onOpenFolder != nil {
            let openItem = NSMenuItem(title: localized("Open Folder"),
                                      action: #selector(openFolder(_:)), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
        }
        if onRemove != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let removeItem = NSMenuItem(title: localized("Remove Favorite"),
                                        action: #selector(removeFavorite(_:)), keyEquivalent: "")
            removeItem.target = self
            menu.addItem(removeItem)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openFolder(_ sender: Any?) { onOpenFolder?() }
    @objc private func removeFavorite(_ sender: Any?) { onRemove?() }
}
