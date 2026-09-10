import Foundation
import AuroraCore

func runTableTests() {
    Check.suite("tabelle modificabili") {
        var table = MarkdownTable(headers: ["Nome", "Stato"], rows: [["Aurora", "Pronta"]])
        Check.equal(table.markdown,
                    "| Nome | Stato |\n| --- | --- |\n| Aurora | Pronta |",
                    "la tabella viene scritta come Markdown GFM")

        table.resize(dataRows: 2, columns: 3)
        Check.equal(table.headers.count, 3, "aggiungere una colonna allarga l'intestazione")
        Check.equal(table.rows.count, 2, "aggiungere una riga conserva i dati esistenti")
        Check.equal(table.rows[0].count, 3, "ogni riga ha sempre tutte le colonne")

        table.headers[2] = "Note"
        table.rows[1] = ["riga", "nuova", "ok"]
        Check.expect(table.markdown.contains("| riga | nuova | ok |"),
                     "i dati inseriti nella griglia finiscono nel Markdown")

        let safe = MarkdownTable(headers: ["a|b"], rows: [["una\ndue"]])
        Check.equal(safe.markdown, "| a¦b |\n| --- |\n| una due |",
                    "una cella non può spezzare la struttura della tabella")
    }
}
