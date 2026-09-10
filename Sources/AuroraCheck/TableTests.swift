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

        var positioned = MarkdownTable(headers: ["A", "B"],
                                       rows: [["1A", "1B"], ["2A", "2B"]])
        Check.expect(positioned.insertDataRow(after: 0),
                     "il più inserisce una riga sotto quella scelta")
        Check.equal(positioned.rows, [["1A", "1B"], ["", ""], ["2A", "2B"]],
                    "la nuova riga mantiene la posizione scelta")
        Check.expect(positioned.insertColumn(after: 0),
                     "il più inserisce una colonna dopo quella scelta")
        Check.equal(positioned.headers, ["A", "", "B"],
                    "la nuova colonna mantiene la posizione scelta")
        Check.equal(positioned.rows[2], ["2A", "", "2B"],
                    "le celle della nuova colonna sono vuote")

        Check.expect(table.removeDataRow(at: 0), "si può rimuovere una riga specifica")
        Check.equal(table.rows, [["riga", "nuova", "ok"]],
                    "rimuovere una riga conserva quella selezionata")
        Check.expect(!table.removeDataRow(at: 0),
                     "la tabella conserva almeno una riga di dati")

        Check.expect(table.removeColumn(at: 1), "si può rimuovere una colonna specifica")
        Check.equal(table.headers, ["Nome", "Note"],
                    "rimuovere una colonna conserva le intestazioni circostanti")
        Check.equal(table.rows, [["riga", "ok"]],
                    "rimuovere una colonna conserva le celle circostanti")
        Check.expect(table.removeColumn(at: 1), "si può ridurre la tabella a una colonna")
        Check.expect(!table.removeColumn(at: 0),
                     "la tabella conserva almeno una colonna")

        let safe = MarkdownTable(headers: ["a|b"], rows: [["una\ndue"]])
        Check.equal(safe.markdown, "| a¦b |\n| --- |\n| una due |",
                    "una cella non può spezzare la struttura della tabella")
    }
}
