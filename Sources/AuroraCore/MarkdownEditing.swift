import Foundation

/// Calcoli di editing che riguardano solo il testo e i suoi indici.
///
/// Stanno accanto al parser, e non nella vista, perché sono la parte che si
/// può sbagliare in silenzio: producono Markdown che *sembra* giusto finché
/// non lo si rilegge. Qui si possono provare senza aprire una finestra.
public enum MarkdownEditing {

    private static func isSpaceOrBreak(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    /// La porzione di una selezione che può stare dentro `**`, `*`, `~~`, `==`
    /// o un apice inverso.
    ///
    /// Un marcatore di emfasi non chiude se ha spazio subito dentro, e non
    /// attraversa un a capo. Una selezione che finisce con l'invio — quella di
    /// ⌘A su un documento che termina con una riga a capo, cioè quasi tutti —
    /// porterebbe il marcatore di chiusura su una riga a sé, e l'emfasi
    /// resterebbe aperta fino in fondo al documento. Lo spazio ai due estremi
    /// va quindi lasciato fuori.
    ///
    /// Se la selezione è fatta di soli spazi non c'è niente da enfatizzare: si
    /// restituisce un punto, e chi chiama inserirà i marcatori vuoti lì.
    public static func emphasisRange(in ns: NSString, selection: NSRange) -> NSRange {
        guard selection.length > 0 else { return selection }
        var start = selection.location
        var end = NSMaxRange(selection)
        while end > start, isSpaceOrBreak(ns.character(at: end - 1)) { end -= 1 }
        while start < end, isSpaceOrBreak(ns.character(at: start)) { start += 1 }
        return start < end
            ? NSRange(location: start, length: end - start)
            : NSRange(location: selection.location, length: 0)
    }
}
