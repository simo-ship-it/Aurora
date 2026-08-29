import Foundation

// MARK: - Modello

enum LineKind: Equatable {
    case blank
    case paragraph
    case heading(level: Int)
    case bulletItem
    case orderedItem
    case fence           // la riga ``` di apertura o chiusura
    case codeBody
    case horizontalRule
    case tableHeader
    case tableDelimiter
    case tableRow
}

struct LineInfo {
    var range: NSRange          // riga completa, terminatore incluso
    var contentsEnd: Int        // fine del testo, terminatore escluso
    var contentRange: NSRange   // testo dopo i prefissi di blocco (per il parsing inline)
    var kind: LineKind = .paragraph
    var quoteDepth: Int = 0
    var listIndent: Int = 0     // livello di rientro dell'elenco (0, 1, 2, …)
    var markers: [NSRange] = [] // sintassi di blocco da nascondere/attenuare
    var bulletRange: NSRange?   // il carattere -, * o +
    var orderedRange: NSRange?  // "1." di un elenco numerato
    var listMarkerText = ""     // "-" oppure "1." — serve a continuare l'elenco con Invio
    var checkboxRange: NSRange? // "[ ]" oppure "[x]"
    var checkboxChecked = false
    var isInsideFence = false
}

struct InlineStyle: OptionSet {
    let rawValue: Int
    static let bold      = InlineStyle(rawValue: 1 << 0)
    static let italic    = InlineStyle(rawValue: 1 << 1)
    static let strike    = InlineStyle(rawValue: 1 << 2)
    static let code      = InlineStyle(rawValue: 1 << 3)
    static let link      = InlineStyle(rawValue: 1 << 4)
    static let image     = InlineStyle(rawValue: 1 << 5)
    static let highlight = InlineStyle(rawValue: 1 << 6)
}

struct InlineRun {
    var range: NSRange
    var style: InlineStyle
    var url: String?
}

struct InlineResult {
    var runs: [InlineRun] = []
    var markers: [NSRange] = []
}

// MARK: - Parser

enum MarkdownParser {

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

