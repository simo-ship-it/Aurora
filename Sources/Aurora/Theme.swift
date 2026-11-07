import AppKit

/// Colori, font e metriche dell'editor.
///
/// Tipografia compatta e superfici neutre, ispirate al lettore Markdown di
/// Codex. Le misure restano relative al corpo scelto dall'utente.
struct Theme {

    static var current = Theme()

    // MARK: - Metriche

    var bodySize: CGFloat = 14
    var monoSize: CGFloat = 13
    var lineHeightMultiple: CGFloat = 22.0 / 14.0
    /// ~75 caratteri per riga al corpo attuale: la misura in cui l'occhio
    /// ritrova l'inizio della riga successiva senza cercarlo.
    var maxContentWidth: CGFloat = 720
    var minSideMargin: CGFloat = 32
    var topInset: CGFloat = 32

    /// Raggio delle superfici di blocco (codice, tabelle).
    var surfaceRadius: CGFloat = 8
    /// Rientro del testo dentro una superficie di blocco.
    var surfacePadding: CGFloat = 16
    /// Passo di rientro di un livello di elenco.
    var listIndent: CGFloat = 24
    /// Passo di rientro di un livello di citazione.
    var quoteIndent: CGFloat = 24

    // MARK: - Font

    /// La famiglia del testo di lettura. `nil` è il font di sistema, che non è
    /// una famiglia fra le altre: segue la dimensione ottica e le impostazioni
    /// di accessibilità, e per questo resta la scelta predefinita.
    var fontFamily: String?

    /// Il font del testo alla misura e al peso richiesti. Una famiglia scelta
    /// dall'utente può non avere il peso chiesto: in quel caso il descrittore
    /// non si risolve e si torna al font di sistema, che ce l'ha sempre.
    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        guard let fontFamily else { return NSFont.systemFont(ofSize: size, weight: weight) }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    var body: NSFont { font(size: bodySize, weight: .regular) }
    /// Il codice resta monospaziato di sistema anche con un'altra famiglia
    /// scelta: l'allineamento in colonna è il suo motivo di esistere.
    var mono: NSFont { NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular) }

    var tableBody: NSFont { font(size: max(11, bodySize * 0.875), weight: .regular) }
    var tableHeader: NSFont { font(size: tableBody.pointSize, weight: .semibold) }

    func heading(_ level: Int) -> NSFont {
        let scale: [CGFloat] = [1.5, 1.25, 1.125, 1, 1, 1]
        let l = max(1, min(6, level))
        return font(size: bodySize * scale[l - 1], weight: .semibold)
    }

    /// Crenatura dei titoli: ai corpi grandi le lettere vanno strette,
    /// altrimenti il peso diventa goffo.
    func headingTracking(_ level: Int) -> CGFloat {
        switch max(1, min(6, level)) {
        case 1: return -0.2
        case 2: return -0.1
        default: return 0
        }
    }

    /// Applica i tratti grassetto/corsivo mantenendo dimensione e famiglia.
    static func apply(bold: Bool, italic: Bool, to font: NSFont) -> NSFont {
        var descriptor = font.fontDescriptor
        if bold {
            var traits = descriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any] ?? [:]
            traits[.weight] = NSFont.Weight.semibold.rawValue
            descriptor = descriptor.addingAttributes([.traits: traits])
        }
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    // MARK: - Colori

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    private static func gray(_ value: CGFloat) -> NSColor {
        NSColor(calibratedWhite: value, alpha: 1)
    }

    /// La pagina. In modalità scura resta quasi nera, ma non assoluta: il
    /// contrasto è netto senza perdere la profondità delle superfici interne.
    let background = Theme.dynamic(light: Theme.gray(1.0), dark: Theme.gray(24.0 / 255.0))

    /// Testo corrente.
    let text = Theme.dynamic(
        light: NSColor(calibratedRed: 26.0 / 255.0, green: 28.0 / 255.0, blue: 31.0 / 255.0, alpha: 1),
        dark: Theme.gray(223.0 / 255.0))

    var headingText: NSColor { text }

    /// Tono di servizio per la sintassi che resta testuale (per esempio le
    /// definizioni dei riferimenti), non per i marcatori nascosti.
    let syntax = Theme.dynamic(light: Theme.gray(0.71), dark: Theme.gray(0.48))

    /// I collegamenti restano riconoscibili grazie alla sottolineatura.
    var accent: NSColor { text }

    /// Testo di servizio: citazioni, numeri di elenco, voci barrate.
    let quoteText = Theme.dynamic(light: Theme.gray(0.365), dark: Theme.gray(0.64))

    let quoteBar = Theme.dynamic(light: Theme.gray(0.855), dark: Theme.gray(0.32))

    var codeText: NSColor { text }

    /// I blocchi di codice hanno una superficie propria; le tabelle restano
    /// sulla pagina e sono separate soltanto da righe orizzontali.
    let codeBackground = Theme.dynamic(
        light: NSColor(calibratedRed: 0.969, green: 0.969, blue: 0.973, alpha: 1),
        dark: Theme.gray(33.0 / 255.0))

    let inlineCodeBackground = Theme.dynamic(
        light: NSColor(calibratedRed: 0.949, green: 0.949, blue: 0.957, alpha: 1),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.085))

    let rule = Theme.dynamic(light: Theme.gray(0.90), dark: Theme.gray(0.22))
    let tableHeaderRule = Theme.dynamic(light: Theme.gray(0.77), dark: Theme.gray(0.36))

    /// Bordo della casella non spuntata.
    let controlBorder = Theme.dynamic(light: Theme.gray(0.78), dark: Theme.gray(0.42))

    let highlight = Theme.dynamic(
        light: NSColor(calibratedRed: 0.992, green: 0.937, blue: 0.706, alpha: 1),
        dark: NSColor(calibratedRed: 0.58, green: 0.50, blue: 0.16, alpha: 0.62))

    /// Nero come il testo: il cursore non è un elemento di marca.
    var insertionPoint: NSColor { text }
}

extension NSAttributedString.Key {
    /// I caratteri con questo attributo diventano controlli a larghezza zero.
    static let auroraConceal = NSAttributedString.Key("auroraConceal")
    /// Decorazione di blocco disegnata dietro al testo: "code", "table", "hr".
    static let auroraBlock = NSAttributedString.Key("auroraBlock")
    /// Profondità della citazione, per disegnare le barre laterali.
    static let auroraQuoteDepth = NSAttributedString.Key("auroraQuoteDepth")
    /// Glifo da disegnare al posto del carattere (elenchi puntati, checkbox).
    static let auroraGlyph = NSAttributedString.Key("auroraGlyph")
    /// URL di un collegamento, gestito internamente (no attributo .link).
    static let auroraLink = NSAttributedString.Key("auroraLink")
    /// URL dell'immagine da disegnare nella riga che conserva la sua sorgente Markdown.
    static let auroraImage = NSAttributedString.Key("auroraImage")
    /// Range della checkbox di una task list; il valore è lo stato.
    static let auroraCheckbox = NSAttributedString.Key("auroraCheckbox")
}
