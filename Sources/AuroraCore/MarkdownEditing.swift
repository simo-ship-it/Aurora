import Foundation

/// Calcoli di editing che riguardano solo il testo e i suoi indici.
///
/// Stanno accanto al parser, e non nella vista, perché sono la parte che si
/// può sbagliare in silenzio: producono Markdown che *sembra* giusto finché
/// non lo si rilegge. Qui si possono provare senza aprire una finestra.
public enum MarkdownEditing {

    public struct InlineRemoval {
        public let replacementRange: NSRange
        public let replacement: String
        public let selectionAfterEdit: NSRange
    }

    public struct InlineApplication {
        public let replacementRange: NSRange
        public let replacement: String
        public let selectionAfterEdit: NSRange
    }

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

    /// Toglie uno solo degli stili applicati da una coppia di delimitatori.
    /// Con `***testo***`, per esempio, togliere il grassetto conserva `*testo*`
    /// e togliere il corsivo conserva `**testo**`.
    public static func removingInlineStyle(_ style: InlineStyle,
                                           from format: InlineFormatting,
                                           in ns: NSString,
                                           preserving selection: NSRange) -> InlineRemoval? {
        let content = format.contentRange
        let outer = NSRange(location: format.openingRange.location,
                            length: NSMaxRange(format.closingRange) - format.openingRange.location)
        guard format.style.contains(style),
              outer.location >= 0, NSMaxRange(outer) <= ns.length,
              selection.location >= outer.location,
              NSMaxRange(selection) <= NSMaxRange(outer) else { return nil }

        let (remainingOpening, remainingClosing) = remainingDelimiters(
            afterRemoving: style, from: format, in: ns)
        let inner = ns.substring(with: content)
        let visibleStart = max(selection.location, content.location)
        let visibleEnd = min(NSMaxRange(selection), NSMaxRange(content))
        let newLocation = outer.location + remainingOpening.utf16.count
            + max(0, visibleStart - content.location)
        return InlineRemoval(
            replacementRange: outer,
            replacement: remainingOpening + inner + remainingClosing,
            selectionAfterEdit: NSRange(location: newLocation,
                                        length: max(0, visibleEnd - visibleStart))
        )
    }

    /// Applica uno stile a una selezione che interseca segmenti già formattati.
    /// Prima elimina solo i delimitatori dello stesso stile, poi racchiude
    /// l'unione in una coppia unica. Evita risultati corrotti come
    /// `****grassetto** normale**`.
    public static func applyingInlineStyle(_ style: InlineStyle,
                                           to selection: NSRange,
                                           formats: [InlineFormatting],
                                           in ns: NSString,
                                           opening defaultOpening: String,
                                           closing defaultClosing: String) -> InlineApplication? {
        guard selection.length > 0, selection.location >= 0,
              NSMaxRange(selection) <= ns.length else { return nil }

        let overlapping = formats.filter { format in
            guard format.style.contains(style) else { return false }
            let content = format.contentRange
            return max(content.location, selection.location)
                < min(NSMaxRange(content), NSMaxRange(selection))
        }
        guard !overlapping.isEmpty else { return nil }

        let outerStart = overlapping.reduce(selection.location) {
            min($0, $1.openingRange.location)
        }
        let outerEnd = overlapping.reduce(NSMaxRange(selection)) {
            max($0, NSMaxRange($1.closingRange))
        }
        let outer = NSRange(location: outerStart, length: outerEnd - outerStart)

        struct Edit {
            let range: NSRange
            let replacement: String
        }
        var edits: [Edit] = []
        for format in overlapping {
            let remaining = remainingDelimiters(afterRemoving: style, from: format, in: ns)
            edits.append(Edit(range: format.openingRange, replacement: remaining.0))
            edits.append(Edit(range: format.closingRange, replacement: remaining.1))
        }

        var body = ns.substring(with: outer)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            let local = NSRange(location: edit.range.location - outer.location,
                                length: edit.range.length)
            body = (body as NSString).replacingCharacters(in: local, with: edit.replacement)
        }

        let orderedEdits = edits.sorted { $0.range.location < $1.range.location }
        func mapped(_ original: Int) -> Int {
            var result = original - outer.location
            for edit in orderedEdits {
                let delta = edit.replacement.utf16.count - edit.range.length
                if original >= NSMaxRange(edit.range) {
                    result += delta
                } else if original > edit.range.location {
                    result = edit.range.location - outer.location + edit.replacement.utf16.count
                }
            }
            return result
        }

        let delimiters = safeDelimiters(for: style, around: body,
                                        opening: defaultOpening, closing: defaultClosing)
        let start = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        let prefixLength = delimiters.0.utf16.count
        return InlineApplication(
            replacementRange: outer,
            replacement: delimiters.0 + body + delimiters.1,
            selectionAfterEdit: NSRange(location: outer.location + prefixLength + start,
                                        length: max(0, end - start))
        )
    }

    private static func remainingDelimiters(afterRemoving style: InlineStyle,
                                             from format: InlineFormatting,
                                             in ns: NSString) -> (String, String) {
        let opening = ns.substring(with: format.openingRange)
        let closing = ns.substring(with: format.closingRange)
        if style == .bold {
            return (String(opening.dropFirst(min(2, opening.utf16.count))),
                    String(closing.dropFirst(min(2, closing.utf16.count))))
        }
        if style == .italic {
            return (String(opening.dropFirst(min(1, opening.utf16.count))),
                    String(closing.dropFirst(min(1, closing.utf16.count))))
        }
        return ("", "")
    }

    /// Se il contenuto rimasto comincia con `*`, un nuovo `**` si fonderebbe
    /// con esso in `***`. In quel caso usa l'equivalente con underscore (e
    /// viceversa), mantenendo non ambigua la struttura Markdown.
    private static func safeDelimiters(for style: InlineStyle, around body: String,
                                       opening: String, closing: String) -> (String, String) {
        guard style == .bold || style == .italic else { return (opening, closing) }
        let first = body.first
        let last = body.last
        if opening.first == "*", first == "*" || last == "*" {
            let marker = style == .bold ? "__" : "_"
            return (marker, marker)
        }
        if opening.first == "_", first == "_" || last == "_" {
            let marker = style == .bold ? "**" : "*"
            return (marker, marker)
        }
        return (opening, closing)
    }

    /// Rende un titolo progressivamente più importante. Un paragrafo entra
    /// nella scala da H6, poi prosegue fino a H1.
    public static func promoteHeading(_ text: String) -> String {
        let (level, body) = heading(in: text)
        let next = level == 0 ? 6 : max(1, level - 1)
        return heading(body, level: next)
    }

    /// Percorre la scala inversa; dopo H6 si torna a un paragrafo normale.
    public static func demoteHeading(_ text: String) -> String {
        let (level, body) = heading(in: text)
        guard level > 0 else { return text }
        let next = level == 6 ? 0 : level + 1
        return heading(body, level: next)
    }

    private static func heading(in text: String) -> (level: Int, body: String) {
        let level = text.prefix { $0 == "#" }.count
        guard (1...6).contains(level), text.dropFirst(level).first == " " else {
            return (0, text)
        }
        return (level, String(text.dropFirst(level + 1)))
    }

    private static func heading(_ body: String, level: Int) -> String {
        level == 0 ? body : String(repeating: "#", count: level) + " " + body
    }
}
