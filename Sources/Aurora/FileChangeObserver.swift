import Darwin
import Foundation

/// Osserva una cartella con il vnode del filesystem. Osservare la cartella,
/// anziché il singolo file, copre anche i salvataggi atomici: molti editor
/// scrivono un file temporaneo e poi lo sostituiscono con una rinomina.
///
/// Il callback può arrivare fuori dal thread principale; chi lo riceve deve
/// quindi passare al main thread prima di toccare AppKit.
final class DirectoryChangeObserver {

    private let directoryURL: URL
    private let handler: () -> Void
    private let queue: DispatchQueue
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    init(directoryURL: URL, label: String, handler: @escaping () -> Void) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.handler = handler
        queue = DispatchQueue(label: "Aurora.FileObserver.\(label)")
        start()
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let events: DispatchSource.FileSystemEvent = [
            .write, .delete, .rename, .extend, .attrib, .link, .revoke
        ]
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handler()
        }
        source.setCancelHandler { [descriptor] in
            guard descriptor >= 0 else { return }
            close(descriptor)
        }
        self.source = source
        source.resume()
    }
}
