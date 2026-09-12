import AppKit

/// La cartella su cui sta lavorando l'editor: quella che il pulsante a forma di
/// cartella elenca e che si sceglie con "Apri cartella…".
///
/// È una sola per l'applicazione, non una per finestra: aprire una cartella
/// cambia il contesto di lavoro, non il documento davanti agli occhi.
final class Workspace {

    static let shared = Workspace()

    private static let defaultsKey = "AuroraWorkspaceFolder"
    private static let favoritesKey = "AuroraFavoriteFolders"

    /// Estensioni elencate. Le altre restano invisibili: l'elenco serve a
    /// scrivere, non a esplorare il disco.
    static let readableExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdtext", "txt"]

    private(set) var folder: URL? {
        didSet {
            guard folder != oldValue else { return }
            UserDefaults.standard.set(folder?.path, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .auroraWorkspaceChanged, object: self)
        }
    }

    private init() {
        guard let path = UserDefaults.standard.string(forKey: Self.defaultsKey) else { return }
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    func open(_ url: URL) {
        folder = url.standardizedFileURL
    }

    // MARK: - Cartelle preferite

    /// I preferiti sono collegamenti a cartelle, non copie: perciò l'elenco
    /// resta leggero e continua a puntare al contenuto aggiornato sul disco.
    /// Conserviamo anche i percorsi non disponibili (per esempio un disco
    /// esterno scollegato), così l'utente può riconoscerli e rimuoverli.
    var favoriteFolders: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        var seen = Set<String>()
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            return seen.insert(url.path).inserted ? url : nil
        }
    }

    func isFavorite(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return favoriteFolders.contains { $0.path == path }
    }

    @discardableResult
    func addFavorite(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        guard !isFavorite(url) else { return false }
        var paths = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        paths.append(url.path)
        UserDefaults.standard.set(paths, forKey: Self.favoritesKey)
        NotificationCenter.default.post(name: .auroraFavoritesChanged, object: self)
        return true
    }

    @discardableResult
    func removeFavorite(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let paths = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        let updated = paths.filter { $0 != path }
        guard updated.count != paths.count else { return false }
        UserDefaults.standard.set(updated, forKey: Self.favoritesKey)
        NotificationCenter.default.post(name: .auroraFavoritesChanged, object: self)
        return true
    }

    /// Alla prima apertura di un documento adotta la sua cartella, così il
    /// pulsante è già utile senza aver scelto niente.
    func adoptIfEmpty(_ documentURL: URL?) {
        guard folder == nil, let documentURL else { return }
        folder = documentURL.deletingLastPathComponent()
    }

    // MARK: - Cartelle aperte nell'albero

    private static let expandedKey = "AuroraExpandedFolders"

    /// Quali cartelle sono aperte nell'albero. Sta qui e non nella vista perché
    /// il pannello viene ricostruito a ogni apertura: se lo stato vivesse lì,
    /// si azzererebbe ogni volta.
    private lazy var expanded: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: Self.expandedKey) ?? [])

    func isExpanded(_ url: URL) -> Bool {
        expanded.contains(url.path)
    }

    func setExpanded(_ isOpen: Bool, for url: URL) {
        let changed = isOpen ? expanded.insert(url.path).inserted : (expanded.remove(url.path) != nil)
        guard changed else { return }
        UserDefaults.standard.set(Array(expanded), forKey: Self.expandedKey)
    }
}
