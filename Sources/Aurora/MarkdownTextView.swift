import AppKit
import AuroraCore

final class MarkdownTextView: NSTextView, NSLayoutManagerDelegate {

    var styler: MarkdownStyler!
    private var theme: Theme { Theme.current }

    private let slashMenu = SlashMenuController()
    private var tableEditor: TableEditorWindowController?
    private var inlineTables: [InlineTableView] = []
    private var inlineTableRefreshScheduled = false
    private var activeInlineTableRange: NSRange?
    private var lastAllowedTextSelection = NSRange(location: 0, length: 0)
    private var normalizingTableSelection = false
    /// `true` per ↑, `false` per ↓; serve a scegliere il lato corretto del blocco.
    private var pendingVerticalNavigation: Bool?
    /// Posizione della "/" che ha aperto il menu, o `NSNotFound`.
    private var slashOrigin = NSNotFound

    // MARK: - Configurazione

    func configure() {
        styler = MarkdownStyler(textView: self)
        slashMenu.onPick = { [weak self] command in self?.applySlash(command) }
        textStorage?.delegate = styler
        layoutManager?.delegate = self

        isRichText = true
        isEditable = true
        isSelectable = true
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        drawsBackground = true
        textContainerInset = NSSize(width: 0, height: theme.topInset)
        defaultParagraphStyle = nil
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        applyTheme()
    }

    /// Le sole proprietà che dipendono dal tema, riunite perché un cambio nelle
    /// impostazioni possa riapplicarle senza ricostruire la vista.
    func applyTheme() {
        backgroundColor = theme.background
        insertionPointColor = theme.insertionPoint
        typingAttributes = [.font: theme.body, .foregroundColor: theme.text]
        inlineTables.forEach { $0.applyTheme() }
        scheduleInlineTableRefresh()
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Menu dei comandi ("/")

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard (string as? String) == "/" || (string as? NSAttributedString)?.string == "/" else { return }

        let slash = selectedRange().location - 1
        guard slash >= 0, slashAllowed(at: slash) else { return }
        slashOrigin = slash
        if !slashMenu.present(query: "", below: caretRect(at: slash), in: window) {
            dismissSlashMenu()
        }
    }

    /// Il menu si apre solo a inizio riga o dopo uno spazio, e mai dentro un
    /// blocco di codice: così una barra dentro `http://` o in `e/o` resta una barra.
    private func slashAllowed(at location: Int) -> Bool {
        if let line = currentLine(at: location), line.kind == .codeBody || line.kind == .fence {
            return false
        }
        guard location > 0 else { return true }
        let character = (self.string as NSString).character(at: location - 1)
        return character == 32 || character == 9 || character == 10 || character == 13
    }

    private func caretRect(at location: Int) -> NSRect {
        let length = (self.string as NSString).length
        return firstRect(forCharacterRange: NSRange(location: min(location, length), length: 0),
                         actualRange: nil)
    }

    private func dismissSlashMenu() {
        slashOrigin = NSNotFound
        slashMenu.dismiss()
    }

    /// Riallinea il menu a ciò che è stato scritto dopo la "/".
    private func refreshSlashMenu() {
        guard slashOrigin != NSNotFound else { return }
        let ns = self.string as NSString
        let caret = selectedRange().location
        guard slashOrigin < ns.length, ns.character(at: slashOrigin) == 47,
              caret > slashOrigin, caret <= ns.length else {
            dismissSlashMenu()
            return
        }
        let query = ns.substring(with: NSRange(location: slashOrigin + 1, length: caret - slashOrigin - 1))
        // Uno spazio chiude il menu: vuol dire che stavi scrivendo, non cercando.
        guard !query.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else {
            dismissSlashMenu()
            return
        }
        if !slashMenu.present(query: query, below: caretRect(at: slashOrigin), in: window) {
            dismissSlashMenu()
        }
    }

    override func keyDown(with event: NSEvent) {
        if slashMenu.isVisible {
            switch event.keyCode {
            case 125: slashMenu.moveSelection(by: 1); return
            case 126: slashMenu.moveSelection(by: -1); return
            case 36, 76: slashMenu.confirmSelection(); return
            case 53: dismissSlashMenu(); return
            default: break
            }
        }

        switch event.keyCode {
        case 126: pendingVerticalNavigation = true
        case 125: pendingVerticalNavigation = false
        default: pendingVerticalNavigation = nil
        }
        super.keyDown(with: event)
        pendingVerticalNavigation = nil
    }

    override func resignFirstResponder() -> Bool {
        dismissSlashMenu()
        return super.resignFirstResponder()
    }

