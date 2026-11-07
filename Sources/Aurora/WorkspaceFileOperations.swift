import AppKit

/// Le modifiche al contenuto della cartella di lavoro passano tutte da qui.
/// Le viste decidono come chiedere nome e destinazione; questa classe mantiene
/// invece le regole del filesystem e la cronologia necessaria per annullarle.
enum WorkspaceFileOperationError: LocalizedError {
    case itemAlreadyExists
    case invalidFolderDestination

    var errorDescription: String? {
        switch self {
        case .itemAlreadyExists:
            return localized("An item with this name already exists.")
        case .invalidFolderDestination:
            return localized("A folder cannot be moved into itself.")
        }
    }
}

final class WorkspaceFileOperations {

    static let shared = WorkspaceFileOperations()

    private typealias Move = (source: URL, destination: URL)

    private struct UndoEntry {
        let action: () throws -> Void
    }

    private let fileManager = FileManager.default
    private var undoEntries: [UndoEntry] = []

    private init() {}

    var canUndo: Bool { !undoEntries.isEmpty }

    func createFolder(named name: String, in parent: URL) throws {
        let destination = parent.standardizedFileURL
            .appendingPathComponent(name, isDirectory: true)
        try ensureAvailable(destination)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        registerUndo { [fileManager] in
            guard fileManager.fileExists(atPath: destination.path) else { return }
            try fileManager.removeItem(at: destination)
        }
    }

    func rename(_ source: URL, to name: String, isFolder: Bool) throws {
        let source = source.standardizedFileURL
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: isFolder)
        guard source != destination else { return }
        try ensureAvailable(destination)
        try moveItems([(source, destination)])
        registerUndo { [weak self] in
            try self?.moveItems([(destination, source)])
        }
    }

    func duplicate(_ sources: [URL]) throws {
        let pairs = try sources.map { source -> Move in
            let source = source.standardizedFileURL
            return (source, try availableCopyURL(for: source))
        }
        try copyItems(pairs)
        registerUndo { [fileManager] in
            for pair in pairs.reversed() where fileManager.fileExists(atPath: pair.destination.path) {
                try fileManager.removeItem(at: pair.destination)
            }
        }
    }

    func copy(_ sources: [URL], to destinationFolder: URL) throws {
        let pairs = try plannedTransfers(sources, to: destinationFolder, copying: true)
        try copyItems(pairs)
        registerUndo { [fileManager] in
            for pair in pairs.reversed() where fileManager.fileExists(atPath: pair.destination.path) {
                try fileManager.removeItem(at: pair.destination)
            }
        }
    }

    func move(_ sources: [URL], to destinationFolder: URL) throws {
        let pairs = try plannedTransfers(sources, to: destinationFolder, copying: false)
        guard !pairs.isEmpty else { return }
        try moveItems(pairs)
        registerUndo { [weak self] in
            try self?.moveItems(pairs.reversed().map { ($0.destination, $0.source) })
        }
    }

    func delete(_ sources: [URL]) throws {
        var trashed: [(original: URL, trashed: URL)] = []
        do {
            for rawSource in sources {
                let source = rawSource.standardizedFileURL
                var resultingURL: NSURL?
                try fileManager.trashItem(at: source, resultingItemURL: &resultingURL)
                guard let trashURL = resultingURL as URL? else {
                    throw CocoaError(.fileNoSuchFile)
                }
                trashed.append((source, trashURL.standardizedFileURL))
            }
        } catch {
            for item in trashed.reversed() {
                try? fileManager.moveItem(at: item.trashed, to: item.original)
            }
            throw error
        }

        registerUndo { [weak self] in
            guard let self else { return }
            for item in trashed {
                try self.ensureAvailable(item.original)
            }
            try self.moveItems(trashed.map { ($0.trashed, $0.original) })
        }
    }

    /// Restituisce `true` solo se l'operazione è stata realmente ripristinata;
    /// un conflitto creato dopo l'azione lascia la cronologia intatta.
    @discardableResult
    func undoLastOperation() -> Bool {
        guard let entry = undoEntries.last else { return false }
        do {
            try entry.action()
            undoEntries.removeLast()
            NotificationCenter.default.post(name: .auroraWorkspaceContentsChanged, object: self)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func plannedTransfers(_ sources: [URL], to destinationFolder: URL,
                                  copying: Bool) throws -> [Move] {
        let folder = destinationFolder.standardizedFileURL
        var seenDestinations = Set<String>()
        var pairs: [Move] = []

        for rawSource in sources {
            let source = rawSource.standardizedFileURL
            if !copying, source.deletingLastPathComponent() == folder { continue }

            let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isFolder, folder == source || folder.path.hasPrefix(source.path + "/") {
                throw WorkspaceFileOperationError.invalidFolderDestination
            }

            let destination = folder.appendingPathComponent(source.lastPathComponent,
                                                             isDirectory: isFolder)
            try ensureAvailable(destination)
            guard seenDestinations.insert(destination.path).inserted else {
                throw WorkspaceFileOperationError.itemAlreadyExists
            }
            pairs.append((source, destination))
        }
        return pairs
    }

    private func availableCopyURL(for source: URL) throws -> URL {
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
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func ensureAvailable(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            throw WorkspaceFileOperationError.itemAlreadyExists
        }
    }

    private func moveItems(_ pairs: [Move]) throws {
        var completed: [Move] = []
        do {
            for pair in pairs {
                try fileManager.moveItem(at: pair.source, to: pair.destination)
                completed.append(pair)
            }
        } catch {
            for pair in completed.reversed() {
                try? fileManager.moveItem(at: pair.destination, to: pair.source)
            }
            throw error
        }
    }

    private func copyItems(_ pairs: [Move]) throws {
        var completed: [Move] = []
        do {
            for pair in pairs {
                try fileManager.copyItem(at: pair.source, to: pair.destination)
                completed.append(pair)
            }
        } catch {
            for pair in completed.reversed() {
                try? fileManager.removeItem(at: pair.destination)
            }
            throw error
        }
    }

    private func registerUndo(_ action: @escaping () throws -> Void) {
        undoEntries.append(UndoEntry(action: action))
        NotificationCenter.default.post(name: .auroraWorkspaceContentsChanged, object: self)
    }
}
