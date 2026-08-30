import Foundation
import AuroraCore

/// Comodità: analizza un documento e restituisce i tipi di riga in ordine.
private func kinds(_ text: String) -> [LineKind] {
    MarkdownParser.parse(text as NSString).map(\.kind)
}

private func lines(_ text: String) -> [LineInfo] {
    MarkdownParser.parse(text as NSString)
}

func runBlockTests() {
    Check.suite("titoli") {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            Check.equal(kinds("\(hashes) Titolo").first, .heading(level: level),
                        "\(hashes) apre un titolo di livello \(level)")
        }
        // Senza spazio non è un titolo: è la regola che salva gli hashtag.
        Check.equal(kinds("#nonUnTitolo").first, .paragraph, "'#parola' resta un paragrafo")
        Check.equal(kinds("####### sette").first, .paragraph, "sette cancelletti non sono un titolo")
    }

    Check.suite("elenchi") {
        for marker in ["-", "*", "+"] {
            Check.equal(kinds("\(marker) voce").first, .bulletItem, "'\(marker)' apre un elenco")
        }
        Check.equal(kinds("1. voce").first, .orderedItem, "'1.' apre un elenco numerato")
        Check.equal(kinds("1) voce").first, .orderedItem, "'1)' apre un elenco numerato")
        Check.equal(lines("1) voce")[0].listMarkerText, "1)",
                    "il marcatore conserva la parentesi, per continuare l'elenco com'era")
        Check.equal(lines("  - due")[0].listIndent, 1, "due spazi sono un livello di rientro")
        Check.equal(lines("    - tre")[0].listIndent, 2, "quattro spazi sono due livelli")
    }

    Check.suite("caselle") {
        let vuota = lines("- [ ] da fare")[0]
        Check.expect(vuota.checkboxRange != nil, "'- [ ]' ha una casella")
        Check.expect(!vuota.checkboxChecked, "'- [ ]' non è spuntata")
        let piena = lines("- [x] fatto")[0]
        Check.expect(piena.checkboxRange != nil, "'- [x]' ha una casella")
        Check.expect(piena.checkboxChecked, "'- [x]' è spuntata")
        Check.expect(lines("- [X] fatto")[0].checkboxChecked, "anche la X maiuscola spunta")
        Check.expect(lines("[x] senza elenco")[0].checkboxRange == nil,
                     "senza elenco non c'è casella")
    }

    Check.suite("citazioni") {
        Check.equal(lines("> uno")[0].quoteDepth, 1, "un '>' è un livello")
        Check.equal(lines("> > due")[0].quoteDepth, 2, "'> >' sono due livelli")
        Check.equal(lines(">> due")[0].quoteDepth, 2, "'>>' sono due livelli anche senza spazio")
        Check.equal(lines("testo > non citazione")[0].quoteDepth, 0,
                    "un '>' a metà riga non cita")
    }

    Check.suite("linee orizzontali") {
        for rule in ["---", "***", "___", "- - -", "----------"] {
            Check.equal(kinds(rule).first, .horizontalRule, "'\(rule)' è una linea")
        }
        Check.equal(kinds("--").first, .paragraph, "due trattini non bastano")
    }

    Check.suite("blocchi di codice") {
        let chiuso = kinds("```\nx\n```\ndopo")
        Check.equal(chiuso, [.fence, .codeBody, .fence, .paragraph],
                    "un recinto chiuso racchiude solo ciò che sta dentro")
        // Comportamento voluto, e conforme al Markdown: senza chiusura il
        // codice continua fino in fondo.
        Check.equal(kinds("```\nx\ndopo"), [.fence, .codeBody, .codeBody],
                    "un recinto aperto rende codice tutto il resto")
        Check.equal(kinds("~~~\nx\n~~~"), [.fence, .codeBody, .fence],
                    "anche la tilde apre un recinto")
        // Un recinto si chiude solo con lo stesso carattere: altrimenti un
        // esempio di Markdown dentro un blocco lo spezzerebbe a metà.
        Check.equal(kinds("```\n~~~\nx\n```"), [.fence, .codeBody, .codeBody, .fence],
                    "la tilde non chiude un recinto di apici")
        Check.expect(lines("```\nx\n```")[1].isInsideFence, "la riga interna sa di essere in un recinto")
    }

    Check.suite("tabelle") {
        Check.equal(kinds("| a | b |\n| --- | --- |\n| 1 | 2 |"),
                    [.tableHeader, .tableDelimiter, .tableRow],
                    "intestazione, delimitatore e riga")
        // Senza la riga dei trattini non è una tabella: sono solo barre.
        Check.equal(kinds("| a | b |\n| 1 | 2 |"), [.paragraph, .paragraph],
                    "senza delimitatore non è una tabella")
        Check.equal(kinds("| a | b |\n| :-- | --: |\n| 1 | 2 |"),
                    [.tableHeader, .tableDelimiter, .tableRow],
                    "il delimitatore accetta gli allineamenti")
    }

    Check.suite("fine del documento") {
        Check.equal(lines("").count, 1, "un documento vuoto ha una riga")
        Check.equal(lines("a\n").count, 2, "un a capo finale lascia una riga vuota dopo")
        Check.equal(lines("a").count, 1, "senza a capo finale non si inventa una riga")
        Check.equal(kinds("```\nx\n").last, .codeBody,
                    "la riga finale dentro un recinto aperto è ancora codice")
    }

    Check.suite("intervalli") {
        let ns = "> - voce" as NSString
        let line = lines("> - voce")[0]
        Check.equal(ns.substring(with: line.contentRange), "voce",
                    "il contenuto esclude i prefissi di citazione ed elenco")
        Check.equal(line.range.length, ns.length, "la riga copre tutto il testo")
    }
}