    /// Toglie "/comando" dal testo e lancia il comando vero.
    private func applySlash(_ command: SlashCommand) {
        let caret = selectedRange().location
        let start = slashOrigin
        dismissSlashMenu()
        guard start != NSNotFound, caret >= start, caret <= (self.string as NSString).length else { return }

        let typed = NSRange(location: start, length: caret - start)
        if typed.length > 0, shouldChangeText(in: typed, replacementString: "") {
            textStorage?.replaceCharacters(in: typed, with: "")
            didChangeText()
        }
        setSelectedRange(NSRange(location: start, length: 0))

        // I comandi leggono il livello dal tag del mittente, come dal menu Formato.
        let sender = NSMenuItem()
        sender.tag = command.tag
        NSApp.sendAction(command.action, to: self, from: sender)
    }

    // MARK: - Occultamento della sintassi

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var modified = [NSLayoutManager.GlyphProperty](repeating: [], count: count)
        var changed = false
        let length = storage.length

        for i in 0..<count {
            var property = props[i]
            let charIndex = charIndexes[i]
            if charIndex < length,
               storage.attribute(.auroraConceal, at: charIndex, effectiveRange: nil) != nil {
                // Un glifo `.null` perde l'appartenenza alla propria riga agli
                // occhi di TextKit: davanti a elementi consecutivi può far
                // applicare `headIndent` invece di `firstLineHeadIndent`, per cui
                // una lista senza Tab sembra rientrata. Un carattere di controllo
                // a larghezza zero resta invece nella riga e non occupa spazio.
                property.insert(.controlCharacter)
                changed = true
            }
            modified[i] = property
        }
        guard changed else { return 0 }

