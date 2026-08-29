# Aurora

Editor Markdown nativo per macOS, scritto in Swift e AppKit. Come Typora, mostra il
testo già formattato **mentre lo scrivi**: non c'è un riquadro di anteprima separato,
c'è una sola area di scrittura in cui i marcatori Markdown si nascondono quando il
cursore non è sulla riga e ricompaiono appena ci torni.

Il file su disco resta Markdown puro: nessun formato proprietario, nessuna conversione.

## Compilare ed eseguire

Servono solo i Command Line Tools di Xcode (niente Xcode completo).

```bash
./Scripts/build_app.sh
```

Lo script compila con SwiftPM e assembla `Aurora.app` nella cartella del progetto.
Poi basta aprirla:

```bash
open Aurora.app Esempio.md
```

Per lo sviluppo quotidiano è comodo anche `swift build` da solo, ma l'apertura dei
file dal Finder e il menu documenti funzionano solo eseguendo il bundle `.app`.

## Cosa supporta

| Elemento | Resa |
| --- | --- |
| Titoli `#` … `######` | Sei livelli, con dimensioni e spaziature dedicate |
| `**grassetto**`, `*corsivo*`, `***entrambi***` | Font reale, marcatori nascosti |
| `~~barrato~~`, `==evidenziato==` | Barratura e sfondo giallo |
| `` `codice inline` `` | Font a spaziatura fissa con sfondo |
| Blocchi ` ``` ` e `~~~` | Riquadro grigio, righe di delimitazione nascoste |
| Citazioni `>` (anche annidate) | Barra laterale e rientro per livello |
| Elenchi `-`, `*`, `+`, `1.`, `1)` | Pallini disegnati, rientri automatici |
| Task list `- [ ]` / `- [x]` | Casella cliccabile, voce completata barrata |
| `[testo](url)` e `<url>` | Collegamento colorato, apribile con ⌘-clic |
| `---`, `***`, `___` | Linea orizzontale disegnata |
| Tabelle `\| a \| b \|` | Allineate a spaziatura fissa, intestazione in grassetto |

## Scrittura

- **Invio** continua l'elenco, la numerazione o la citazione della riga corrente;
  su un elemento vuoto esce dall'elenco.
- **Tab / ⇧Tab** aumentano e riducono il rientro degli elementi.
- **⌘B**, **⌘I**, **⇧⌘X**, **⌘`**, **⇧⌘H** applicano e tolgono grassetto, corsivo,
  barrato, codice ed evidenziato.
- **⌘1 … ⌘6** impostano il livello del titolo, **⌘0** torna a paragrafo.
- **⇧⌘U** elenco puntato, **⇧⌘T** elenco di attività, **⇧⌘'** citazione,
  **⌥⌘K** blocco di codice, **⌘K** collegamento, **⇧⌘-** linea orizzontale.
- **⌘F** cerca nel documento, con la barra di ricerca di sistema.
- Un clic su una casella `[ ]` la spunta; **⌘-clic** su un collegamento lo apre.

Annulla/ripristina, salvataggio automatico, versioni, documenti recenti e schede
delle finestre sono quelli standard di macOS.

## Com'è fatto

```
Sources/Aurora/
  main.swift               avvio dell'applicazione
  AppDelegate.swift        menu e ciclo di vita
  MarkdownDocument.swift   NSDocument: lettura e scrittura UTF-8
  EditorViewController.swift  area di scrittura, colonna centrata, scorrimento
  MarkdownTextView.swift   NSTextView: glifi nascosti, decorazioni, comandi di editing
  MarkdownParser.swift     analisi di blocchi e elementi inline (solo indici, nessuna copia)
  MarkdownStyler.swift     dal risultato dell'analisi agli attributi del testo
  Theme.swift              font, colori chiari/scuri, metriche
```

Il punto delicato è nascondere la sintassi senza toccare il testo. Aurora usa lo
stack TextKit 1 e, tramite il delegato del layout manager, assegna il glifo nullo ai
caratteri marcati con un attributo interno: i marcatori restano nel documento ma non
occupano spazio. Quando la selezione entra in una riga, l'attributo viene tolto e i
marcatori riappaiono in grigio.

Per restare fluido su file grandi, lo stile non viene ricalcolato ovunque a ogni
tasto: si aggiornano le righe modificate, quelle che entrano o escono dalla selezione
e quelle che compaiono scorrendo. L'unico caso in cui serve andare oltre è l'apertura
o la chiusura di un blocco di codice, che cambia l'aspetto di tutto ciò che segue: lo
styler se ne accorge confrontando lo stato dei blocchi prima e dopo la modifica.

## Limiti attuali

- Le tabelle sono allineate a spaziatura fissa, non disegnate come griglia.
- Le immagini `![](…)` sono mostrate come collegamento, non incorporate.
- I blocchi di codice indentati di quattro spazi non sono riconosciuti come tali
  (servono i delimitatori ` ``` `), per non alterare gli elenchi annidati.
- Nessuna evidenziazione della sintassi dentro i blocchi di codice.
- Titoli in stile setext (sottolineati con `===`) non riconosciuti.
