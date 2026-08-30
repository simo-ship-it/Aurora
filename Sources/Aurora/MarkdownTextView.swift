import AppKit

final class MarkdownTextView: NSTextView, NSLayoutManagerDelegate {

    var styler: MarkdownStyler!
    private var theme: Theme { Theme.current }

    private let slashMenu = SlashMenuController()
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
        backgroundColor = theme.background
        insertionPointColor = theme.insertionPoint
        textContainerInset = NSSize(width: 0, height: theme.topInset)
        defaultParagraphStyle = nil
        typingAttributes = [.font: theme.body, .foregroundColor: theme.text]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
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
        super.keyDown(with: event)
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
                property.insert(.null)
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

    // MARK: - Decorazioni (blocchi di codice, citazioni, linee, elenchi)

    /// Un frammento di riga con l'intervallo di caratteri che copre, già nelle
    /// coordinate della vista.
    private struct LineBox {
        let characters: NSRange
        let rect: NSRect
    }

    /// Le righe inquadrate, con i caratteri di ciascuna.
    ///
    /// È il perno di tutto il disegno delle decorazioni. La strada opposta —
    /// chiedere al layout manager dove sta il glifo di un dato carattere — qui non
    /// si può percorrere: Aurora nasconde la sintassi assegnando il *glifo nullo*,
    /// e per un carattere nascosto quella domanda può rispondere con un glifo della
    /// riga precedente, mandando la decorazione una riga più su. Enumerare i
    /// frammenti e chiedere a ciascuno quali caratteri copre funziona invece
    /// sempre, perché un glifo nullo appartiene comunque al frammento della sua riga.
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
        /// Non si può chiedere quale riga *contiene* il primo carattere: i caratteri
        /// nascosti hanno glifo nullo e il layout li attribuisce al frammento della
        /// riga precedente. Cercare a partire da loro atterra sempre una riga più su
        /// — la linea orizzontale disegnata sopra i trattini, il riquadro del codice
        /// che parte una riga prima. Il frammento della riga giusta, invece,
        /// comincia sempre dentro l'intervallo: al più contiene solo l'a-capo.
        func rows(in range: NSRange) -> [NSRect] {
            boxes.filter { NSLocationInRange($0.characters.location, range) }.map(\.rect)
        }

        /// L'area coperta da una decorazione, o `nil` se non è inquadrata.
        func box(for range: NSRange) -> NSRect? {
            rows(in: range).reduce(nil) { (union: NSRect?, row) in union.map { $0.union(row) } ?? row }
        }

        // Superfici dei blocchi: codice e tabelle condividono lo stesso grigio stondato.
        storage.enumerateAttribute(.auroraBlock, in: visible) { value, range, _ in
            guard let kind = value as? String else { return }
            switch kind {
            case "code", "table":
                guard var surface = box(for: range) else { return }
                surface.origin.x = origin.x
                surface.size.width = contentWidth
                // Il codice ha già aria dalle righe ``` nascoste; la tabella no.
                surface = surface.insetBy(dx: 0, dy: kind == "code" ? -2 : -10)
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

        // Filetto sotto l'intestazione della tabella, al posto della riga di trattini.
        storage.enumerateAttribute(.auroraTableRule, in: visible) { value, range, _ in
            guard value != nil, let row = rows(in: range).first else { return }
            theme.rule.setFill()
            NSRect(x: origin.x + theme.surfacePadding,
                   y: (row.midY - 0.5).rounded(),
                   width: contentWidth - theme.surfacePadding * 2, height: 1).fill()
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
        let selection = selectedRange()
        if selection.length > 0 || currentLine(at: selection.location)?.kind == .bulletItem
            || currentLine(at: selection.location)?.kind == .orderedItem {
            shiftIndent(by: 2)
        } else {
            insertText("    ", replacementRange: selection)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        shiftIndent(by: -2)
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
        let selection = selectedRange()
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
        let text = selection.length > 0 ? ns.substring(with: selection) : "testo"
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
             #selector(toggleBlockquote(_:)), #selector(toggleBulletList(_:)), #selector(toggleTaskList(_:)),
             #selector(insertHorizontalRule(_:)), #selector(insertLink(_:)), #selector(insertCodeBlock(_:)):
            return isEditable
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
