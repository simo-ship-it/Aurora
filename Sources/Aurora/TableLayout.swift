import Foundation
import AuroraCore

/// Lettura delle celle dal Markdown sottostante. La disposizione visiva è
/// responsabilità di `InlineTableView`, che usa controlli AppKit reali.
enum TableLayout {

    // MARK: - Celle di una riga

    /// Il testo fra due barre verticali, con il suo intervallo nel documento.
    struct Cell {
        let range: NSRange      // il testo della cella, senza spazi ai lati
        let text: String
    }

    /// Divide una riga in celle. Le barre esterne sono facoltative, come in GFM.
    static func cells(of line: LineInfo, in ns: NSString) -> [Cell] {
        let start = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        guard end > start else { return [] }

        var cells: [Cell] = []
        var cursor = start
        // Una barra a inizio riga apre la prima cella invece di chiuderne una vuota.
        if ns.character(at: cursor) == 124 { cursor += 1 }

        var fieldStart = cursor
        var index = cursor
        func chiudi(at limit: Int) {
            var from = fieldStart, to = limit
            while from < to, isSpace(ns.character(at: from)) { from += 1 }
            while to > from, isSpace(ns.character(at: to - 1)) { to -= 1 }
            let range = NSRange(location: from, length: to - from)
            cells.append(Cell(range: range, text: ns.substring(with: range)))
        }

        while index < end {
            if ns.character(at: index) == 124 {
                chiudi(at: index)
                fieldStart = index + 1
            }
            index += 1
        }
        // Coda dopo l'ultima barra: è una cella solo se contiene qualcosa.
        if fieldStart < end {
            let resto = ns.substring(with: NSRange(location: fieldStart, length: end - fieldStart))
            if !resto.trimmingCharacters(in: .whitespaces).isEmpty { chiudi(at: end) }
        }
        return cells
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }
}
