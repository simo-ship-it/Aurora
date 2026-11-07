import Foundation

// Questo file è un modulo a sé, e importa solo Foundation. Il confine non è
// burocrazia: è il modo in cui il compilatore tiene fede a quello che il
// parser promette — leggere il testo e restituire indici, senza sapere nulla
// di font, colori o viste. È anche ciò che lo rende verificabile da solo.

// MARK: - Modello

public enum LineKind: Equatable {
    case blank
    case paragraph
    case heading(level: Int)
    case setextUnderline
    case bulletItem
    case orderedItem
    case listContinuation
    case fence           // la riga ``` di apertura o chiusura
    case codeBody
    case indentedCode
    case linkDefinition
    case horizontalRule
    case tableHeader
    case tableDelimiter
    case tableRow
}

public struct LineInfo {
    public var range: NSRange          // riga completa, terminatore incluso
    public var contentsEnd: Int        // fine del testo, terminatore escluso
    public var contentRange: NSRange   // testo dopo i prefissi di blocco (per il parsing inline)
    public var kind: LineKind = .paragraph
    public var quoteDepth: Int = 0
    public var listIndent: Int = 0     // livello di rientro dell'elenco (0, 1, 2, …)
    public var markers: [NSRange] = [] // sintassi di blocco da nascondere/attenuare
    public var bulletRange: NSRange?   // il carattere -, * o +
    public var orderedRange: NSRange?  // "1." di un elenco numerato
    public var listMarkerText = ""     // "-" oppure "1." — serve a continuare l'elenco con Invio
    public var checkboxRange: NSRange? // "[ ]" oppure "[x]"
    public var checkboxChecked = false
    public var isInsideFence = false
}

public struct InlineStyle: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold      = InlineStyle(rawValue: 1 << 0)
    public static let italic    = InlineStyle(rawValue: 1 << 1)
    public static let strike    = InlineStyle(rawValue: 1 << 2)
    public static let code      = InlineStyle(rawValue: 1 << 3)
    public static let link      = InlineStyle(rawValue: 1 << 4)
    public static let image     = InlineStyle(rawValue: 1 << 5)
    public static let highlight = InlineStyle(rawValue: 1 << 6)
    public static let underline = InlineStyle(rawValue: 1 << 7)
}

public struct InlineRun {
    public var range: NSRange
    public var style: InlineStyle
    public var url: String?
}

public struct InlineResult {
    public var runs: [InlineRun] = []
    public var markers: [NSRange] = []
    /// Coppie di delimitatori che applicano uno stile. Servono all'editor per
    /// togliere la formattazione anche quando il cursore è in mezzo al testo o
    /// la selezione ne copre solo una parte.
    public var formats: [InlineFormatting] = []
    public var images: [InlineImage] = []
}

public struct InlineFormatting {
    public var style: InlineStyle
    public var openingRange: NSRange
    public var closingRange: NSRange

    public var contentRange: NSRange {
        NSRange(location: NSMaxRange(openingRange),
                length: max(0, closingRange.location - NSMaxRange(openingRange)))
    }
}

public struct InlineImage {
    public var range: NSRange
    public var url: String
}

public struct LinkReference: Equatable {
    public var destination: String
    public var title: String?

    public init(destination: String, title: String? = nil) {
        self.destination = destination
        self.title = title
    }
}

public struct MarkdownAnalysis {
    public var lines: [LineInfo]
    public var references: [String: LinkReference]
}

// MARK: - Parser

public enum MarkdownParser {

    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09
    private static let hash: unichar = 0x23
    private static let gt: unichar = 0x3E
    private static let backtick: unichar = 0x60
    private static let tilde: unichar = 0x7E
    private static let star: unichar = 0x2A
    private static let dash: unichar = 0x2D
    private static let plus: unichar = 0x2B
    private static let underscore: unichar = 0x5F
    private static let backslash: unichar = 0x5C
    private static let bang: unichar = 0x21
    private static let openBracket: unichar = 0x5B
    private static let closeBracket: unichar = 0x5D
    private static let openParen: unichar = 0x28
    private static let closeParen: unichar = 0x29
    private static let equals: unichar = 0x3D
    private static let pipe: unichar = 0x7C
    private static let colon: unichar = 0x3A
    private static let lt: unichar = 0x3C

    private static func isBlank(_ c: unichar) -> Bool { c == space || c == tab }

    private static func isWordChar(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c > 0x7F
    }

