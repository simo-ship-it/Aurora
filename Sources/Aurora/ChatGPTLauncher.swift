import AppKit

/// Apre una cartella nell'app desktop di ChatGPT tramite il normale evento
/// macOS "Apri", lo stesso usato trascinando una cartella sull'app.
enum ChatGPTLauncher {

    private static let bundleIdentifiers = [
        "com.openai.codex",
        "com.openai.chat"
    ]

    static var applicationURL: URL? {
        bundleIdentifiers.lazy.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }.first
    }

    static var isAvailable: Bool { applicationURL != nil }

    static func open(folder: URL) {
        guard let applicationURL else { NSSound.beep(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            if error != nil {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }
}
