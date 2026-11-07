import Foundation
import AuroraCore

/// I brani con il loro stile, come li vede chi legge: il testo che resta
/// visibile, senza i marcatori.
private func runs(_ text: String) -> [(String, InlineStyle)] {
    let ns = text as NSString
    return MarkdownParser.parseInline(ns, range: NSRange(location: 0, length: ns.length))
        .runs.map { (ns.substring(with: $0.range), $0.style) }
}

private func style(of text: String, _ fragment: String) -> InlineStyle? {
    runs(text).first { $0.0 == fragment }?.1
}

private func url(in text: String) -> String? {
    let ns = text as NSString
    return MarkdownParser.parseInline(ns, range: NSRange(location: 0, length: ns.length))
        .runs.compactMap(\.url).first
}

private func inline(_ text: String) -> InlineResult {
    let ns = text as NSString
    return MarkdownParser.parseInline(ns, range: NSRange(location: 0, length: ns.length))
}

func runInlineTests() {
    Check.suite("emfasi") {
        Check.equal(style(of: "**grassetto**", "grassetto"), .bold, "** è grassetto")
        Check.equal(style(of: "*corsivo*", "corsivo"), .italic, "* è corsivo")
        Check.equal(style(of: "***entrambi***", "entrambi"), [.bold, .italic],
                    "*** è grassetto e corsivo insieme")
        Check.equal(style(of: "__grassetto__", "grassetto"), .bold, "__ è grassetto")
        Check.equal(style(of: "_corsivo_", "corsivo"), .italic, "_ è corsivo")
        Check.equal(style(of: "~~barrato~~", "barrato"), .strike, "~~ è barrato")
        Check.equal(style(of: "==evidenziato==", "evidenziato"), .highlight, "== è evidenziato")
        Check.equal(style(of: "`codice`", "codice"), .code, "l'apice inverso è codice")
        Check.equal(style(of: "<u>sottolineato</u>", "sottolineato"), .underline,
                    "<u> applica il sottolineato")
    }

    Check.suite("delimitatori modificabili") {
        let combined = inline("***entrambi***")
        Check.equal(combined.formats.count, 1,
                    "il formato combinato conserva una sola coppia di delimitatori")
        Check.equal(combined.formats.first?.style, [.bold, .italic],
                    "la coppia *** ricorda entrambi gli stili")
        Check.equal(combined.formats.first?.contentRange, NSRange(location: 3, length: 8),
                    "il formato espone il contenuto senza i delimitatori")

        let nested = inline("**grassetto e *corsivo***")
        Check.equal(nested.formats.count, 2,
                    "i formati annidati conservano due coppie indipendenti")
        Check.equal(nested.formats.map(\.style).contains(.bold), true,
                    "la coppia esterna resta identificabile")
        Check.equal(nested.formats.map(\.style).contains(.italic), true,
                    "la coppia interna resta identificabile")
    }

    Check.suite("emfasi che non si apre") {
        // In mezzo a una parola l'underscore non enfatizza: altrimenti ogni
        // nome_di_variabile diventerebbe corsivo.
        Check.equal(runs("nome_di_variabile").map(\.0), ["nome_di_variabile"],
                    "l'underscore dentro una parola non enfatizza: un brano solo, senza stile")
        Check.equal(style(of: "`**non grassetto**`", "**non grassetto**"), .code,
                    "dentro il codice i marcatori sono testo")
        Check.equal(runs("\\*non corsivo\\*").map(\.1), [[]],
                    "il backslash annulla il marcatore")
        Check.equal(runs("2 * 3 * 4").map(\.1), [[]],
                    "gli asterischi isolati non enfatizzano")
    }

    Check.suite("collegamenti") {
        Check.equal(style(of: "[testo](https://esempio.it)", "testo"), .link,
                    "la parte fra parentesi quadre è il collegamento")
        Check.equal(url(in: "[testo](https://esempio.it)"), "https://esempio.it",
                    "l'indirizzo viene estratto")
        Check.equal(url(in: "<https://esempio.it>"), "https://esempio.it",
                    "anche un indirizzo nudo fra parentesi angolari")
        Check.equal(style(of: "![alt](img.png)", "alt"), .image,
                    "il punto esclamativo distingue l'immagine dal collegamento")
        Check.equal(url(in: "![alt](img.png)"), "img.png", "l'immagine porta il proprio indirizzo")
        Check.equal(inline("![alt](img.png)").images.first?.url, "img.png",
                    "l'immagine espone una vera anteprima oltre allo stile del testo alternativo")
    }

    Check.suite("collegamenti estesi") {
        Check.equal(url(in: "https://esempio.it/percorso"), "https://esempio.it/percorso",
                    "un URL nudo diventa un collegamento GFM")
        Check.equal(url(in: "www.esempio.it"), "http://www.esempio.it",
                    "www riceve automaticamente lo schema HTTP")
        Check.equal(url(in: "nome@example.com"), "mailto:nome@example.com",
                    "un indirizzo email nudo diventa mailto")
        Check.equal(url(in: "<nome@example.com>"), "mailto:nome@example.com",
                    "anche l'autolink email fra parentesi angolari")
        Check.equal(style(of: "<x:y>", "<x:y>"), [],
                    "uno schema di un solo carattere non è un autolink CommonMark")
        Check.equal(url(in: "[testo](<cartella con spazi/file.md>)"),
                    "cartella con spazi/file.md",
                    "una destinazione fra parentesi angolari conserva gli spazi")
    }

    Check.suite("collegamenti di riferimento") {
        let document = "[Aurora][sito]\n\n[sito]: https://example.com"
        let ns = document as NSString
        let firstLine = NSRange(location: 0, length: ("[Aurora][sito]" as NSString).length)
        let parsed = MarkdownParser.parseInline(ns, range: firstLine,
                                                references: MarkdownParser.analyze(ns).references)
        Check.equal(parsed.runs.compactMap(\.url).first, "https://example.com",
                    "un riferimento completo risolve la definizione nel documento")

        let shortcut = "[sito]\n\n[sito]: https://example.com" as NSString
        let shortcutResult = MarkdownParser.parseInline(
            shortcut, range: NSRange(location: 0, length: 6),
            references: MarkdownParser.analyze(shortcut).references)
        Check.equal(shortcutResult.runs.compactMap(\.url).first, "https://example.com",
                    "anche un riferimento abbreviato viene risolto")
    }

    Check.suite("inline multilinea") {
        Check.equal(style(of: "*prima\nseconda*", "prima\nseconda"), .italic,
                    "l'enfasi può attraversare un soft break")
    }
}

