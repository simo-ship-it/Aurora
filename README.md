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
| Titoli `#` … `######` | Sei livelli, con dimensioni dedicate |
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
- **⌘B**, **⌘I**, **⇧⌘X**, **⇧⌘H** applicano e tolgono grassetto, corsivo,
  barrato ed evidenziato.
- **⌘1 … ⌘6** impostano il livello del titolo, **⌘0** torna a paragrafo.
- **⇧⌘U** elenco puntato, **⇧⌘T** elenco di attività, **⌥⌘K** blocco di codice,
  **⌘K** collegamento.
- **⌘F** cerca nel documento, con la barra di ricerca di sistema.
- Un clic su una casella `[ ]` la spunta; **⌘-clic** su un collegamento lo apre.

Codice inline, citazione e linea orizzontale si prendono dal menu **Formato**: le loro
scorciatoie (⌘`, ⇧⌘', ⇧⌘-) sono dichiarate su tasti di punteggiatura che con layout
non statunitensi — l'italiano fra questi — stanno altrove, quindi non rispondono.

Annulla/ripristina, salvataggio automatico, versioni, documenti recenti e schede
delle finestre sono quelli standard di macOS.

## Cartella di lavoro

Il pulsante a forma di cartella in barra del titolo apre l'albero della cartella su cui
stai lavorando: le sottocartelle si aprono sul posto, i file si aprono con un clic.
Per sceglierne un'altra, **⌘⇧O** oppure un clic sul nome della cartella in cima al
pannello.

I figli di una cartella si leggono dal disco solo quando la si apre, quindi un albero
profondo non costa nulla finché resta chiuso. La cartella scelta e quali sono aperte
sopravvivono alla chiusura dell'app. Se non ne hai ancora scelta una, il pannello
adotta la cartella del primo documento che apri.

Elenca solo `.md`, `.markdown`, `.mdown`, `.mkd`, `.mdtext` e `.txt`: serve a scrivere,
non a esplorare il disco. La prima volta che punti la cartella dentro Documenti,
Scrivania o Download, macOS chiede il permesso di accedervi.

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
  Workspace.swift          cartella di lavoro e stato dell'albero, su UserDefaults
  WorkspaceBrowser.swift   pulsante in barra del titolo e albero dei file
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

C'è poi una regola che tiene fermo il testo mentre lo scrivi: **la geometria verticale
di una riga non dipende dal cursore, e nessun tipo di riga aggiunge spazio sopra o
sotto di sé**. La separazione la danno le righe vuote — che in Markdown sono anche il
modo in cui la separazione è scritta nel file. Senza questo vincolo il testo scappa da
sotto le dita: lo spazio nascerebbe nell'istante in cui la riga cambia natura, cioè
mentre ci stai ancora scrivendo dentro. Per questo `paragraphStyle` non riceve lo stato
di selezione: il vincolo lo fa rispettare il compilatore, non la memoria di chi tocca
il file. Resta il solo scarto del corpo più grande di un titolo, due punti.

## Limiti attuali

- Le tabelle sono allineate a spaziatura fissa, non disegnate come griglia.
- Le immagini `![](…)` sono mostrate come collegamento, non incorporate.
- I blocchi di codice indentati di quattro spazi non sono riconosciuti come tali
  (servono i delimitatori ` ``` `), per non alterare gli elenchi annidati.
- Nessuna evidenziazione della sintassi dentro i blocchi di codice.
- Titoli in stile setext (sottolineati con `===`) non riconosciuti.
- Aprire un recinto ` ``` ` senza chiuderlo rende codice tutto il resto del documento,
  come vuole il Markdown: il testo sotto si riorganizza finché non lo chiudi.

## Difetti noti

- **⇧Tab aumenta il rientro invece di ridurlo.** `insertBacktab` è implementato
  correttamente ma non viene raggiunto: l'evento arriva come `insertTab:`.
- **⌘` , ⇧⌘' e ⇧⌘- non rispondono** con tastiere non statunitensi. I comandi
  funzionano dal menu Formato.
- **I marcatori inglobano l'a-capo finale.** Su un documento che termina con una riga
  a capo, ⌘A seguito da ⌘B mette il `**` di chiusura su una riga a sé e l'emfasi non
  si chiude.
- **Tabelle con delimitatore a trattino singolo** (`| - | - |`) non riconosciute: il
  controllo conta i trattini dell'intera riga e ne pretende tre, mentre GFM ne chiede
  uno per cella.
