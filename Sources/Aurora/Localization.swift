import Foundation

/// Il testo dell'interfaccia nella lingua scelta dal sistema.
///
/// La chiave è la frase inglese, non una sigla. Dove la traduzione manca —
/// perché la lingua non è fra quelle in `Resources/*.lproj`, o perché la voce
/// è appena stata aggiunta — l'app mostra l'inglese e resta usabile, invece di
/// esporre il nome interno della chiave.
func localized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
}

extension Notification.Name {
    /// L'aspetto è cambiato nelle impostazioni: chi mostra testo si ridisegni.
    static let auroraThemeChanged = Notification.Name("AuroraThemeChanged")
}