    /// Analizza l'intero documento riga per riga. È una singola passata lineare.
    static func parse(_ ns: NSString) -> [LineInfo] {
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

        detectTables(ns, &lines)
        return lines
    }

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
                        if c == fenceChar && run >= fenceLength {
                            inFence = false
                            line.kind = .fence
                            line.isInsideFence = true
                            line.contentRange = NSRange(location: contentsEnd, length: 0)
                            line.markers.append(NSRange(location: start, length: contentsEnd - start))
                            return line
                        }
                    } else {
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
                    if mark == space || isChecked {
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

    /// Seconda passata: una riga di intestazione seguita da "| --- | --- |" apre una tabella.
    private static func detectTables(_ ns: NSString, _ lines: inout [LineInfo]) {
        var i = 0
        while i < lines.count {
            guard !lines[i].isInsideFence, isDelimiterRow(ns, lines[i]), i > 0,
                  containsPipe(ns, lines[i - 1]), lines[i - 1].kind == .paragraph else { i += 1; continue }
            lines[i - 1].kind = .tableHeader
            lines[i].kind = .tableDelimiter
            var j = i + 1
            while j < lines.count, lines[j].kind == .paragraph, containsPipe(ns, lines[j]) {
                lines[j].kind = .tableRow
                j += 1
            }
            i = j
        }
    }

    private static func containsPipe(_ ns: NSString, _ line: LineInfo) -> Bool {
        var i = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        while i < end {
            if ns.character(at: i) == pipe { return true }
            i += 1
        }
        return false
    }

    private static func isDelimiterRow(_ ns: NSString, _ line: LineInfo) -> Bool {
        var i = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        guard end > i else { return false }
        var dashes = 0, pipes = 0
        while i < end {
            let c = ns.character(at: i)
            if c == dash { dashes += 1 }
            else if c == pipe { pipes += 1 }
            else if c != colon && !isBlank(c) { return false }
            i += 1
        }
        return dashes >= 3 && pipes >= 1
    }

    // MARK: Inline

    static func parseInline(_ ns: NSString, range: NSRange) -> InlineResult {
        var out = InlineResult()
        guard range.length > 0 else { return out }
        parseInline(ns, range: range, style: [], url: nil, into: &out)
        return out
    }

    private static func parseInline(_ ns: NSString, range: NSRange, style: InlineStyle,
                                    url: String?, into out: inout InlineResult) {
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
            if c == backslash, i + 1 < end {
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
                    out.markers.append(NSRange(location: i, length: run))
                    let content = NSRange(location: i + run, length: close - i - run)
                    if content.length > 0 {
                        out.runs.append(InlineRun(range: content, style: style.union(.code), url: url))
                    }
                    out.markers.append(NSRange(location: close, length: run))
                    i = close + run
                    plainStart = i
                    continue
                }
            }

            // Immagini: ![alt](url)
            if c == bang, i + 1 < end, ns.character(at: i + 1) == openBracket,
               let link = matchLink(ns, from: i + 1, end: end) {
                emit(upTo: i)
                out.markers.append(NSRange(location: i, length: 2))                 // "!["
                parseInline(ns, range: link.text, style: style.union(.image), url: link.url, into: &out)
                out.markers.append(NSRange(location: NSMaxRange(link.text),
                                           length: link.end - NSMaxRange(link.text)))
                i = link.end
                plainStart = i
                continue
            }

            // Collegamenti: [testo](url)
            if c == openBracket, let link = matchLink(ns, from: i, end: end) {
                emit(upTo: i)
                out.markers.append(NSRange(location: i, length: 1))                 // "["
                parseInline(ns, range: link.text, style: style.union(.link), url: link.url, into: &out)
                out.markers.append(NSRange(location: NSMaxRange(link.text),
                                           length: link.end - NSMaxRange(link.text)))
                i = link.end
                plainStart = i
                continue
            }

            // Autolink: <https://…>
            if c == lt, let close = findAutolinkEnd(ns, from: i, end: end) {
                emit(upTo: i)
                let content = NSRange(location: i + 1, length: close - i - 1)
                out.markers.append(NSRange(location: i, length: 1))
                out.runs.append(InlineRun(range: content, style: style.union(.link),
                                          url: ns.substring(with: content)))
                out.markers.append(NSRange(location: close, length: 1))
                i = close + 1
                plainStart = i
                continue
            }

            // Barrato ~~x~~ ed evidenziato ==x==
            if c == tilde || c == equals {
                let added: InlineStyle = (c == tilde) ? .strike : .highlight
                if i + 1 < end, ns.character(at: i + 1) == c,
                   let close = findDelimiter(ns, char: c, count: 2, from: i + 2, end: end) {
                    emit(upTo: i)
                    out.markers.append(NSRange(location: i, length: 2))
                    parseInline(ns, range: NSRange(location: i + 2, length: close - i - 2),
                                style: style.union(added), url: url, into: &out)
                    out.markers.append(NSRange(location: close, length: 2))
                    i = close + 2
                    plainStart = i
                    continue
                }
            }

            // Enfasi: *x*, **x**, ***x***, _x_, __x__
            if c == star || c == underscore {
                var run = 0
                while i + run < end, ns.character(at: i + run) == c, run < 3 { run += 1 }
                let opensWell = i + run < end && !isBlank(ns.character(at: i + run))
                // Gli underscore non spezzano snake_case.
                let intraword = (c == underscore) && i > 0 && isWordChar(ns.character(at: i - 1))
                if opensWell, !intraword,
                   let close = findDelimiter(ns, char: c, count: run, from: i + run, end: end) {
                    var added: InlineStyle = []
                    if run == 1 { added = .italic }
                    else if run == 2 { added = .bold }
                    else { added = [.bold, .italic] }
                    emit(upTo: i)
                    out.markers.append(NSRange(location: i, length: run))
                    parseInline(ns, range: NSRange(location: i + run, length: close - i - run),
                                style: style.union(added), url: url, into: &out)
                    out.markers.append(NSRange(location: close, length: run))
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
                if run >= count, i > from, !isBlank(ns.character(at: i - 1)) {
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

    private static func matchLink(_ ns: NSString, from: Int, end: Int) -> LinkMatch? {
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
        guard i < end, depth == 0 else { return nil }
        let textRange = NSRange(location: from + 1, length: i - from - 1)
        var j = i + 1
        guard j < end, ns.character(at: j) == openParen else { return nil }
        j += 1
        let urlStart = j
        var parens = 1
        while j < end {
            let c = ns.character(at: j)
            if c == backslash { j += 2; continue }
            if c == openParen { parens += 1 }
            else if c == closeParen {
                parens -= 1
                if parens == 0 { break }
            }
            j += 1
        }
        guard j < end, parens == 0 else { return nil }
        var destination = ns.substring(with: NSRange(location: urlStart, length: j - urlStart))
        // Rimuove un eventuale titolo: (url "titolo")
        if let spaceIdx = destination.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            destination = String(destination[destination.startIndex..<spaceIdx])
        }
        return LinkMatch(text: textRange, url: destination, end: j + 1)
    }

    private static func findAutolinkEnd(_ ns: NSString, from: Int, end: Int) -> Int? {
        var i = from + 1
        var sawScheme = false
        while i < end {
            let c = ns.character(at: i)
            if isBlank(c) || c == lt { return nil }
            if c == colon { sawScheme = true }
            if c == 0x3E { return sawScheme && i > from + 1 ? i : nil }
            i += 1
        }
        return nil
    }
}