        modified.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!,
                                    characterIndexes: charIndexes, font: aFont,
                                    forGlyphRange: glyphRange)
        }
        return count
    }

    /// I caratteri marcati come sintassi nascosta partecipano ancora al layout
    /// della propria riga, ma non avanzano orizzontalmente e non vengono disegnati.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, charIndex < storage.length,
              storage.attribute(.auroraConceal, at: charIndex, effectiveRange: nil) != nil else {
            return action
        }
        return .zeroAdvancement
    }

    // MARK: - Decorazioni (blocchi di codice, citazioni, linee, elenchi)

    /// Un frammento di riga con l'intervallo di caratteri che copre, già nelle
    /// coordinate della vista.
    private struct LineBox {
        let characters: NSRange
        let rect: NSRect
    }

    /// Le righe inquadrate, con i caratteri di ciascuna.
    ///
    /// È il perno di tutto il disegno delle decorazioni. I caratteri di sintassi
    /// nascosti hanno avanzamento zero, quindi il loro rettangolo non è un'ancora
    /// geometrica utile; il frammento della riga conserva invece sia la geometria
    /// sia l'intervallo di caratteri a cui appartiene.
    private func lineBoxes(_ layout: NSLayoutManager, glyphs: NSRange, origin: NSPoint) -> [LineBox] {
        var boxes: [LineBox] = []
        layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
            var box = rect
            box.origin.x += origin.x
            box.origin.y += origin.y
            boxes.append(LineBox(characters: layout.characterRange(forGlyphRange: glyphRange,
                                                                   actualGlyphRange: nil),
                                 rect: box))
        }
        return boxes
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0 else { return }

        // Il layout va garantito PRIMA di chiedere quali glifi cadono nel rettangolo:
        // altrimenti la domanda stessa parte da una geometria non aggiornata e le
        // decorazioni finiscono su coordinate vecchie.
        layout.ensureLayout(forBoundingRect: rect, in: container)

        let visibleGlyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        let visible = layout.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        guard visible.length > 0 else { return }

        let origin = textContainerOrigin
        let contentWidth = container.size.width
        let boxes = lineBoxes(layout, glyphs: visibleGlyphs, origin: origin)

        /// Le righe di una decorazione: quelle che *cominciano* dentro il suo
        /// intervallo di caratteri.
        ///
        /// Si usa la copertura in caratteri anziché il rettangolo della sintassi:
        /// quest'ultimo può avere larghezza zero. Il frammento conserva invece la
        /// riga corretta anche quando il suo prefisso non occupa spazio.
        func rows(in range: NSRange) -> [NSRect] {
            boxes.filter { NSLocationInRange($0.characters.location, range) }.map(\.rect)
        }

        /// L'area coperta da una decorazione, o `nil` se non è inquadrata.
        func box(for range: NSRange) -> NSRect? {
            rows(in: range).reduce(nil) { (union: NSRect?, row) in union.map { $0.union(row) } ?? row }
        }

        // Superfici dei blocchi di codice.
        storage.enumerateAttribute(.auroraBlock, in: visible) { value, range, _ in
            guard let kind = value as? String else { return }
            switch kind {
            case "code":
                guard var surface = box(for: range) else { return }
                surface.origin.x = origin.x
                surface.size.width = contentWidth
                surface = surface.insetBy(dx: 0, dy: -2)
                theme.codeBackground.setFill()
                NSBezierPath(roundedRect: surface,
                             xRadius: theme.surfaceRadius,
                             yRadius: theme.surfaceRadius).fill()
            case "hr":
                // Il tratto appartiene a una riga sola: la prima dell'intervallo.
                guard let row = rows(in: range).first else { return }
                theme.rule.setFill()
                NSRect(x: origin.x + 2, y: (row.midY - 0.5).rounded(),
                       width: contentWidth - 4, height: 1).fill()
            default:
                break
            }
        }

        // Barre laterali delle citazioni, a pillola.
        storage.enumerateAttribute(.auroraQuoteDepth, in: visible) { value, range, _ in
            guard let depth = value as? Int, depth > 0, let area = box(for: range) else { return }
            theme.quoteBar.setFill()
            for level in 0..<depth {
                let bar = NSRect(x: origin.x + CGFloat(level) * theme.quoteIndent + 1,
                                 y: area.minY + 1, width: 3, height: max(0, area.height - 2))
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        // Segni di elenco e caselle: forme disegnate, non glifi di testo.
        storage.enumerateAttribute(.auroraGlyph, in: visible) { value, range, _ in
            guard let glyph = value as? String, let row = rows(in: range).first
                    ?? boxes.first(where: { NSLocationInRange(range.location, $0.characters) })?.rect
            else { return }
            let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? theme.body

            // Il testo è centrato nella riga dall'altezza fissa: il centro ottico
            // della x minuscola si ricava dal frammento e dal font, senza passare
            // dai glifi. È lì che l'occhio cerca il segno.
            let textTop = row.midY - (font.ascender - font.descender) / 2
            let middle = textTop + font.ascender - font.xHeight / 2
            // Il marcatore non è nascosto — è solo trasparente — quindi la sua
            // posizione orizzontale si può chiedere ai glifi senza rischi.
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let left = layout.boundingRect(forGlyphRange: glyphs, in: container).minX + origin.x

            switch glyph {
            case "☐", "☑":
                self.drawCheckbox(at: NSPoint(x: left + 7, y: middle), checked: glyph == "☑")
            default:
                self.drawBullet(at: NSPoint(x: left + 3, y: middle), glyph: glyph)
            }
        }
    }

    /// Livello 0 pieno, livello 1 vuoto, livello 2 quadrato: la forma dice la profondità.
    private func drawBullet(at center: NSPoint, glyph: String) {
        theme.quoteText.setFill()
        theme.quoteText.setStroke()
        switch glyph {
        case "◦":
            let radius: CGFloat = 3
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
            ring.lineWidth = 1.2
            ring.stroke()
        case "▪":
            let side: CGFloat = 5
            NSBezierPath(roundedRect: NSRect(x: center.x - side / 2, y: center.y - side / 2,
                                             width: side, height: side),
                         xRadius: 1.2, yRadius: 1.2).fill()
        default:
            let radius: CGFloat = 2.75
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)).fill()
        }
    }

    private func drawCheckbox(at center: NSPoint, checked: Bool) {
        let side: CGFloat = 14
        let box = NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        let shape = NSBezierPath(roundedRect: box, xRadius: 4.5, yRadius: 4.5)

        guard checked else {
            theme.controlBorder.setStroke()
            shape.lineWidth = 1.2
            shape.stroke()
            return
        }

        theme.accent.setFill()
        shape.fill()

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: center.x - 3.1, y: center.y - 0.1))
        mark.line(to: NSPoint(x: center.x - 0.9, y: center.y + 2.4))
        mark.line(to: NSPoint(x: center.x + 3.3, y: center.y - 2.6))
        mark.lineWidth = 1.7
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        NSColor.white.setStroke()
        mark.stroke()
    }

    // MARK: - A capo intelligente negli elenchi

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0, let line = currentLine(at: selection.location) else {
            super.insertNewline(sender)
            return
        }

        let prefixLength = max(0, line.contentRange.location - line.range.location)
        let isListLike = line.kind == .bulletItem || line.kind == .orderedItem || line.quoteDepth > 0
        guard isListLike, prefixLength > 0 else {
            super.insertNewline(sender)
            return
        }

        // Elemento vuoto: uscire dall'elenco invece di crearne un altro.
        if line.contentRange.length == 0 {
            let prefixRange = NSRange(location: line.range.location, length: prefixLength)
            insertText("", replacementRange: prefixRange)
            return
        }

        var prefix = String(repeating: "> ", count: line.quoteDepth)
        prefix += String(repeating: " ", count: line.listIndent * 2)
        switch line.kind {
        case .bulletItem:
            prefix += line.listMarkerText + " "
        case .orderedItem:
            let token = line.listMarkerText
            let separator = String(token.suffix(1))
            let number = Int(token.dropLast()) ?? 1
            prefix += "\(number + 1)\(separator) "
        default:
            break
        }
        if line.checkboxRange != nil { prefix += "[ ] " }
        insertText("\n" + prefix, replacementRange: selection)
    }

    // MARK: - Rientri

    override func insertTab(_ sender: Any?) {
        if moveTableSelection(forward: true) { return }
        let selection = selectedRange()
        if selection.length > 0 || currentLine(at: selection.location)?.kind == .bulletItem
            || currentLine(at: selection.location)?.kind == .orderedItem {
            shiftIndent(by: 2)
        } else {
            insertText("    ", replacementRange: selection)
        }
    }

    /// ⇧Tab torna alla cella precedente quando il cursore è in una tabella;
    /// altrove conserva il rientro previsto per l'editor.
    override func insertBacktab(_ sender: Any?) {
        if moveTableSelection(forward: false) { return }
        insertTab(sender)
    }

    private func shiftIndent(by amount: Int) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: selection)
        var result = ""
        var removedBeforeCaret = 0
        var addedBeforeCaret = 0
        var offset = lineRange.location

        ns.enumerateSubstrings(in: lineRange, options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            let text = ns.substring(with: enclosing)
            if amount > 0 {
                result += String(repeating: " ", count: amount) + text
                if enclosing.location <= selection.location { addedBeforeCaret += amount }
            } else {
                var stripped = text
                var removed = 0
                while removed < -amount, stripped.hasPrefix(" ") {
                    stripped.removeFirst()
                    removed += 1
                }
                result += stripped
                if enclosing.location <= selection.location { removedBeforeCaret += removed }
            }
            offset = NSMaxRange(enclosing)
        }
        guard offset > lineRange.location, !result.isEmpty else { return }

        let target = NSRange(location: lineRange.location, length: offset - lineRange.location)
        guard shouldChangeText(in: target, replacementString: result) else { return }
        textStorage?.replaceCharacters(in: target, with: result)
        didChangeText()
        let delta = addedBeforeCaret - removedBeforeCaret
        let newLocation = max(lineRange.location, selection.location + delta)
        setSelectedRange(NSRange(location: min(newLocation, string.utf16.count), length: 0))
    }

    // MARK: - Comandi di formattazione

    @objc func toggleBold(_ sender: Any?) { wrapSelection(with: "**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection(with: "*") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrapSelection(with: "~~") }
    @objc func toggleInlineCode(_ sender: Any?) { wrapSelection(with: "`") }
    @objc func toggleHighlight(_ sender: Any?) { wrapSelection(with: "==") }

    private func wrapSelection(with marker: String) {
        let ns = string as NSString
        // Lo spazio e gli a capo ai bordi della selezione restano fuori: dentro
        // i marcatori impedirebbero all'emfasi di chiudersi.
        let selection = MarkdownEditing.emphasisRange(in: ns, selection: selectedRange())
        let markerLength = marker.utf16.count

        // Se la selezione è già racchiusa dal marcatore, lo rimuove.
        let outer = NSRange(location: selection.location - markerLength,
                            length: selection.length + markerLength * 2)
        if outer.location >= 0, NSMaxRange(outer) <= ns.length,
           ns.substring(with: NSRange(location: outer.location, length: markerLength)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(selection), length: markerLength)) == marker {
            let inner = ns.substring(with: selection)
            insertText(inner, replacementRange: outer)
            setSelectedRange(NSRange(location: outer.location, length: selection.length))
            return
        }

        let selected = selection.length > 0 ? ns.substring(with: selection) : ""
        insertText(marker + selected + marker, replacementRange: selection)
        if selection.length == 0 {
            setSelectedRange(NSRange(location: selection.location + markerLength, length: 0))
        } else {
            setSelectedRange(NSRange(location: selection.location + markerLength, length: selection.length))
        }
    }

    /// Livello 0 = paragrafo normale.
    @objc func setHeadingLevel(_ sender: Any?) {
        let level = (sender as? NSMenuItem)?.tag ?? 0
        transformLines { line, text in
            var body = text
            while body.hasPrefix("#") { body.removeFirst() }
            if body.hasPrefix(" ") { body.removeFirst() }
            _ = line
            return level == 0 ? body : String(repeating: "#", count: level) + " " + body
        }
    }

    @objc func promoteHeading(_ sender: Any?) {
        guard activeInlineTableRange == nil else { return }
        transformLines { _, text in MarkdownEditing.promoteHeading(text) }
    }

    @objc func demoteHeading(_ sender: Any?) {
        guard activeInlineTableRange == nil else { return }
        transformLines { _, text in MarkdownEditing.demoteHeading(text) }
    }

    @objc func toggleBlockquote(_ sender: Any?) {
        let allQuoted = selectedLineTexts().allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(">")
        }
        transformLines { _, text in
            if allQuoted {
                var body = text
                if let range = body.range(of: "> ") ?? body.range(of: ">") {
                    body.removeSubrange(range)
                }
                return body
            }
            return "> " + text
        }
    }

    @objc func toggleBulletList(_ sender: Any?) {
        let allBulleted = selectedLineTexts().allSatisfy {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
        }
        transformLines { _, text in
            if allBulleted {
                var body = text
                while body.hasPrefix(" ") { body.removeFirst() }
                body.removeFirst(min(2, body.count))
                return body
            }
            return "- " + text
        }
    }

    @objc func toggleTaskList(_ sender: Any?) {
        transformLines { _, text in
            var body = text
            while body.hasPrefix(" ") { body.removeFirst() }
            if body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") {
                body.removeFirst(6)
                return body
            }
            if body.hasPrefix("- ") { body.removeFirst(2) }
            return "- [ ] " + body
        }
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: selection)
        let atLineStart = selection.location == lineRange.location
        insertText((atLineStart ? "" : "\n") + "---\n", replacementRange: selection)
    }

    @objc func insertLink(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let text = selection.length > 0 ? ns.substring(with: selection) : localized("text")
        insertText("[\(text)](https://)", replacementRange: selection)
        let caret = selection.location + text.utf16.count + 3
        setSelectedRange(NSRange(location: caret, length: 8))
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        let selection = selectedRange()
        let ns = string as NSString
        let body = selection.length > 0 ? ns.substring(with: selection) : ""
        insertText("```\n" + body + "\n```\n", replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + 4, length: 0))
    }

    @objc func insertTable(_ sender: Any?) {
        presentTableEditor(TableEditorWindowController.newTable()) { [weak self] table in
            self?.insert(table: table)
        }
    }

    @objc func editTable(_ sender: Any?) {
        let existing: (table: MarkdownTable, range: NSRange)?
        if let active = activeInlineTableRange,
           let view = inlineTables.first(where: { NSEqualRanges($0.sourceRange, active) }) {
            existing = (view.editedTable, active)
        } else {
            existing = markdownTable(at: selectedRange().location)
        }
        guard let existing else { return }
        presentTableEditor(existing.table) { [weak self] table in
            self?.replace(table: table, in: existing.range)
        }
    }

    private func insert(table: MarkdownTable) {
        let ns = string as NSString
        let selection = selectedRange()
        // Una tabella è un blocco: se è l'unico contenuto servono comunque due
        // righe reali, prima e dopo, sulle quali il cursore possa posizionarsi.
        let before = selection.location == 0 ? "\n"
            : (ns.character(at: selection.location - 1) != 10 ? "\n" : "")
        let afterLocation = NSMaxRange(selection)
        let after = afterLocation == ns.length ? "\n"
            : (ns.character(at: afterLocation) != 10 ? "\n" : "")
        let markdown = before + table.markdown + after
        guard shouldChangeText(in: selection, replacementString: markdown) else { return }
        textStorage?.replaceCharacters(in: selection, with: markdown)
        didChangeText()
        let tableEnd = selection.location + before.utf16.count + table.markdown.utf16.count
        setSelectedRange(NSRange(location: tableEnd + after.utf16.count, length: 0))
    }

    private func replace(table: MarkdownTable, in range: NSRange) {
        guard shouldChangeText(in: range, replacementString: table.markdown) else { return }
        textStorage?.replaceCharacters(in: range, with: table.markdown)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + 2, length: 0))
    }

    private func presentTableEditor(_ table: MarkdownTable,
                                    onApply: @escaping (MarkdownTable) -> Void) {
        guard let window else { return }
        let controller = TableEditorWindowController(table: table, onApply: onApply)
        tableEditor = controller
        controller.beginSheet(for: window) { [weak self, weak controller] in
            guard let self, let controller, self.tableEditor === controller else { return }
            self.tableEditor = nil
        }
    }

    private func markdownTable(at location: Int) -> (table: MarkdownTable, range: NSRange)? {
        let all = styler.lines
        guard let current = all.firstIndex(where: { location >= $0.range.location && location < NSMaxRange($0.range) }),
              isTableLine(all[current].kind) else { return nil }

        var first = current
        while first > 0, isTableLine(all[first - 1].kind) { first -= 1 }
        var last = current
        while last < all.count - 1, isTableLine(all[last + 1].kind) { last += 1 }

        let ns = string as NSString
        guard let header = all[first...last].first(where: { $0.kind == .tableHeader }) else { return nil }
        let headers = TableLayout.cells(of: header, in: ns).map(\.text)
        guard !headers.isEmpty else { return nil }
        let delimiter = all[first...last].first(where: { $0.kind == .tableDelimiter })
            .map { TableLayout.cells(of: $0, in: ns).map(\.text) } ?? []
        let rows = all[first...last]
            .filter { $0.kind == .tableRow }
            .map { TableLayout.cells(of: $0, in: ns).map(\.text) }
        let range = NSRange(location: all[first].range.location,
                            length: all[last].contentsEnd - all[first].range.location)
        return (MarkdownTable(headers: headers, delimiter: delimiter, rows: rows), range)
    }

    private func isTableLine(_ kind: LineKind) -> Bool {
        kind == .tableHeader || kind == .tableDelimiter || kind == .tableRow
    }

    private struct InlineTablePresentation {
        let range: NSRange
        let table: MarkdownTable
        let frame: NSRect
    }

    private func scheduleInlineTableRefresh() {
        guard !inlineTableRefreshScheduled else { return }
        inlineTableRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.inlineTableRefreshScheduled = false
            self?.refreshInlineTables()
        }
    }

    private func refreshInlineTables() {
        guard styler != nil, !inlineTables.contains(where: \.isEditing) else { return }
        let presentations = inlineTablePresentations()

        if let active = activeInlineTableRange {
            activeInlineTableRange = presentations.first(where: {
                $0.range.location == active.location
            })?.range
        }

        let canReuse = presentations.count == inlineTables.count
            && zip(presentations, inlineTables).allSatisfy {
                NSEqualRanges($0.range, $1.sourceRange) && $0.table == $1.table
            }
        if canReuse {
            for (presentation, view) in zip(presentations, inlineTables) {
                view.frame = presentation.frame
            }
            return
        }

        inlineTables.forEach { $0.removeFromSuperview() }
        inlineTables = presentations.map { presentation in
            let tableView = InlineTableView(frame: presentation.frame,
                                            sourceRange: presentation.range,
                                            table: presentation.table,
                                            onActivate: { [weak self] range in
                self?.activeInlineTableRange = range
            }, onMoveOutside: { [weak self] range, before in
                self?.moveCaret(outsideTable: range, before: before)
            }) { [weak self] table, range in
                self?.replace(table: table, in: range)
            }
            addSubview(tableView)
            return tableView
        }
    }

    private func inlineTablePresentations() -> [InlineTablePresentation] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        layout.ensureLayout(for: container)

        let all = styler.lines
        let ns = string as NSString
        let origin = textContainerOrigin
        let boxes = lineBoxes(layout,
                              glyphs: layout.glyphRange(for: container),
                              origin: origin)
        var result: [InlineTablePresentation] = []
        var index = 0

        while index < all.count {
            guard all[index].kind == .tableHeader else { index += 1; continue }
            let first = index
            var last = first
            while last < all.count - 1, isTableLine(all[last + 1].kind) { last += 1 }

            let headers = TableLayout.cells(of: all[first], in: ns).map(\.text)
            let delimiter = all[first...last].first(where: { $0.kind == .tableDelimiter })
                .map { TableLayout.cells(of: $0, in: ns).map(\.text) } ?? []
            let rows = all[first...last]
                .filter { $0.kind == .tableRow }
                .map { TableLayout.cells(of: $0, in: ns).map(\.text) }

            if !headers.isEmpty {
                let range = NSRange(location: all[first].range.location,
                                    length: all[last].contentsEnd - all[first].range.location)
                // La sorgente della tabella ha avanzamento zero. Usiamo la stessa
                // enumerazione dei frammenti delle altre decorazioni del documento,
                // che non dipende dal rettangolo dei caratteri nascosti.
                if let line = boxes.first(where: {
                    NSLocationInRange($0.characters.location, all[first].range)
                })?.rect {
                    let table = MarkdownTable(headers: headers, delimiter: delimiter, rows: rows)
                    let width = max(240, container.size.width)
                    let rowGutter = InlineTableView.rowControlGutter
                    let columnGutter = InlineTableView.columnControlGutter
                    let height = CGFloat(1 + table.rows.count) * InlineTableView.rowHeight
                    let frame = NSRect(x: origin.x,
                                       y: line.minY - columnGutter,
                                       width: width + rowGutter,
                                       height: height + columnGutter)
                    result.append(InlineTablePresentation(range: range, table: table, frame: frame))
                }
            }
            index = last + 1
        }
        return result
    }

    private func moveCaret(outsideTable range: NSRange, before: Bool) {
        guard let window else { return }
        _ = window.makeFirstResponder(self)
        activeInlineTableRange = nil

        let ns = string as NSString
        if before {
            if range.location == 0 {
                guard shouldChangeText(in: NSRange(location: 0, length: 0),
                                       replacementString: "\n") else { return }
                textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                setSelectedRange(NSRange(location: range.location - 1, length: 0))
            }
        } else {
            let end = min(NSMaxRange(range), ns.length)
            if end == ns.length {
                guard shouldChangeText(in: NSRange(location: end, length: 0),
                                       replacementString: "\n") else { return }
                textStorage?.replaceCharacters(in: NSRange(location: end, length: 0), with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: end + 1, length: 0))
            } else if ns.character(at: end) == 10 || ns.character(at: end) == 13 {
                setSelectedRange(NSRange(location: end + 1, length: 0))
            } else {
                guard shouldChangeText(in: NSRange(location: end, length: 0),
                                       replacementString: "\n") else { return }
                textStorage?.replaceCharacters(in: NSRange(location: end, length: 0), with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: end + 1, length: 0))
            }
        }
        scrollRangeToVisible(selectedRange())
    }

    /// Il Markdown che conserva la tabella non è una superficie di editing.
    /// Se il cursore del documento vi entra con frecce o mouse, lo spostiamo
    /// sull'altro lato del blocco; le celle restano accessibili direttamente
    /// attraverso i loro `NSTextField`.
    func normalizeSelectionOutsideTables() {
        guard !normalizingTableSelection, window?.firstResponder === self else { return }
        let selection = selectedRange()
        guard selection.length == 0 else {
            lastAllowedTextSelection = selection
            return
        }

        // Le viste vengono riallineate al ciclo di layout successivo; durante
        // la digitazione il parser, invece, contiene già gli intervalli nuovi.
        // Usarlo qui evita che la posizione della tabella rimasta indietro di
        // un carattere catturi la seconda lettera scritta nella riga sopra.
        guard let range = currentTableRange(containing: selection.location) else {
            lastAllowedTextSelection = selection
            return
        }

        let before: Bool
        if let vertical = pendingVerticalNavigation {
            before = vertical
        } else if lastAllowedTextSelection.location < range.location {
            // Arrivando da sopra, l'intera tabella si comporta come una riga.
            before = false
        } else if lastAllowedTextSelection.location > NSMaxRange(range) {
            before = true
        } else {
            let middle = range.location + range.length / 2
            before = selection.location <= middle
        }

        normalizingTableSelection = true
        moveCaret(outsideTable: range, before: before)
        lastAllowedTextSelection = selectedRange()
        normalizingTableSelection = false
    }

    private func currentTableRange(containing location: Int) -> NSRange? {
        let all = styler.lines
        var index = 0
        while index < all.count {
            guard all[index].kind == .tableHeader else {
                index += 1
                continue
            }

            let first = index
            var last = first
            while last < all.count - 1, isTableLine(all[last + 1].kind) {
                last += 1
            }
            let range = NSRange(location: all[first].range.location,
                                length: all[last].contentsEnd - all[first].range.location)
            if location >= range.location && location <= NSMaxRange(range) {
                return range
            }
            index = last + 1
        }
        return nil
    }

    /// La tabella è un insieme di celle editabili direttamente nel testo. Le
    /// barre e il delimitatore sono nascosti dallo styler; Tab attraversa quindi
    /// i soli contenuti, come in un editor di documenti.
    private func moveTableSelection(forward: Bool) -> Bool {
        let selection = selectedRange()
        guard let cells = tableCellRanges(at: selection.location), !cells.isEmpty else { return false }
        let current = cells.firstIndex {
            selection.location >= $0.location && selection.location <= NSMaxRange($0)
        } ?? 0
        let target = forward ? current + 1 : current - 1
        guard cells.indices.contains(target) else { return false }
        setSelectedRange(cells[target])
        return true
    }

    private func tableCellRanges(at location: Int) -> [NSRange]? {
        let all = styler.lines
        guard let current = all.firstIndex(where: { location >= $0.range.location && location < NSMaxRange($0.range) }),
              isTableLine(all[current].kind) else { return nil }

        var first = current
        while first > 0, isTableLine(all[first - 1].kind) { first -= 1 }
        var last = current
        while last < all.count - 1, isTableLine(all[last + 1].kind) { last += 1 }

        let ns = string as NSString
        return all[first...last]
            .filter { $0.kind == .tableHeader || $0.kind == .tableRow }
            .flatMap { TableLayout.cells(of: $0, in: ns).map(\.range) }
    }

    private func selectedLineTexts() -> [String] {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        var result: [String] = []
        ns.enumerateSubstrings(in: lineRange, options: [.byLines]) { substring, _, _, _ in
            result.append(substring ?? "")
        }
        return result
    }

    private func transformLines(_ transform: (LineInfo?, String) -> String) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: selection)
        guard lineRange.length > 0 || ns.length == 0 else { return }

        var pieces: [String] = []
        var terminators: [String] = []
        ns.enumerateSubstrings(in: lineRange, options: [.byLines]) { substring, range, enclosing, _ in
            pieces.append(substring ?? "")
            terminators.append(ns.substring(with: NSRange(location: NSMaxRange(range),
                                                          length: NSMaxRange(enclosing) - NSMaxRange(range))))
        }
        if pieces.isEmpty { pieces = [""]; terminators = [""] }

        var result = ""
        for (index, piece) in pieces.enumerated() {
            result += transform(nil, piece) + terminators[index]
        }
        guard shouldChangeText(in: lineRange, replacementString: result) else { return }
        textStorage?.replaceCharacters(in: lineRange, with: result)
        didChangeText()
        let delta = result.utf16.count - lineRange.length
        let location = min(max(lineRange.location, selection.location + delta), string.utf16.count)
        setSelectedRange(NSRange(location: location, length: 0))
    }

    // MARK: - Interazione

    override func mouseDown(with event: NSEvent) {
        activeInlineTableRange = nil
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(at: point), let storage = textStorage, index < storage.length {
            // ⌘-clic su un collegamento: lo apre nel browser.
            if event.modifierFlags.contains(.command),
               let value = storage.attribute(.auroraLink, at: index, effectiveRange: nil) as? String,
               let url = URL(string: value), url.scheme != nil {
                NSWorkspace.shared.open(url)
                return
            }
            // Clic su una casella di una task list: la commuta.
            var checkboxRange = NSRange(location: 0, length: 0)
            if storage.attribute(.auroraCheckbox, at: index, effectiveRange: &checkboxRange) != nil,
               checkboxRange.length == 3 {
                toggleCheckbox(at: checkboxRange)
                return
            }
            // Un doppio clic conserva il clic singolo per l'editing testuale,
            // ma apre una griglia per cambiare celle, righe e colonne.
            if event.clickCount == 2, let existing = markdownTable(at: index) {
                presentTableEditor(existing.table) { [weak self] table in
                    self?.replace(table: table, in: existing.range)
                }
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(at range: NSRange) {
        let ns = string as NSString
        let markRange = NSRange(location: range.location + 1, length: 1)
        let current = ns.substring(with: markRange)
        let replacement = current == " " ? "x" : " "
        let selection = selectedRange()
        guard shouldChangeText(in: markRange, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: markRange, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layout = layoutManager, let container = textContainer else { return nil }
        let origin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: nil)
        guard layout.numberOfGlyphs > 0 else { return nil }
        return layout.characterIndexForGlyph(at: min(glyph, layout.numberOfGlyphs - 1))
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        styler.handleTextChange()
        refreshSlashMenu()
        scheduleInlineTableRefresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleInlineTableRefresh()
    }

    override func layout() {
        super.layout()
        scheduleInlineTableRefresh()
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let location = selectedRange().location
        if inlineTables.contains(where: {
            location >= $0.sourceRange.location && location <= NSMaxRange($0.sourceRange)
        }) {
            return
        }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    private func currentLine(at location: Int) -> LineInfo? {
        let all = styler.lines
        for line in all where location >= line.range.location && location <= line.contentsEnd {
            return line
        }
        return all.last
    }

    // MARK: - Menu

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)),
             #selector(toggleInlineCode(_:)), #selector(toggleHighlight(_:)), #selector(setHeadingLevel(_:)),
             #selector(promoteHeading(_:)), #selector(demoteHeading(_:)),
             #selector(toggleBlockquote(_:)), #selector(toggleBulletList(_:)), #selector(toggleTaskList(_:)),
             #selector(insertHorizontalRule(_:)), #selector(insertLink(_:)), #selector(insertCodeBlock(_:)),
             #selector(insertTable(_:)):
            return isEditable
        case #selector(editTable(_:)):
            return isEditable && (activeInlineTableRange != nil
                || markdownTable(at: selectedRange().location) != nil)
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
