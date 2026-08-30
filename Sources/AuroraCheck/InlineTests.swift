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
}
