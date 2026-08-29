import AppKit

/// Colori, font e metriche dell'editor.
///
/// La tavolozza è monocromatica: la gerarchia nasce dal tono e dallo spazio,
/// non dal colore. L'accento compare in due soli posti — collegamenti e caselle
/// spuntate — così resta un segnale, non una decorazione.
struct Theme {

    static var current = Theme()

    // MARK: - Metriche

    var bodySize: CGFloat = 17
    var monoSize: CGFloat = 14
    var lineHeightMultiple: CGFloat = 1.7
    /// ~75 caratteri per riga al corpo attuale: la misura in cui l'occhio
    /// ritrova l'inizio della riga successiva senza cercarlo.
    var maxContentWidth: CGFloat = 720
    var minSideMargin: CGFloat = 32
    var topInset: CGFloat = 44

    /// Raggio delle superfici di blocco (codice, tabelle).
    var surfaceRadius: CGFloat = 12
    /// Rientro del testo dentro una superficie di blocco.
    var surfacePadding: CGFloat = 16
    /// Passo di rientro di un livello di elenco.
    var listIndent: CGFloat = 24
    /// Passo di rientro di un livello di citazione.
    var quoteIndent: CGFloat = 22

    // MARK: - Font

    var body: NSFont { NSFont.systemFont(ofSize: bodySize, weight: .regular) }
    var mono: NSFont { NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular) }

    func heading(_ level: Int) -> NSFont {
        let scale: [CGFloat] = [1.85, 1.45, 1.20, 1.06, 0.98, 0.92]
        let l = max(1, min(6, level))
        let size = (bodySize * scale[l - 1]).rounded()
        let weight: NSFont.Weight = l <= 2 ? .bold : .semibold
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Crenatura dei titoli: ai corpi grandi le lettere vanno strette,
    /// altrimenti il peso diventa goffo.
    func headingTracking(_ level: Int) -> CGFloat {
        switch max(1, min(6, level)) {
        case 1: return -0.6
        case 2: return -0.4
        case 3, 4: return -0.2
        default: return 0
        }
    }

    /// Applica i tratti grassetto/corsivo mantenendo dimensione e famiglia.
    static func apply(bold: Bool, italic: Bool, to font: NSFont) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
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

    /// La pagina.
    let background = Theme.dynamic(light: Theme.gray(1.0), dark: Theme.gray(0.13))

    /// Testo corrente.
    let text = Theme.dynamic(light: Theme.gray(0.05), dark: Theme.gray(0.925))

    let headingText = Theme.dynamic(light: Theme.gray(0.04), dark: Theme.gray(0.97))

    /// Marcatori Markdown visibili sulla riga attiva: presenti ma non invadenti.
    let syntax = Theme.dynamic(light: Theme.gray(0.71), dark: Theme.gray(0.48))

    /// Speso solo su collegamenti e caselle spuntate.
    let accent = Theme.dynamic(
        light: NSColor(calibratedRed: 0.07, green: 0.494, blue: 0.388, alpha: 1),
        dark: NSColor(calibratedRed: 0.184, green: 0.722, blue: 0.561, alpha: 1))

    /// Testo di servizio: citazioni, numeri di elenco, voci barrate.
    let quoteText = Theme.dynamic(light: Theme.gray(0.365), dark: Theme.gray(0.64))

    let quoteBar = Theme.dynamic(light: Theme.gray(0.855), dark: Theme.gray(0.32))

    let codeText = Theme.dynamic(light: Theme.gray(0.13), dark: Theme.gray(0.87))

    /// La superficie condivisa da blocchi di codice e tabelle.
    let codeBackground = Theme.dynamic(
        light: NSColor(calibratedRed: 0.969, green: 0.969, blue: 0.973, alpha: 1),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.055))

    let inlineCodeBackground = Theme.dynamic(
        light: NSColor(calibratedRed: 0.949, green: 0.949, blue: 0.957, alpha: 1),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.085))

    let rule = Theme.dynamic(light: Theme.gray(0.91), dark: Theme.gray(0.26))

    /// Bordo della casella non spuntata.
    let controlBorder = Theme.dynamic(light: Theme.gray(0.78), dark: Theme.gray(0.42))

    let highlight = Theme.dynamic(
        light: NSColor(calibratedRed: 0.992, green: 0.937, blue: 0.706, alpha: 1),
        dark: NSColor(calibratedRed: 0.58, green: 0.50, blue: 0.16, alpha: 0.62))

    /// Nero come il testo: il cursore non è un elemento di marca.
    let insertionPoint = Theme.dynamic(light: Theme.gray(0.05), dark: Theme.gray(0.925))
}

extension NSAttributedString.Key {
    /// I caratteri con questo attributo non generano glifi (sintassi nascosta).
    static let auroraConceal = NSAttributedString.Key("auroraConceal")
    /// Decorazione di blocco disegnata dietro al testo: "code", "table", "hr".
    static let auroraBlock = NSAttributedString.Key("auroraBlock")
    /// Profondità della citazione, per disegnare le barre laterali.
    static let auroraQuoteDepth = NSAttributedString.Key("auroraQuoteDepth")
    /// Glifo da disegnare al posto del carattere (elenchi puntati, checkbox).
    static let auroraGlyph = NSAttributedString.Key("auroraGlyph")
    /// URL di un collegamento, gestito internamente (no attributo .link).
    static let auroraLink = NSAttributedString.Key("auroraLink")
    /// Range della checkbox di una task list; il valore è lo stato.
    static let auroraCheckbox = NSAttributedString.Key("auroraCheckbox")
}
