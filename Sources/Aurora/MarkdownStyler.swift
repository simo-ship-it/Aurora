import AppKit

/// Applica lo stile visivo al testo. La sintassi Markdown resta nel documento
/// ma viene nascosta sulle righe che non contengono il cursore, come in Typora.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {

    private unowned let textView: MarkdownTextView
    private var theme: Theme { Theme.current }

    private var cachedLines: [LineInfo]?
    private var activeLines: Set<Int> = []
    private var lastEditedRange: NSRange?
    /// Stato "dentro un blocco di codice" della riga che seguiva la modifica, prima della modifica.
    private var fenceStateBeforeEdit: Bool?
    private var safetyRestyleWorkItem: DispatchWorkItem?

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init()
    }

    // MARK: - Struttura del documento

    private var storage: NSTextStorage? { textView.textStorage }

    var lines: [LineInfo] {
        if let cached = cachedLines { return cached }
        let parsed = MarkdownParser.parse((storage?.string ?? "") as NSString)
        cachedLines = parsed
        return parsed
    }

    func invalidateCache() { cachedLines = nil }

    // MARK: - Notifiche di modifica

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Prima di buttare la cache: com'era la riga che seguiva la modifica?
        // Se apre o chiude un blocco di codice, cambia lo stile di tutto ciò che segue.
        if let cached = cachedLines {
            let oldEnd = editedRange.location + editedRange.length - delta
            fenceStateBeforeEdit = lineIndex(containing: oldEnd, in: cached).map { cached[$0].isInsideFence }
        } else {
            fenceStateBeforeEdit = nil
        }
        invalidateCache()
        lastEditedRange = editedRange
    }

    /// Chiamato dopo ogni modifica del testo.
    func handleTextChange() {
        guard let storage, let edited = lastEditedRange else { restyleAll(); return }
        lastEditedRange = nil

        let ns = storage.string as NSString
        let clamped = NSRange(location: min(edited.location, ns.length),
                              length: min(edited.length, max(0, ns.length - min(edited.location, ns.length))))
        let all = lines
        guard let first = lineIndex(containing: clamped.location, in: all) else { restyleAll(); return }
        let last = lineIndex(containing: NSMaxRange(clamped), in: all) ?? first

        let structureChanged = fenceStateBeforeEdit != nil && fenceStateBeforeEdit != all[last].isInsideFence
        fenceStateBeforeEdit = nil

        let from = max(0, first - 2)
        // Se è cambiato l'inizio o la fine di un blocco di codice, tutto ciò che segue
        // cambia aspetto: si ristilizza fino alla fine di quanto è a schermo.
        let to = structureChanged ? max(last, visibleLineRange()?.upperBound ?? last) + 20
                                  : last + 2
        restyle(lineRange: from...min(all.count - 1, max(from, to)))
        // La riga appena creata eredita gli attributi del punto d'inserimento:
        // se fra questi c'è una decorazione di blocco, si estende dove non deve.
        sanitizeTypingAttributes()
        scheduleSafetyRestyle()
    }

    /// Rete di sicurezza: quando la digitazione si ferma, riallinea ciò che è visibile.
    private func scheduleSafetyRestyle() {
        safetyRestyleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.restyleVisible() }
        safetyRestyleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// Righe attualmente inquadrate dalla finestra.
    private func visibleLineRange() -> ClosedRange<Int>? {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        let origin = textView.textContainerOrigin
        var rect = textView.visibleRect
        rect.origin.x -= origin.x
        rect.origin.y -= origin.y
        guard rect.height > 0 else { return nil }
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let all = lines
        guard !all.isEmpty,
              let first = lineIndex(containing: characters.location, in: all),
              let last = lineIndex(containing: NSMaxRange(characters), in: all) else { return nil }
        return min(first, last)...max(first, last)
    }

    /// Ristilizza le righe a schermo (più un margine), usata durante lo scorrimento.
    func restyleVisible() {
        guard let visible = visibleLineRange() else { return }
        let all = lines
        // Un margine oltre il bordo dello schermo, così scorrendo di poco non
        // si trovano righe non ancora stilizzate.
        let margine = 20
        activeLines = computeActiveLines(all)
        restyle(lineRange: max(0, visible.lowerBound - margine)...min(all.count - 1, visible.upperBound + margine))
    }

    /// Chiamato quando il cursore si sposta: cambia l'insieme delle righe "in modifica".
    func selectionChanged() {
        let all = lines
        let updated = computeActiveLines(all)
        guard updated != activeLines else { return }
        let changed = updated.symmetricDifference(activeLines)
        activeLines = updated
        for index in changed.sorted() where index < all.count {
            restyle(lineRange: index...index)
        }
        sanitizeTypingAttributes()
    }

    /// Righe toccate dalla selezione: sono quelle su cui la sintassi resta visibile.
    private func computeActiveLines(_ all: [LineInfo]) -> Set<Int> {
        let selection = textView.selectedRange()
        guard !all.isEmpty,
              var first = lineIndex(containing: selection.location, in: all),
              var last = lineIndex(containing: NSMaxRange(selection), in: all) else { return [] }
        // Il cursore a inizio riga non "apre" la riga precedente.
        while first > 0, all[first].range.location > selection.location { first -= 1 }
        while first < last, selection.location > all[first].contentsEnd { first += 1 }
        while last > first, all[last].range.location >= NSMaxRange(selection) { last -= 1 }
        guard first <= last else { return [] }
        return Set(first...last)
    }

    private func lineIndex(containing location: Int, in all: [LineInfo]) -> Int? {
        var low = 0, high = all.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let line = all[mid]
            // `range` comprende il terminatore, quindi la sua fine coincide con
            // l'inizio della riga dopo: quella posizione appartiene alla riga
            // successiva, non a questa. Senza il confronto stretto, il cursore
            // appena andato a capo terrebbe "in modifica" la riga che ha lasciato.
            if location < line.range.location { high = mid - 1 }
            else if location >= NSMaxRange(line.range) { low = mid + 1 }
            else { return mid }
        }
        return all.isEmpty ? nil : min(max(0, low), all.count - 1)
    }

    // MARK: - Applicazione degli stili

    func restyleAll() {
        safetyRestyleWorkItem?.cancel()
        let all = lines
        guard !all.isEmpty else { return }
        activeLines = computeActiveLines(all)
        restyle(lineRange: 0...(all.count - 1))
        sanitizeTypingAttributes()
    }

    private func restyle(lineRange: ClosedRange<Int>) {
        guard let storage else { return }
        let all = lines
        guard !all.isEmpty else { return }
        let lower = max(0, lineRange.lowerBound)
        let upper = min(all.count - 1, lineRange.upperBound)
        guard lower <= upper else { return }

        let ns = storage.string as NSString
        storage.beginEditing()
        for index in lower...upper {
            apply(all[index], index: index, ns: ns, storage: storage)
        }
        storage.endEditing()

        let start = all[lower].range.location
        let end = min(ns.length, NSMaxRange(all[upper].range))
        let dirty = NSRange(location: start, length: max(0, end - start))
        if let layout = textView.layoutManager, dirty.length >= 0 {
            layout.invalidateGlyphs(forCharacterRange: dirty, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: dirty, actualCharacterRange: nil)
        }
        textView.needsDisplay = true
    }

    private func apply(_ line: LineInfo, index: Int, ns: NSString, storage: NSTextStorage) {
        guard line.range.length > 0 else { return }
        let active = activeLines.contains(index)
        let isCode = line.kind == .codeBody || line.kind == .fence

        // --- Font e paragrafo di base per la riga
        var baseFont = theme.body
        var baseColor = theme.text
        switch line.kind {
        case .heading(let level):
            baseFont = theme.heading(level)
            baseColor = theme.headingText
        case .codeBody, .fence:
            baseFont = theme.mono
            baseColor = theme.codeText
        case .tableHeader:
            baseFont = NSFont.monospacedSystemFont(ofSize: theme.monoSize, weight: .semibold)
        case .tableDelimiter, .tableRow:
            baseFont = theme.mono
        default:
            break
        }
        if line.quoteDepth > 0 && !isCode { baseColor = theme.quoteText }

        let (paragraph, baselineOffset) = paragraphStyle(for: line, font: baseFont)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraph
        ]
        if baselineOffset != 0 { attributes[.baselineOffset] = baselineOffset }
        if isCode { attributes[.auroraBlock] = "code" }
        // Il tratto si disegna solo quando i trattini sono nascosti: sulla riga
        // attiva si vede la sorgente, non la sorgente *e* la sua anteprima.
        // Stessa regola dei pallini di elenco e delle caselle di spunta.
        if line.kind == .horizontalRule, !active { attributes[.auroraBlock] = "hr" }
        if line.kind == .tableHeader || line.kind == .tableDelimiter || line.kind == .tableRow {
            attributes[.auroraBlock] = "table"
        }
        if case .heading(let level) = line.kind { attributes[.kern] = theme.headingTracking(level) }
        if line.quoteDepth > 0 { attributes[.auroraQuoteDepth] = line.quoteDepth }

        storage.setAttributes(attributes, range: line.range)

        // --- Contenuto inline
        if !isCode, line.contentRange.length > 0, line.kind != .horizontalRule {
            let inline = MarkdownParser.parseInline(ns, range: line.contentRange)
            for run in inline.runs {
                applyInline(run, baseFont: baseFont, baseColor: baseColor, storage: storage)
            }
            for marker in inline.markers {
                conceal(marker, active: active, storage: storage)
            }
        }

        // --- Riga ``` : nascosta quando non si sta modificando, fa da margine del riquadro
        if line.kind == .fence, !active, line.contentRange.length > 0 {
            storage.addAttribute(.auroraConceal, value: true, range: line.contentRange)
        }

        // --- Marcatori di blocco (#, >, ```, rientri)
        for marker in line.markers {
            conceal(marker, active: active, storage: storage)
        }

        // --- Elenchi puntati: pallino disegnato al posto del trattino
        if let bullet = line.bulletRange, bullet.length > 0 {
            if active {
                storage.addAttribute(.foregroundColor, value: theme.syntax, range: bullet)
            } else {
                storage.addAttributes([.foregroundColor: NSColor.clear,
                                       .auroraGlyph: bulletGlyph(for: line.listIndent)], range: bullet)
            }
        }
        if let ordered = line.orderedRange, ordered.length > 0 {
            storage.addAttributes([
                .foregroundColor: theme.quoteText,
                .font: NSFont.systemFont(ofSize: theme.bodySize, weight: .semibold)
            ], range: ordered)
        }

        // --- Task list: casella disegnata al posto di "[ ]"
        if let checkbox = line.checkboxRange {
            if active {
                storage.addAttribute(.foregroundColor, value: theme.syntax, range: checkbox)
            } else {
                storage.addAttributes([.foregroundColor: NSColor.clear,
                                       .auroraGlyph: line.checkboxChecked ? "☑" : "☐"], range: checkbox)
            }
            storage.addAttribute(.auroraCheckbox, value: line.checkboxChecked, range: checkbox)
            if line.checkboxChecked, line.contentRange.length > 0 {
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .foregroundColor: theme.quoteText], range: line.contentRange)
            }
        }

        // --- Linea orizzontale: caratteri nascosti, il tratto è disegnato dalla vista
        if line.kind == .horizontalRule, !active {
            let content = NSRange(location: line.range.location,
                                  length: max(0, line.contentsEnd - line.range.location))
            if content.length > 0 { storage.addAttribute(.auroraConceal, value: true, range: content) }
        }
    }

    private func bulletGlyph(for indent: Int) -> String {
        switch indent % 3 {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }

    private func conceal(_ range: NSRange, active: Bool, storage: NSTextStorage) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        if active {
            storage.addAttribute(.foregroundColor, value: theme.syntax, range: range)
        } else {
            storage.addAttribute(.auroraConceal, value: true, range: range)
        }
    }

    private func applyInline(_ run: InlineRun, baseFont: NSFont, baseColor: NSColor, storage: NSTextStorage) {
        guard run.range.length > 0, NSMaxRange(run.range) <= storage.length else { return }
        let style = run.style
        var attributes: [NSAttributedString.Key: Any] = [:]

        if style.contains(.code) {
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular)
            attributes[.foregroundColor] = theme.codeText
            attributes[.backgroundColor] = theme.inlineCodeBackground
        } else {
            attributes[.font] = Theme.apply(bold: style.contains(.bold),
                                            italic: style.contains(.italic),
                                            to: baseFont)
        }
        if style.contains(.strike) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.foregroundColor] = theme.quoteText
        }
        if style.contains(.highlight) {
            attributes[.backgroundColor] = theme.highlight
        }
        if style.contains(.link) || style.contains(.image) {
            attributes[.foregroundColor] = theme.accent
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = theme.accent.withAlphaComponent(0.35)
            if let url = run.url { attributes[.auroraLink] = url }
        }
        storage.addAttributes(attributes, range: run.range)
    }

    /// L'altezza di riga è fissata in punti anziché con `lineHeightMultiple`:
    /// così gli sfondi (codice inline, evidenziato) restano allineati al testo.
    /// Restituisce anche lo scostamento di base con cui centrare il testo
    /// nella riga: senza, con interlinee ampie gli sfondi galleggiano più in alto.
    /// Invariante: la geometria di una riga non dipende da dove sta il cursore,
    /// e nessun tipo di riga aggiunge spazio *sopra* di sé. Sono le due cose che
    /// farebbero muovere il testo sotto le dita mentre lo si scrive: lo spazio
    /// sopra nasce nell'istante in cui la riga cambia natura, e una geometria
    /// legata al cursore salta ogni volta che ci entri o ne esci. Lo stacco
    /// verticale lo danno le righe vuote, che esistono già prima.
    ///
    /// Per questo la funzione non riceve `active`: così il vincolo lo fa
    /// rispettare il compilatore, non la memoria di chi tocca il file.
    private func paragraphStyle(for line: LineInfo, font: NSFont) -> (NSParagraphStyle, CGFloat) {
        let style = NSMutableParagraphStyle()
        // Nessun tipo di riga aggiunge spazio di coda. La separazione verticale la
        // danno le righe vuote — che in Markdown sono anche il modo in cui la
        // separazione è scritta nel file. Così cambiare mestiere a una riga non
        // cambia lo spazio che occupa, e due righe consecutive senza riga vuota in
        // mezzo restano un solo paragrafo, come vuole il Markdown.
        style.paragraphSpacing = 0
        let quoteIndent = CGFloat(line.quoteDepth) * theme.quoteIndent
        var multiple = theme.lineHeightMultiple

        switch line.kind {
        case .heading:
            multiple = 1.25
            style.firstLineHeadIndent = quoteIndent
            style.headIndent = quoteIndent
        case .codeBody, .fence:
            multiple = 1.35
            style.firstLineHeadIndent = theme.surfacePadding + quoteIndent
            style.headIndent = theme.surfacePadding + quoteIndent
        case .bulletItem, .orderedItem:
            let indent = CGFloat(line.listIndent) * theme.listIndent + quoteIndent
            style.firstLineHeadIndent = indent
            style.headIndent = indent + theme.listIndent
        case .tableHeader, .tableDelimiter, .tableRow:
            multiple = 1.35
            style.firstLineHeadIndent = theme.surfacePadding + quoteIndent
            style.headIndent = theme.surfacePadding + quoteIndent
        case .horizontalRule, .blank:
            // Entrambe hanno corpo e altezza del testo normale: diventare linea
            // orizzontale, o scrivere un carattere su una riga vuota, non cambia
            // nulla dell'ingombro.
            style.firstLineHeadIndent = quoteIndent
            style.headIndent = quoteIndent
        default:
            style.firstLineHeadIndent = quoteIndent
            style.headIndent = quoteIndent
        }

        let natural = ceil(font.ascender - font.descender + font.leading)
        let height = max((font.pointSize * multiple).rounded(), natural)
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return (style, ((height - natural) / 2).rounded())
    }

    /// Impedisce che gli attributi interni (sintassi nascosta) vengano ereditati da ciò che si digita.
    private func sanitizeTypingAttributes() {
        var attributes = textView.typingAttributes
        for key: NSAttributedString.Key in [.auroraConceal, .auroraGlyph, .auroraBlock,
                                            .auroraCheckbox, .auroraLink, .auroraQuoteDepth] {
            attributes.removeValue(forKey: key)
        }
        textView.typingAttributes = attributes
    }
}