    private static func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }

    // MARK: Blocchi

    /// Analizza l'intero documento. La prima passata riconosce le righe; le
    /// successive risolvono le strutture che dipendono dalle righe vicine.
    public static func analyze(_ ns: NSString) -> MarkdownAnalysis {
        var lines: [LineInfo] = []
        var index = 0
        var fenceChar: unichar = 0
        var fenceLength = 0
        var inFence = false

        while index < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            lines.append(parseLine(ns, start: start, end: end, contentsEnd: contentsEnd,
                                   inFence: &inFence, fenceChar: &fenceChar, fenceLength: &fenceLength))
            index = end
        }

        // Riga vuota finale (il documento termina con un a capo, o è vuoto).
        if ns.length == 0 || isLineBreak(ns.character(at: ns.length - 1)) {
            var last = LineInfo(range: NSRange(location: ns.length, length: 0),
                                contentsEnd: ns.length,
                                contentRange: NSRange(location: ns.length, length: 0))
            last.kind = inFence ? .codeBody : .blank
            last.isInsideFence = inFence
            lines.append(last)
        }

        let references = detectLinkDefinitions(ns, &lines)
        detectSetextHeadings(ns, &lines)
        detectContainerContinuations(ns, &lines)
        detectTables(ns, &lines)
        return MarkdownAnalysis(lines: lines, references: references)
    }

    public static func parse(_ ns: NSString) -> [LineInfo] { analyze(ns).lines }

    private static func isLineBreak(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029 }

    private static func parseLine(_ ns: NSString, start: Int, end: Int, contentsEnd: Int,
                                  inFence: inout Bool, fenceChar: inout unichar,
                                  fenceLength: inout Int) -> LineInfo {
        var line = LineInfo(range: NSRange(location: start, length: end - start),
                            contentsEnd: contentsEnd,
                            contentRange: NSRange(location: start, length: contentsEnd - start))
        let limit = contentsEnd
        var p = start

        // --- Citazioni annidate: "> ", ">> ", …
        if !inFence {
            while true {
                var probe = p
                var spaces = 0
                while probe < limit, isBlank(ns.character(at: probe)), spaces < 3 { probe += 1; spaces += 1 }
                guard probe < limit, ns.character(at: probe) == gt else { break }
                probe += 1
                if probe < limit, isBlank(ns.character(at: probe)) { probe += 1 }
                line.quoteDepth += 1
                line.markers.append(NSRange(location: p, length: probe - p))
                p = probe
            }
        }

        // --- Delimitatore di blocco di codice
        var probe = p
        var lead = 0
        while probe < limit, isBlank(ns.character(at: probe)), lead < 3 { probe += 1; lead += 1 }
        if probe < limit {
            let c = ns.character(at: probe)
            if c == backtick || c == tilde {
                var run = 0
                while probe + run < limit, ns.character(at: probe + run) == c { run += 1 }
                if run >= 3 {
                    if inFence {
                        var tail = probe + run
                        while tail < limit, isBlank(ns.character(at: tail)) { tail += 1 }
                        if c == fenceChar && run >= fenceLength && tail == limit {
                            inFence = false
                            line.kind = .fence
                            line.isInsideFence = true
                            line.contentRange = NSRange(location: contentsEnd, length: 0)
                            line.markers.append(NSRange(location: start, length: contentsEnd - start))
                            return line
                        }
                    } else {
                        // L'info string di un recinto aperto con apici inversi
                        // non può contenere altri apici inversi.
                        var validOpening = true
                        if c == backtick {
                            var tail = probe + run
                            while tail < limit {
                                if ns.character(at: tail) == backtick { validOpening = false; break }
                                tail += 1
                            }
                        }
                        if validOpening {
                            inFence = true
                            fenceChar = c
                            fenceLength = run
                            line.kind = .fence
                            line.isInsideFence = true
                            // Nasconde i backtick ma lascia visibile il nome del linguaggio.
                            line.markers.append(NSRange(location: probe, length: run))
                            line.contentRange = NSRange(location: probe + run, length: contentsEnd - probe - run)
                            return line
                        }
                    }
                }
            }
        }

        if inFence {
            line.kind = .codeBody
            line.isInsideFence = true
            line.contentRange = NSRange(location: p, length: contentsEnd - p)
            return line
        }

        // --- Riga vuota
        var onlyBlanks = true
        var scan = p
        while scan < limit {
            if !isBlank(ns.character(at: scan)) { onlyBlanks = false; break }
            scan += 1
        }
        if onlyBlanks {
            line.kind = line.quoteDepth > 0 ? .paragraph : .blank
            line.contentRange = NSRange(location: contentsEnd, length: 0)
            return line
        }

        // --- Rientro (elenchi e allineamento)
        var indentColumns = 0
        var afterIndent = p
        while afterIndent < limit {
            let c = ns.character(at: afterIndent)
            if c == space { indentColumns += 1; afterIndent += 1 }
            else if c == tab { indentColumns += 4; afterIndent += 1 }
            else { break }
        }

        // --- Linea orizzontale: ---, ***, ___
        if indentColumns <= 3, isHorizontalRule(ns, from: afterIndent, to: limit) {
            line.kind = .horizontalRule
            line.contentRange = NSRange(location: contentsEnd, length: 0)
            line.markers.append(NSRange(location: p, length: contentsEnd - p))
            return line
        }

        // --- Titoli ATX
        if indentColumns <= 3, afterIndent < limit, ns.character(at: afterIndent) == hash {
            var level = 0
            var q = afterIndent
            while q < limit, ns.character(at: q) == hash, level < 7 { level += 1; q += 1 }
            let followedBySpace = (q >= limit) || isBlank(ns.character(at: q))
            if level >= 1 && level <= 6 && followedBySpace {
                var contentStart = q
                while contentStart < limit, isBlank(ns.character(at: contentStart)) { contentStart += 1 }
                line.kind = .heading(level: level)
                line.markers.append(NSRange(location: p, length: contentStart - p))

                // Cancelletti di chiusura opzionali: "## Titolo ##"
                var tail = limit
                while tail > contentStart, isBlank(ns.character(at: tail - 1)) { tail -= 1 }
                var hashEnd = tail
                while hashEnd > contentStart, ns.character(at: hashEnd - 1) == hash { hashEnd -= 1 }
                if hashEnd < tail, hashEnd > contentStart, isBlank(ns.character(at: hashEnd - 1)) {
                    line.markers.append(NSRange(location: hashEnd - 1, length: contentsEnd - hashEnd + 1))
                    tail = hashEnd - 1
                } else {
                    tail = contentsEnd
                }
                line.contentRange = NSRange(location: contentStart, length: max(0, tail - contentStart))
                return line
            }
        }

        // --- Elenchi puntati e numerati
        if afterIndent < limit {
            let c = ns.character(at: afterIndent)
            var markerEnd = -1
            var ordered = false

            if c == dash || c == star || c == plus {
                if afterIndent + 1 >= limit || isBlank(ns.character(at: afterIndent + 1)) {
                    markerEnd = afterIndent + 1
                }
            } else if isDigit(c) {
                var q = afterIndent
                var digits = 0
                while q < limit, isDigit(ns.character(at: q)), digits < 9 { q += 1; digits += 1 }
                if q < limit, ns.character(at: q) == 0x2E || ns.character(at: q) == closeParen {
                    q += 1
                    if q >= limit || isBlank(ns.character(at: q)) {
                        markerEnd = q
                        ordered = true
                    }
                }
            }

            if markerEnd >= 0 {
                var contentStart = markerEnd
                while contentStart < limit, isBlank(ns.character(at: contentStart)) { contentStart += 1 }
                line.kind = ordered ? .orderedItem : .bulletItem
                line.listIndent = indentColumns / 2
                line.listMarkerText = ns.substring(with: NSRange(location: afterIndent,
                                                                length: markerEnd - afterIndent))
                if ordered {
                    line.orderedRange = NSRange(location: afterIndent, length: markerEnd - afterIndent)
                } else {
                    line.bulletRange = NSRange(location: afterIndent, length: 1)
                }
                // Il rientro è sostituito dal rientro tipografico; dopo il marcatore
                // resta un solo spazio, così il testo non si sposta quando la riga si attiva.
                if afterIndent > p { line.markers.append(NSRange(location: p, length: afterIndent - p)) }
                if contentStart > markerEnd + 1 {
                    line.markers.append(NSRange(location: markerEnd + 1, length: contentStart - markerEnd - 1))
                }

                // Task list: "- [ ] " oppure "- [x] "
                if contentStart + 2 < limit,
                   ns.character(at: contentStart) == openBracket,
                   ns.character(at: contentStart + 2) == closeBracket {
                    let mark = ns.character(at: contentStart + 1)
                    let isChecked = (mark == 0x78 || mark == 0x58)   // x o X
                    let empty = isBlank(mark)
                    let followedByWhitespace = contentStart + 3 >= limit
                        || isBlank(ns.character(at: contentStart + 3))
                    if (empty || isChecked) && followedByWhitespace {
                        line.checkboxRange = NSRange(location: contentStart, length: 3)
                        line.checkboxChecked = isChecked
                        // Il marcatore dell'elenco cede il posto alla casella.
                        if let bullet = line.bulletRange {
                            line.markers.append(NSRange(location: bullet.location,
                                                        length: contentStart - bullet.location))
                            line.bulletRange = nil
                        }
                        contentStart += 3
                        var afterBox = contentStart
                        while afterBox < limit, isBlank(ns.character(at: afterBox)) { afterBox += 1 }
                        if afterBox > contentStart + 1 {
                            line.markers.append(NSRange(location: contentStart + 1,
                                                        length: afterBox - contentStart - 1))
                        }
                        contentStart = afterBox
                    }
                }

                line.contentRange = NSRange(location: contentStart, length: max(0, contentsEnd - contentStart))
                return line
            }
        }

        // --- Blocco di codice rientrato. Gli elenchi hanno precedenza per
        // conservare i livelli a due spazi usati dall'editor.
        if indentColumns >= 4 {
            var contentStart = p
            var columns = 0
            while contentStart < limit, columns < 4 {
                let c = ns.character(at: contentStart)
                if c == space { columns += 1; contentStart += 1 }
                else if c == tab { columns = 4; contentStart += 1 }
                else { break }
            }
            line.kind = .indentedCode
            line.isInsideFence = true
            line.markers.append(NSRange(location: p, length: contentStart - p))
            line.contentRange = NSRange(location: contentStart, length: contentsEnd - contentStart)
            return line
        }

        line.kind = .paragraph
        line.contentRange = NSRange(location: afterIndent, length: max(0, contentsEnd - afterIndent))
        return line
    }

    private static func isHorizontalRule(_ ns: NSString, from: Int, to: Int) -> Bool {
        guard from < to else { return false }
        let c = ns.character(at: from)
        guard c == dash || c == star || c == underscore else { return false }
        var count = 0
        var i = from
        while i < to {
            let ch = ns.character(at: i)
            if ch == c { count += 1 }
            else if !isBlank(ch) { return false }
            i += 1
        }
        return count >= 3
    }

    // MARK: Strutture che dipendono dalle righe vicine

    private static func detectLinkDefinitions(_ ns: NSString,
                                              _ lines: inout [LineInfo]) -> [String: LinkReference] {
        var references: [String: LinkReference] = [:]
        for index in lines.indices where lines[index].kind == .paragraph {
            guard let definition = linkReferenceDefinition(ns, line: lines[index]) else { continue }
            if references[definition.label] == nil {
                references[definition.label] = LinkReference(destination: definition.destination,
                                                             title: definition.title)
            }
            lines[index].kind = .linkDefinition
        }
        return references
    }

    private static func linkReferenceDefinition(_ ns: NSString, line: LineInfo)
        -> (label: String, destination: String, title: String?)? {
        let start = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        guard start + 3 < end, ns.character(at: start) == openBracket else { return nil }

        var close = start + 1
        while close < end {
            if ns.character(at: close) == backslash { close += 2; continue }
            if ns.character(at: close) == closeBracket { break }
            close += 1
        }
        guard close < end, close + 1 < end, ns.character(at: close + 1) == colon else { return nil }

        let rawLabel = ns.substring(with: NSRange(location: start + 1, length: close - start - 1))
        let label = normalizedLabel(rawLabel)
        guard !label.isEmpty else { return nil }

        var cursor = close + 2
        while cursor < end, isBlank(ns.character(at: cursor)) { cursor += 1 }
        guard cursor < end else { return nil }

        let destination: String
        if ns.character(at: cursor) == lt {
            let valueStart = cursor + 1
            cursor = valueStart
            while cursor < end, ns.character(at: cursor) != 0x3E,
                  !isLineBreak(ns.character(at: cursor)) { cursor += 1 }
            guard cursor < end, ns.character(at: cursor) == 0x3E else { return nil }
            destination = ns.substring(with: NSRange(location: valueStart, length: cursor - valueStart))
            cursor += 1
        } else {
            let valueStart = cursor
            var depth = 0
            while cursor < end {
                let c = ns.character(at: cursor)
                if c == backslash { cursor = min(end, cursor + 2); continue }
                if isBlank(c) { break }
                if c == openParen { depth += 1 }
                if c == closeParen {
                    if depth == 0 { break }
                    depth -= 1
                }
                cursor += 1
            }
            guard cursor > valueStart, depth == 0 else { return nil }
            destination = ns.substring(with: NSRange(location: valueStart, length: cursor - valueStart))
        }

        while cursor < end, isBlank(ns.character(at: cursor)) { cursor += 1 }
        var title: String?
        if cursor < end {
            let opener = ns.character(at: cursor)
            let closer: unichar
            if opener == 0x22 || opener == 0x27 { closer = opener }
            else if opener == openParen { closer = closeParen }
            else { return nil }
            cursor += 1
            let titleStart = cursor
            while cursor < end, ns.character(at: cursor) != closer {
                if ns.character(at: cursor) == backslash { cursor += 2 } else { cursor += 1 }
            }
            guard cursor < end else { return nil }
            title = ns.substring(with: NSRange(location: titleStart, length: cursor - titleStart))
            cursor += 1
            while cursor < end, isBlank(ns.character(at: cursor)) { cursor += 1 }
        }
        guard cursor == end else { return nil }
        return (label, unescape(destination), title)
    }

    private static func detectSetextHeadings(_ ns: NSString, _ lines: inout [LineInfo]) {
        guard lines.count > 1 else { return }
        for index in 1..<lines.count {
            guard lines[index - 1].kind == .paragraph,
                  lines[index - 1].quoteDepth == lines[index].quoteDepth,
                  let level = setextLevel(ns, line: lines[index]) else { continue }
            lines[index - 1].kind = .heading(level: level)
            lines[index].kind = .setextUnderline
            let syntax = NSRange(location: lines[index].contentRange.location,
                                 length: lines[index].contentsEnd - lines[index].contentRange.location)
            if syntax.length > 0 { lines[index].markers = [syntax] }
            lines[index].contentRange = NSRange(location: lines[index].contentsEnd, length: 0)
        }
    }

    private static func setextLevel(_ ns: NSString, line: LineInfo) -> Int? {
        guard line.kind == .paragraph || line.kind == .horizontalRule else { return nil }
        let candidate = line.kind == .horizontalRule
            ? (line.markers.last ?? line.contentRange)
            : line.contentRange
        var start = candidate.location
        var end = NSMaxRange(candidate)
        while start < end, isBlank(ns.character(at: start)) { start += 1 }
        while end > start, isBlank(ns.character(at: end - 1)) { end -= 1 }
        guard start < end else { return nil }
        let marker = ns.character(at: start)
        guard marker == equals || marker == dash else { return nil }
        var cursor = start
        while cursor < end, ns.character(at: cursor) == marker { cursor += 1 }
        guard cursor == end else { return nil }
        return marker == equals ? 1 : 2
    }

    private static func detectContainerContinuations(_ ns: NSString, _ lines: inout [LineInfo]) {
        guard lines.count > 1 else { return }
        for index in 1..<lines.count where lines[index].kind == .paragraph {
            let previous = lines[index - 1]
            guard previous.kind != .blank else { continue }

            // CommonMark consente di omettere il marcatore `>` nelle righe di
            // continuazione di un paragrafo citato.
            if lines[index].quoteDepth == 0, previous.quoteDepth > 0,
               previous.kind == .paragraph || previous.kind == .listContinuation
                    || previous.kind == .bulletItem || previous.kind == .orderedItem {
                lines[index].quoteDepth = previous.quoteDepth
            }

            if previous.kind == .bulletItem || previous.kind == .orderedItem
                || previous.kind == .listContinuation {
                lines[index].kind = .listContinuation
                lines[index].listIndent = previous.listIndent
            }
        }
        _ = ns
    }

    /// Seconda passata: una riga di intestazione seguita da "| --- | --- |" apre una tabella.
    private static func detectTables(_ ns: NSString, _ lines: inout [LineInfo]) {
        var i = 0
        while i < lines.count {
            guard !lines[i].isInsideFence, let delimiterColumns = delimiterColumnCount(ns, lines[i]),
                  i > 0, lines[i - 1].kind == .paragraph,
                  tableCellCount(ns, lines[i - 1]) == delimiterColumns else { i += 1; continue }
            lines[i - 1].kind = .tableHeader
            lines[i].kind = .tableDelimiter
            var j = i + 1
            while j < lines.count, lines[j].kind == .paragraph, containsUnescapedPipe(ns, lines[j]) {
                lines[j].kind = .tableRow
                j += 1
            }
            i = j
        }
    }

    private static func containsUnescapedPipe(_ ns: NSString, _ line: LineInfo) -> Bool {
        var i = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        while i < end {
            if ns.character(at: i) == backslash { i += 2; continue }
            if i < end, ns.character(at: i) == pipe { return true }
            i += 1
        }
        return false
    }

    private static func tableCellCount(_ ns: NSString, _ line: LineInfo) -> Int {
        var start = line.contentRange.location
        var end = NSMaxRange(line.contentRange)
        while start < end, isBlank(ns.character(at: start)) { start += 1 }
        while end > start, isBlank(ns.character(at: end - 1)) { end -= 1 }
        guard start < end else { return 0 }
        var pipes = 0
        var cursor = start
        while cursor < end {
            if ns.character(at: cursor) == backslash { cursor += 2; continue }
            if cursor < end, ns.character(at: cursor) == pipe { pipes += 1 }
            cursor += 1
        }
        guard pipes > 0 else { return 0 }
        let leading = ns.character(at: start) == pipe
        let trailing = ns.character(at: end - 1) == pipe
        return max(0, pipes + 1 - (leading ? 1 : 0) - (trailing ? 1 : 0))
    }

    /// Riga di delimitazione: ogni cella dev'essere fatta di trattini, con
    /// eventuali due punti ai lati per l'allineamento. GFM ne chiede **uno per
    /// cella**, non tre in tutta la riga: `| - | - |` è una tabella valida.
    private static func delimiterColumnCount(_ ns: NSString, _ line: LineInfo) -> Int? {
        let start = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        guard end > start else { return nil }

        /// `nil` se la cella è vuota (le barre esterne ne creano una per lato).
        func valida(_ from: Int, _ to: Int) -> Bool? {
            var a = from, b = to
            while a < b, isBlank(ns.character(at: a)) { a += 1 }
            while b > a, isBlank(ns.character(at: b - 1)) { b -= 1 }
            guard a < b else { return nil }
            var i = a
            if ns.character(at: i) == colon { i += 1 }
            var trattini = 0
            while i < b, ns.character(at: i) == dash { i += 1; trattini += 1 }
            if i < b, ns.character(at: i) == colon { i += 1 }
            return i == b && trattini >= 1
        }

        var pipes = 0, celle = 0, cellStart = start, index = start
        while index < end {
            if ns.character(at: index) == pipe {
                pipes += 1
                if let ok = valida(cellStart, index) {
                    guard ok else { return nil }
                    celle += 1
                }
                cellStart = index + 1
            }
            index += 1
        }
        if let ok = valida(cellStart, end) {
            guard ok else { return nil }
            celle += 1
        }
        return celle >= 1 && pipes >= 1 ? celle : nil
    }

    // MARK: Inline

    public static func parseInline(_ ns: NSString, range: NSRange) -> InlineResult {
        parseInline(ns, range: range, references: analyze(ns).references)
    }

    public static func parseInline(_ ns: NSString, range: NSRange,
                                   references: [String: LinkReference]) -> InlineResult {
        var out = InlineResult()
        guard range.length > 0 else { return out }
        parseInline(ns, range: range, style: [], url: nil, references: references, into: &out)
        return out
    }

    private static func parseInline(_ ns: NSString, range: NSRange, style: InlineStyle,
                                    url: String?, references: [String: LinkReference],
                                    into out: inout InlineResult) {
        var i = range.location
        let end = NSMaxRange(range)
        var plainStart = i

        func emit(upTo idx: Int) {
            if idx > plainStart {
                out.runs.append(InlineRun(range: NSRange(location: plainStart, length: idx - plainStart),
                                          style: style, url: url))
            }
        }

        while i < end {
            let c = ns.character(at: i)

            // Escape: \*
            if c == backslash, i + 1 < end, isEscapablePunctuation(ns.character(at: i + 1)) {
                emit(upTo: i)
                out.markers.append(NSRange(location: i, length: 1))
                i += 2
                plainStart = i
                continue
            }

            // Codice inline: `x`, ``x``
            if c == backtick {
                var run = 0
                while i + run < end, ns.character(at: i + run) == backtick { run += 1 }
                if let close = findLiteralRun(ns, char: backtick, count: run, from: i + run, end: end) {
                    emit(upTo: i)
                    let opening = NSRange(location: i, length: run)
                    let closing = NSRange(location: close, length: run)
                    out.markers.append(opening)
                    let content = NSRange(location: i + run, length: close - i - run)
                    if content.length > 0 {
                        out.runs.append(InlineRun(range: content, style: style.union(.code), url: url))
                    }
                    out.markers.append(closing)
                    out.formats.append(InlineFormatting(style: .code,
                                                        openingRange: opening,
                                                        closingRange: closing))
                    i = close + run
                    plainStart = i
                    continue
                }
            }

            // Markdown non ha una sintassi nativa per il sottolineato. Aurora
            // conserva quindi il comune HTML inline: <u>testo</u>.
            if c == lt, i + 3 <= end,
               ns.substring(with: NSRange(location: i, length: 3)).lowercased() == "<u>" {
                let search = NSRange(location: i + 3, length: end - i - 3)
                let close = ns.range(of: "</u>", options: [.caseInsensitive], range: search)
                if close.location != NSNotFound {
                    emit(upTo: i)
                    let opening = NSRange(location: i, length: 3)
                    let content = NSRange(location: i + 3, length: close.location - i - 3)
                    out.markers.append(opening)
                    parseInline(ns, range: content, style: style.union(.underline), url: url,
                                references: references, into: &out)
                    out.markers.append(close)
                    out.formats.append(InlineFormatting(style: .underline,
                                                        openingRange: opening,
                                                        closingRange: close))
                    i = NSMaxRange(close)
                    plainStart = i
                    continue
                }
            }

            // Immagini: ![alt](url)
            if c == bang, i + 1 < end, ns.character(at: i + 1) == openBracket,
               let link = matchAnyLink(ns, from: i + 1, end: end, references: references) {
                emit(upTo: i)
                out.markers.append(NSRange(location: i, length: 2))                 // "!["
                if link.text.length > 0 {
                    out.images.append(InlineImage(range: link.text, url: link.url))
                }
                parseInline(ns, range: link.text, style: style.union(.image), url: link.url,
                            references: references, into: &out)
                out.markers.append(NSRange(location: NSMaxRange(link.text),
                                           length: link.end - NSMaxRange(link.text)))
                i = link.end
                plainStart = i
                continue
            }

            // Collegamenti: [testo](url)
            if c == openBracket, let link = matchAnyLink(ns, from: i, end: end, references: references) {
                emit(upTo: i)
                out.markers.append(NSRange(location: i, length: 1))                 // "["
                parseInline(ns, range: link.text, style: style.union(.link), url: link.url,
                            references: references, into: &out)
                out.markers.append(NSRange(location: NSMaxRange(link.text),
                                           length: link.end - NSMaxRange(link.text)))
                i = link.end
                plainStart = i
                continue
            }

            // Autolink CommonMark: <https://…> e <nome@example.com>.
            if c == lt, let link = matchAngleAutolink(ns, from: i, end: end) {
                emit(upTo: i)
                let content = NSRange(location: i + 1, length: link.close - i - 1)
                out.markers.append(NSRange(location: i, length: 1))
                out.runs.append(InlineRun(range: content, style: style.union(.link),
                                          url: link.url))
                out.markers.append(NSRange(location: link.close, length: 1))
                i = link.close + 1
                plainStart = i
                continue
            }

            // Estensione GFM: URL, www ed email senza parentesi angolari.
            if let link = matchBareAutolink(ns, from: i, end: end) {
                emit(upTo: i)
                out.runs.append(InlineRun(range: link.range, style: style.union(.link), url: link.url))
                i = NSMaxRange(link.range)
                plainStart = i
                continue
            }

            // Barrato ~~x~~ ed evidenziato ==x==
            if c == tilde || c == equals {
                let added: InlineStyle = (c == tilde) ? .strike : .highlight
                if i + 1 < end, ns.character(at: i + 1) == c,
                   let close = findDelimiter(ns, char: c, count: 2, from: i + 2, end: end) {
                    emit(upTo: i)
                    let opening = NSRange(location: i, length: 2)
                    let closing = NSRange(location: close, length: 2)
                    out.markers.append(opening)
                    parseInline(ns, range: NSRange(location: i + 2, length: close - i - 2),
                                style: style.union(added), url: url, references: references, into: &out)
                    out.markers.append(closing)
                    out.formats.append(InlineFormatting(style: added,
                                                        openingRange: opening,
                                                        closingRange: closing))
                    i = close + 2
                    plainStart = i
                    continue
                }
            }

            // Enfasi: *x*, **x**, ***x***, _x_, __x__
            if c == star || c == underscore {
                var run = 0
                while i + run < end, ns.character(at: i + run) == c, run < 3 { run += 1 }
                let opensWell = i + run < end && !isInlineWhitespace(ns.character(at: i + run))
                // Gli underscore non spezzano snake_case.
                let intraword = (c == underscore) && i > 0 && isWordChar(ns.character(at: i - 1))
                if opensWell, !intraword,
                   let close = findDelimiter(ns, char: c, count: run, from: i + run, end: end) {
                    var added: InlineStyle = []
                    if run == 1 { added = .italic }
                    else if run == 2 { added = .bold }
                    else { added = [.bold, .italic] }
                    emit(upTo: i)
                    let opening = NSRange(location: i, length: run)
                    let closing = NSRange(location: close, length: run)
                    out.markers.append(opening)
                    parseInline(ns, range: NSRange(location: i + run, length: close - i - run),
                                style: style.union(added), url: url, references: references, into: &out)
                    out.markers.append(closing)
                    out.formats.append(InlineFormatting(style: added,
                                                        openingRange: opening,
                                                        closingRange: closing))
                    i = close + run
                    plainStart = i
                    continue
                }
            }

            i += 1
        }
        emit(upTo: end)
    }

    /// Cerca una sequenza chiusa senza interpretare escape (per il codice inline).
    private static func findLiteralRun(_ ns: NSString, char: unichar, count: Int, from: Int, end: Int) -> Int? {
        var i = from
        while i < end {
            if ns.character(at: i) == char {
                var run = 0
                while i + run < end, ns.character(at: i + run) == char { run += 1 }
                if run == count { return i }
                i += run
            } else {
                i += 1
            }
        }
        return nil
    }

    /// Cerca il delimitatore di chiusura di un'enfasi, saltando gli escape.
    private static func findDelimiter(_ ns: NSString, char: unichar, count: Int, from: Int, end: Int) -> Int? {
        var i = from
        while i < end {
            let c = ns.character(at: i)
            if c == backslash { i += 2; continue }
            if c == char {
                var run = 0
                while i + run < end, ns.character(at: i + run) == char { run += 1 }
                if run >= count, i > from, !isInlineWhitespace(ns.character(at: i - 1)) {
                    return i + run - count   // consuma i delimitatori più interni
                }
                i += run
                continue
            }
            i += 1
        }
        return nil
    }

    private struct LinkMatch {
        var text: NSRange   // contenuto fra parentesi quadre
        var url: String
        var end: Int        // indice subito dopo la parentesi tonda di chiusura
    }

    private static func matchAnyLink(_ ns: NSString, from: Int, end: Int,
                                     references: [String: LinkReference]) -> LinkMatch? {
        matchInlineLink(ns, from: from, end: end)
            ?? matchReferenceLink(ns, from: from, end: end, references: references)
    }

    private static func closingBracket(_ ns: NSString, from: Int, end: Int) -> Int? {
        guard from < end, ns.character(at: from) == openBracket else { return nil }
        var depth = 1
        var i = from + 1
        while i < end {
            let c = ns.character(at: i)
            if c == backslash { i += 2; continue }
            if c == openBracket { depth += 1 }
            else if c == closeBracket {
                depth -= 1
                if depth == 0 { break }
            }
            i += 1
        }
        return i < end && depth == 0 ? i : nil
    }

    private static func matchInlineLink(_ ns: NSString, from: Int, end: Int) -> LinkMatch? {
        guard let i = closingBracket(ns, from: from, end: end) else { return nil }
        let textRange = NSRange(location: from + 1, length: i - from - 1)
        var j = i + 1
        guard j < end, ns.character(at: j) == openParen else { return nil }
        j += 1
        while j < end, isInlineWhitespace(ns.character(at: j)) { j += 1 }

        let destination: String
        if j < end, ns.character(at: j) == lt {
            let valueStart = j + 1
            j = valueStart
            while j < end {
                let c = ns.character(at: j)
                if c == backslash { j += 2; continue }
                if c == 0x3E { break }
                if c == lt || isLineBreak(c) { return nil }
                j += 1
            }
            guard j < end, ns.character(at: j) == 0x3E else { return nil }
            destination = ns.substring(with: NSRange(location: valueStart, length: j - valueStart))
            j += 1
        } else {
            let valueStart = j
            var depth = 0
            while j < end {
                let c = ns.character(at: j)
                if c == backslash { j += 2; continue }
                if isInlineWhitespace(c) { break }
                if c == openParen { depth += 1; j += 1; continue }
                if c == closeParen {
                    if depth == 0 { break }
                    depth -= 1
                }
                j += 1
            }
            guard depth == 0 else { return nil }
            destination = ns.substring(with: NSRange(location: valueStart, length: j - valueStart))
        }

        while j < end, isInlineWhitespace(ns.character(at: j)) { j += 1 }
        if j < end, ns.character(at: j) != closeParen {
            let opener = ns.character(at: j)
            let closer: unichar
            if opener == 0x22 || opener == 0x27 { closer = opener }
            else if opener == openParen { closer = closeParen }
            else { return nil }
            j += 1
            while j < end, ns.character(at: j) != closer {
                if ns.character(at: j) == backslash { j += 2 } else { j += 1 }
            }
            guard j < end else { return nil }
            j += 1
            while j < end, isInlineWhitespace(ns.character(at: j)) { j += 1 }
        }
        guard j < end, ns.character(at: j) == closeParen else { return nil }
        return LinkMatch(text: textRange, url: unescape(destination), end: j + 1)
    }

    private static func matchReferenceLink(_ ns: NSString, from: Int, end: Int,
                                           references: [String: LinkReference]) -> LinkMatch? {
        guard !references.isEmpty,
              let textEnd = closingBracket(ns, from: from, end: end) else { return nil }
        let text = NSRange(location: from + 1, length: textEnd - from - 1)
        let textLabel = ns.substring(with: text)
        var syntaxEnd = textEnd + 1
        var label = textLabel

        if syntaxEnd < end, ns.character(at: syntaxEnd) == openBracket {
            let labelStart = syntaxEnd + 1
            var labelEnd = labelStart
            while labelEnd < end, ns.character(at: labelEnd) != closeBracket {
                if ns.character(at: labelEnd) == backslash { labelEnd += 2 }
                else if ns.character(at: labelEnd) == openBracket { return nil }
                else { labelEnd += 1 }
            }
            guard labelEnd < end else { return nil }
            label = labelEnd == labelStart
                ? textLabel
                : ns.substring(with: NSRange(location: labelStart, length: labelEnd - labelStart))
            syntaxEnd = labelEnd + 1
        }

        guard let reference = references[normalizedLabel(label)] else { return nil }
        return LinkMatch(text: text, url: reference.destination, end: syntaxEnd)
    }

    private struct AngleAutolink {
        var close: Int
        var url: String
    }

    private static func matchAngleAutolink(_ ns: NSString, from: Int, end: Int) -> AngleAutolink? {
        var close = from + 1
        while close < end {
            let c = ns.character(at: close)
            if c == 0x3E { break }
            if c == lt || isInlineWhitespace(c) || c < 0x20 { return nil }
            close += 1
        }
        guard close < end, close > from + 1 else { return nil }
        let raw = ns.substring(with: NSRange(location: from + 1, length: close - from - 1))
        if isValidEmail(raw) { return AngleAutolink(close: close, url: "mailto:" + raw) }
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = String(raw[..<colon])
        guard isValidScheme(scheme) else { return nil }
        return AngleAutolink(close: close, url: raw)
    }

    private struct BareAutolink {
        var range: NSRange
        var url: String
    }

    private static func matchBareAutolink(_ ns: NSString, from: Int, end: Int) -> BareAutolink? {
        guard from < end, bareAutolinkCanStart(ns, at: from) else { return nil }
        let remaining = NSRange(location: from, length: end - from)
        let prefixes = [("https://", ""), ("http://", ""), ("www.", "http://")]
        for (prefix, addedScheme) in prefixes {
            let prefixRange = ns.range(of: prefix, options: [], range: remaining)
            guard prefixRange.location == from else { continue }
            var limit = from + prefix.utf16.count
            while limit < end {
                let c = ns.character(at: limit)
                if isInlineWhitespace(c) || c == lt { break }
                limit += 1
            }
            limit = trimAutolinkEnd(ns, from: from, end: limit)
            guard limit > from + prefix.utf16.count else { return nil }
            let value = ns.substring(with: NSRange(location: from, length: limit - from))
            let candidate = addedScheme + value
            guard let url = URL(string: candidate), url.host?.contains(".") == true else { return nil }
            return BareAutolink(range: NSRange(location: from, length: limit - from), url: candidate)
        }

        let first = ns.character(at: from)
        guard isEmailLocalCharacter(first) else { return nil }
        var limit = from
        while limit < end {
            let c = ns.character(at: limit)
            if isInlineWhitespace(c) || c == lt || c == 0x3E { break }
            limit += 1
        }
        limit = trimAutolinkEnd(ns, from: from, end: limit)
        let value = ns.substring(with: NSRange(location: from, length: limit - from))
        guard isValidEmail(value) else { return nil }
        return BareAutolink(range: NSRange(location: from, length: limit - from), url: "mailto:" + value)
    }

    private static func bareAutolinkCanStart(_ ns: NSString, at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = ns.character(at: index - 1)
        return isInlineWhitespace(previous) || previous == star || previous == underscore
            || previous == tilde || previous == openParen
    }

    private static func trimAutolinkEnd(_ ns: NSString, from: Int, end: Int) -> Int {
        var limit = end
        let trailing: Set<unichar> = [0x3F, 0x21, 0x2E, 0x2C, colon, star, underscore, tilde]
        while limit > from, trailing.contains(ns.character(at: limit - 1)) { limit -= 1 }
        while limit > from, ns.character(at: limit - 1) == closeParen {
            var opens = 0, closes = 0, cursor = from
            while cursor < limit {
                if ns.character(at: cursor) == openParen { opens += 1 }
                if ns.character(at: cursor) == closeParen { closes += 1 }
                cursor += 1
            }
            if closes > opens { limit -= 1 } else { break }
        }
        return limit
    }

    private static func isValidScheme(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard (2...32).contains(scalars.count), let first = scalars.first,
              (65...90).contains(first.value) || (97...122).contains(first.value) else { return false }
        return scalars.dropFirst().allSatisfy {
            (65...90).contains($0.value) || (97...122).contains($0.value)
                || (48...57).contains($0.value) || $0 == "+" || $0 == "." || $0 == "-"
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        return parts[0].unicodeScalars.allSatisfy { isEmailLocalCharacter(unichar($0.value)) }
            && parts[1].unicodeScalars.allSatisfy {
                (48...57).contains($0.value) || (65...90).contains($0.value)
                    || (97...122).contains($0.value) || $0 == "." || $0 == "-" || $0 == "_"
            }
    }

    private static func isEmailLocalCharacter(_ c: unichar) -> Bool {
        isWordChar(c) || c == 0x2E || c == dash || c == underscore || c == plus
    }

    private static func isInlineWhitespace(_ c: unichar) -> Bool {
        isBlank(c) || isLineBreak(c)
    }

    private static func isEscapablePunctuation(_ c: unichar) -> Bool {
        (c >= 0x21 && c <= 0x2F) || (c >= 0x3A && c <= 0x40)
            || (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7E)
    }

    private static func normalizedLabel(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for scalar in value.unicodeScalars {
            if escaping {
                if scalar.value <= UInt16.max, isEscapablePunctuation(unichar(scalar.value)) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result.append("\\")
                    result.unicodeScalars.append(scalar)
                }
                escaping = false
            } else if scalar == "\\" {
                escaping = true
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        if escaping { result.append("\\") }
        return result
    }
}
