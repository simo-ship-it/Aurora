import AppKit
import AuroraCore

/// Le colonne di una tabella Markdown, misurate una volta per tutta la tabella.
///
/// TextKit sa impaginare tabelle vere (`NSTextTable`), ma vuole una cella per
/// paragrafo: qui una riga intera è un paragrafo solo, quindi quella strada è
/// chiusa. Le colonne si ottengono allora con la crenatura — si allarga il
/// carattere che precede ogni cella quanto basta perché la cella cada al suo
/// posto — e il testo resta Markdown puro, com'è giusto che sia.
struct TableLayout {

    enum Alignment {
        case leading, center, trailing
    }

    /// Ascissa d'inizio di ogni colonna, dal margine interno del blocco.
    let columnStarts: [CGFloat]
    let columnWidths: [CGFloat]
    let alignments: [Alignment]

    /// Spazio fra il testo di una colonna e l'inizio della successiva.
    static let gutter: CGFloat = 24

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

    // MARK: - Allineamenti

    /// Legge `:---`, `:---:` e `---:` dalla riga dei trattini.
    static func alignments(from delimiter: LineInfo, in ns: NSString) -> [Alignment] {
        cells(of: delimiter, in: ns).map { cell in
            let testo = cell.text.trimmingCharacters(in: .whitespaces)
            let apre = testo.hasPrefix(":")
            let chiude = testo.hasSuffix(":")
            if apre && chiude { return .center }
            if chiude { return .trailing }
            return .leading
        }
    }

    // MARK: - Misura

    /// Calcola le colonne dalla larghezza massima di ogni cella.
    static func measure(rows: [(line: LineInfo, font: NSFont)],
                        delimiter: LineInfo?,
                        in ns: NSString) -> TableLayout {
        var widths: [CGFloat] = []
        for row in rows {
            for (index, cell) in cells(of: row.line, in: ns).enumerated() {
                let larghezza = (cell.text as NSString)
                    .size(withAttributes: [.font: row.font]).width
                if index < widths.count {
                    widths[index] = max(widths[index], larghezza)
                } else {
                    widths.append(larghezza)
                }
            }
        }

        var starts: [CGFloat] = []
        var x: CGFloat = 0
        for width in widths {
            starts.append(x)
            x += width + gutter
        }

        var aligns = delimiter.map { alignments(from: $0, in: ns) } ?? []
        while aligns.count < widths.count { aligns.append(.leading) }

        return TableLayout(columnStarts: starts,
                           columnWidths: widths,
                           alignments: Array(aligns.prefix(max(widths.count, 0))))
    }

    /// Dove deve cominciare il testo di una cella, secondo l'allineamento.
    func start(ofColumn index: Int, cellWidth: CGFloat) -> CGFloat {
        guard index < columnStarts.count else { return 0 }
        let start = columnStarts[index]
        let width = columnWidths[index]
        switch alignments.indices.contains(index) ? alignments[index] : .leading {
        case .leading: return start
        case .center: return start + (width - cellWidth) / 2
        case .trailing: return start + width - cellWidth
        }
    }
}