func runEditingTests() {
    /// Il testo effettivamente racchiuso, dato ciò che l'utente ha selezionato.
    func wrapped(_ text: String, _ selection: NSRange) -> String {
        let ns = text as NSString
        return ns.substring(with: MarkdownEditing.emphasisRange(in: ns, selection: selection))
    }

    Check.suite("selezione da enfatizzare") {
        Check.equal(wrapped("ciao", NSRange(location: 0, length: 4)), "ciao",
                    "una selezione pulita non cambia")

        // Il caso che rompeva il documento: ⌘A su un file che finisce con un
        // a capo metteva il marcatore di chiusura su una riga a sé.
        Check.equal(wrapped("ciao\n", NSRange(location: 0, length: 5)), "ciao",
                    "l'a capo finale resta fuori dai marcatori")
        Check.equal(wrapped("uno\ndue\n", NSRange(location: 0, length: 8)), "uno\ndue",
                    "di più righe si tiene fuori solo l'a capo finale")
        Check.equal(wrapped("  ciao  ", NSRange(location: 0, length: 8)), "ciao",
                    "gli spazi ai bordi restano fuori: dentro impedirebbero la chiusura")

        // Una selezione di soli spazi diventa un punto: si inseriscono i
        // marcatori vuoti e si scrive in mezzo, senza inghiottire lo spazio.
        let solaSpaziatura = MarkdownEditing.emphasisRange(in: "a   b" as NSString,
                                                           selection: NSRange(location: 1, length: 3))
        Check.equal(solaSpaziatura, NSRange(location: 1, length: 0),
                    "una selezione di soli spazi si riduce a un punto")

        let vuota = MarkdownEditing.emphasisRange(in: "ciao" as NSString,
                                                  selection: NSRange(location: 2, length: 0))
        Check.equal(vuota, NSRange(location: 2, length: 0), "un cursore senza selezione resta dov'è")
    }

    Check.suite("grado dei titoli") {
        Check.equal(MarkdownEditing.promoteHeading("Testo"), "###### Testo",
                    "alzare un paragrafo lo trasforma in H6")
        Check.equal(MarkdownEditing.promoteHeading("###### Testo"), "##### Testo",
                    "alzare H6 lo trasforma in H5")
        Check.equal(MarkdownEditing.promoteHeading("## Testo"), "# Testo",
                    "alzare H2 lo trasforma in H1")
        Check.equal(MarkdownEditing.promoteHeading("# Testo"), "# Testo",
                    "H1 è il grado massimo")

        Check.equal(MarkdownEditing.demoteHeading("# Testo"), "## Testo",
                    "abbassare H1 lo trasforma in H2")
        Check.equal(MarkdownEditing.demoteHeading("###### Testo"), "Testo",
                    "abbassare H6 lo trasforma in paragrafo")
        Check.equal(MarkdownEditing.demoteHeading("Testo"), "Testo",
                    "un paragrafo è il grado minimo")
        Check.equal(MarkdownEditing.promoteHeading("#hashtag"), "###### #hashtag",
                    "un hashtag senza spazio resta contenuto del paragrafo")
    }

    Check.suite("rimozione stile inline") {
        let text = "***testo***" as NSString
        let format = MarkdownParser.parseInline(text,
                                                range: NSRange(location: 0, length: text.length))
            .formats[0]
        let selection = NSRange(location: 4, length: 3)

        let withoutBold = MarkdownEditing.removingInlineStyle(.bold, from: format, in: text,
                                                               preserving: selection)
        Check.equal(withoutBold?.replacement, "*testo*",
                    "togliere il grassetto da *** conserva il corsivo")
        Check.equal(withoutBold?.selectionAfterEdit, NSRange(location: 2, length: 3),
                    "una selezione parziale resta sullo stesso testo visibile")

        let withoutItalic = MarkdownEditing.removingInlineStyle(.italic, from: format, in: text,
                                                                 preserving: selection)
        Check.equal(withoutItalic?.replacement, "**testo**",
                    "togliere il corsivo da *** conserva il grassetto")
        Check.equal(withoutItalic?.selectionAfterEdit, NSRange(location: 3, length: 3),
                    "gli indici tengono conto dei delimitatori rimasti")

        let underlined = "<u>testo</u>" as NSString
        let underlineFormat = MarkdownParser.parseInline(
            underlined, range: NSRange(location: 0, length: underlined.length)).formats[0]
        let withoutUnderline = MarkdownEditing.removingInlineStyle(
            .underline, from: underlineFormat, in: underlined,
            preserving: NSRange(location: 3, length: 5))
        Check.equal(withoutUnderline?.replacement, "testo",
                    "togliere il sottolineato elimina entrambi i tag asimmetrici")
        Check.equal(withoutUnderline?.selectionAfterEdit, NSRange(location: 0, length: 5),
                    "la selezione resta sul testo dopo la rimozione dei tag")
    }

    Check.suite("applicazione su selezione mista") {
        let mixed = "**grassetto** normale" as NSString
        let mixedResult = MarkdownParser.parseInline(
            mixed, range: NSRange(location: 0, length: mixed.length))
        let boldAll = MarkdownEditing.applyingInlineStyle(
            .bold, to: NSRange(location: 2, length: 19), formats: mixedResult.formats,
            in: mixed, opening: "**", closing: "**")
        Check.equal(boldAll?.replacement, "**grassetto normale**",
                    "grassetto più testo normale diventa un solo segmento grassetto")
        Check.equal(boldAll?.selectionAfterEdit, NSRange(location: 2, length: 17),
                    "la selezione non include i vecchi delimitatori eliminati")

        let combined = "***entrambi*** normale" as NSString
        let combinedResult = MarkdownParser.parseInline(
            combined, range: NSRange(location: 0, length: combined.length))
        let combinedBold = MarkdownEditing.applyingInlineStyle(
            .bold, to: NSRange(location: 3, length: 19), formats: combinedResult.formats,
            in: combined, opening: "**", closing: "**")
        Check.equal(combinedBold?.replacement, "__*entrambi* normale__",
                    "il grassetto misto conserva il corsivo senza creare asterischi ambigui")

        if let replacement = combinedBold?.replacement {
            let reparsed = inline(replacement)
            Check.equal(reparsed.runs.first { ($0.range.location...NSMaxRange($0.range))
                .contains(3) }?.style.contains(.bold), true,
                "il risultato normalizzato resta grassetto valido")
        }
    }
}
