import AppKit

/// Le preferenze dell'utente, e l'unico punto da cui `Theme.current` viene
/// costruito.
///
/// Il tema resta una struttura di soli valori: qui si decide quali, si scrivono
/// in `UserDefaults` e si avvisa chi disegna. Nessuna vista legge le preferenze
/// direttamente, così cambiare una misura non richiede di sapere chi la usa.
final class Settings {

    static let shared = Settings()

    enum Appearance: String, CaseIterable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: return localized("Match System")
            case .light:  return localized("Light")
            case .dark:   return localized("Dark")
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            }
        }
    }

    // MARK: - Valori

    /// `nil` significa il font di sistema: non è un nome di famiglia fra gli
    /// altri, perché segue la dimensione ottica e le impostazioni di accessibilità.
    var fontFamily: String? { didSet { save("fontFamily", fontFamily); apply() } }
    var fontSize: CGFloat { didSet { save("fontSize", Double(fontSize)); apply() } }
    var lineHeight: CGFloat { didSet { save("lineHeight", Double(lineHeight)); apply() } }
    var contentWidth: CGFloat { didSet { save("contentWidth", Double(contentWidth)); apply() } }
    var appearance: Appearance { didSet { save("appearance", appearance.rawValue); apply() } }

    // Gli estremi dei cursori, e insieme i limiti entro cui un valore letto dal
    // disco viene ricondotto: un plist modificato a mano non deve rompere il testo.
    static let fontSizeRange: ClosedRange<CGFloat> = 11...30
    static let lineHeightRange: ClosedRange<CGFloat> = 1.2...2.6
    static let contentWidthRange: ClosedRange<CGFloat> = 480...1200

    private static let defaults = Theme()

    // MARK: - Persistenza

    private let store = UserDefaults.standard
    private static let prefix = "AuroraSettings."
    /// Vero durante `init` e `restoreDefaults`: impedisce che ogni `didSet`
    /// ricostruisca il tema mentre i valori sono ancora a metà.
    private var isLoading = true

    private init() {
        let store = self.store
        func number(_ key: String, _ fallback: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
            guard store.object(forKey: Settings.prefix + key) != nil else { return fallback }
            return min(max(CGFloat(store.double(forKey: Settings.prefix + key)), range.lowerBound),
                       range.upperBound)
        }
        fontFamily = store.string(forKey: Settings.prefix + "fontFamily")
        fontSize = number("fontSize", Settings.defaults.bodySize, Settings.fontSizeRange)
        lineHeight = number("lineHeight", Settings.defaults.lineHeightMultiple, Settings.lineHeightRange)
        contentWidth = number("contentWidth", Settings.defaults.maxContentWidth, Settings.contentWidthRange)
        appearance = Appearance(rawValue: store.string(forKey: Settings.prefix + "appearance") ?? "")
            ?? .system
        isLoading = false
    }

    private func save(_ key: String, _ value: Any?) {
        guard !isLoading else { return }
        if let value {
            store.set(value, forKey: Settings.prefix + key)
        } else {
            store.removeObject(forKey: Settings.prefix + key)
        }
    }

    func restoreDefaults() {
        isLoading = true
        fontFamily = nil
        fontSize = Settings.defaults.bodySize
        lineHeight = Settings.defaults.lineHeightMultiple
        contentWidth = Settings.defaults.maxContentWidth
        appearance = .system
        for key in ["fontFamily", "fontSize", "lineHeight", "contentWidth", "appearance"] {
            store.removeObject(forKey: Settings.prefix + key)
        }
        isLoading = false
        apply()
    }

    // MARK: - Applicazione

    /// Ricostruisce il tema e avvisa le viste. Va chiamata una volta all'avvio,
    /// prima che si apra qualunque finestra.
    func apply() {
        guard !isLoading else { return }
        var theme = Theme()
        theme.fontFamily = fontFamily
        theme.bodySize = fontSize
        // Il monospaziato ha occhio più grande: pareggiato alla lettera, sulla
        // stessa riga sembrerebbe più corpo del testo attorno.
        theme.monoSize = (fontSize * 0.85).rounded()
        theme.lineHeightMultiple = lineHeight
        theme.maxContentWidth = contentWidth
        Theme.current = theme

        NSApp?.appearance = appearance.nsAppearance
        NotificationCenter.default.post(name: .auroraThemeChanged, object: nil)
    }
}
