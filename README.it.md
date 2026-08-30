# Aurora

[![CI](https://github.com/simo-ship-it/Aurora/actions/workflows/ci.yml/badge.svg)](https://github.com/simo-ship-it/Aurora/actions/workflows/ci.yml)
[![Licenza: MIT](https://img.shields.io/badge/Licenza-MIT-blue.svg)](LICENSE)

Editor Markdown nativo per macOS, scritto in Swift e AppKit. Come Typora, mostra il
testo già formattato **mentre lo scrivi**: non c'è un riquadro di anteprima separato,
c'è una sola area di scrittura in cui i marcatori Markdown si nascondono quando il
cursore non è sulla riga e ricompaiono appena ci torni.

Il file su disco resta Markdown puro: nessun formato proprietario, nessuna conversione.

*[Read me in English](README.md)*

<!-- TODO: aggiungere qui una schermata o una GIF breve — per un editor che si
     gioca tutto su come appare il testo mentre scrivi, la tabella delle
     funzionalità non basta. -->

## Installare

```bash
brew install --cask simo-ship-it/aurora/aurora
```

Oppure scarica lo `.zip` dai [rilasci](https://github.com/simo-ship-it/Aurora/releases),
scompattalo e trascina Aurora in Applicazioni. Serve macOS 13 o successivo; il
pacchetto è universale (Apple silicon e Intel).

## Compilare dai sorgenti

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
| Tabelle `\| a \| b \|` | Colonne allineate, intestazione in grassetto, allineamenti `:---:` |

## Scrittura

- **Invio** continua l'elenco, la numerazione o la citazione della riga corrente;
  su un elemento vuoto esce dall'elenco.
- **Tab** e **⇧Tab** aumentano entrambi il rientro degli elementi. Per ridurlo si
  tolgono gli spazi a mano: è una scelta, non una dimenticanza.
- **⌘B**, **⌘I**, **⇧⌘X**, **⇧⌘H** applicano e tolgono grassetto, corsivo,
  barrato ed evidenziato.
- **⌘1 … ⌘6** impostano il livello del titolo, **⌘0** torna a paragrafo.
- **⇧⌘U** elenco puntato, **⇧⌘T** elenco di attività, **⌥⌘K** blocco di codice,
  **⌘K** collegamento.
- **/** apre il menu dei comandi (vedi sotto).
- **⌘F** cerca nel documento, con la barra di ricerca di sistema.
- Un clic su una casella `[ ]` la spunta; **⌘-clic** su un collegamento lo apre.

Codice inline, citazione e linea orizzontale si prendono dal menu **Formato**: le loro
scorciatoie (⌘`, ⇧⌘', ⇧⌘-) sono dichiarate su tasti di punteggiatura che con layout
non statunitensi — l'italiano fra questi — stanno altrove, quindi non rispondono.

Annulla/ripristina, salvataggio automatico, versioni, documenti recenti e schede
delle finestre sono quelli standard di macOS.

## Menu dei comandi

Digitando **/** a inizio riga, o dopo uno spazio, si apre un elenco di tutti i comandi
di formattazione: titoli, elenchi, citazione, blocco di codice, linea orizzontale,
collegamento, grassetto, corsivo, barrato, evidenziato, codice inline. Continuando a
scrivere si filtra, **↑ ↓** scorrono, **Invio** o un clic applicano, **Esc** chiude.
Il testo digitato dopo la barra sparisce insieme al menu.

Si filtra sul nome ma anche sulla sintassi: `/###` trova Titolo 3 e `/---` la linea
orizzontale, per chi il Markdown lo conosce già.

Dentro una parola la barra resta una barra — `http://esempio.it` e `e/o` non aprono
niente — e dentro un blocco di codice il menu non compare affatto.

Ogni voce richiama il comando che esiste già nel menu Formato: il menu dei comandi è
un modo per raggiungerli scrivendo, non una seconda implementazione.

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

## Impostazioni

**⌘,** apre le impostazioni: carattere, dimensione del testo, interlinea,
larghezza della colonna, e se l'app segua l'aspetto di sistema o resti chiara o
scura. I cursori mostrano il valore mentre li trascini ma lo applicano solo
quando lasci il mouse: ogni cambiamento ridisegna tutti i documenti aperti, e
farlo a ogni scatto renderebbe il trascinamento a scatti sui file lunghi.

Il carattere predefinito è quello di sistema, che non è una famiglia fra le
altre: segue la dimensione ottica e le impostazioni di accessibilità. Il codice
resta monospaziato qualunque cosa si scelga, perché allinearsi in colonna è
tutto il motivo per cui è monospaziato.

## Lingua

Aurora segue la lingua di sistema e ripiega sull'inglese. Include inglese,
italiano, spagnolo, francese, tedesco, portoghese brasiliano, giapponese e
cinese semplificato.

Le traduzioni stanno in una tabella sola, `Scripts/make_strings.py`, invece che
sparse in otto file: aggiungere una frase significa aggiungere una riga per
lingua, e una lingua che la dimentica viene colta da `Scripts/check_strings.py`,
che l'integrazione continua esegue a ogni push. La chiave è la frase inglese
stessa, così una voce non ancora tradotta compare in inglese invece di mostrare
un nome interno.

## Com'è fatto

```
Sources/AuroraCore/
  MarkdownParser.swift     analisi di blocchi e elementi inline (solo indici, nessuna copia)
  MarkdownEditing.swift    modifiche al testo che sono pura aritmetica di indici

Sources/Aurora/
  main.swift               avvio dell'applicazione
  AppDelegate.swift        menu e ciclo di vita
  Localization.swift       una sola ricerca, chiavi in inglese
  Settings.swift           preferenze, e l'unico punto in cui il tema viene costruito
  SettingsWindowController.swift  la finestra Impostazioni
  MarkdownDocument.swift   NSDocument: lettura e scrittura UTF-8
  EditorViewController.swift  area di scrittura, colonna centrata, scorrimento
  MarkdownTextView.swift   NSTextView: glifi nascosti, decorazioni, comandi di editing
  MarkdownStyler.swift     dal risultato dell'analisi agli attributi del testo
  SlashMenu.swift          il menu dei comandi che si apre con "/"
  TableLayout.swift        celle, colonne e allineamenti delle tabelle
  Workspace.swift          cartella di lavoro e stato dell'albero, su UserDefaults
  WorkspaceBrowser.swift   pulsante in barra del titolo e albero dei file
  Theme.swift              font, colori chiari/scuri, metriche

Sources/AuroraCheck/       le prove (vedi sotto)
```

`AuroraCore` è un modulo a sé e importa solo Foundation. Il confine non è
burocrazia: è il modo in cui il compilatore tiene fede a quello che il parser
promette — leggere il testo, restituire indici, non sapere nulla di font, colori
o viste. È anche ciò che lo rende verificabile da solo.

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

Le decorazioni disegnate — il riquadro del codice, la barra delle citazioni, la
linea orizzontale, i segni di elenco — non chiedono mai al layout dove stia il glifo
di un carattere. Non si può: i caratteri nascosti hanno glifo nullo, e il layout li
attribuisce al frammento della riga *precedente*, per cui ogni decorazione finirebbe
una riga più su. Si enumerano invece i frammenti di riga inquadrati e si tengono
quelli che **cominciano** dentro l'intervallo decorato: il frammento della riga giusta
comincia sempre lì dentro, al più contenendo solo il proprio a-capo.

Le tabelle sono l'unico posto dove il disegno interviene sulla spaziatura del testo.
TextKit sa impaginare tabelle vere, ma vuole una cella per paragrafo, mentre qui una
riga intera è un paragrafo solo. Le colonne si ottengono allora misurando le celle e
allargando con la crenatura il carattere che precede ciascuna, così che cada al suo
posto; le barre verticali restano nel testo ma diventano trasparenti, e riappaiono in
grigio quando il cursore è sulla riga. La riga dei trattini si nasconde come qualunque
altro marcatore e al suo posto viene disegnato il filetto dell'intestazione. Il file su
disco non cambia di un byte.

C'è poi una regola che tiene fermo il testo mentre lo scrivi: **la geometria verticale
di una riga non dipende dal cursore, e nessun tipo di riga aggiunge spazio sopra o
sotto di sé**. La separazione la danno le righe vuote — che in Markdown sono anche il
modo in cui la separazione è scritta nel file. Senza questo vincolo il testo scappa da
sotto le dita: lo spazio nascerebbe nell'istante in cui la riga cambia natura, cioè
mentre ci stai ancora scrivendo dentro. Per questo `paragraphStyle` non riceve lo stato
di selezione: il vincolo lo fa rispettare il compilatore, non la memoria di chi tocca
il file. Resta il solo scarto del corpo più grande di un titolo, due punti.

## Prove

```bash
swift run AuroraCheck
```

Le prove sono un eseguibile invece che un target di test perché XCTest e
swift-testing arrivano con Xcode, mentre per compilare Aurora bastano i Command
Line Tools: legarle a Xcode significherebbe che sulla macchina di chi sviluppa
l'app non girano. Coprono il parser — titoli, elenchi, caselle, citazioni,
recinti, tabelle, estremi del documento — e l'aritmetica di indici dietro ai
comandi di modifica.

## Limiti attuali

- Le immagini `![](…)` sono mostrate come collegamento, non incorporate.
- I blocchi di codice indentati di quattro spazi non sono riconosciuti come tali
  (servono i delimitatori ` ``` `), per non alterare gli elenchi annidati.
- Nessuna evidenziazione della sintassi dentro i blocchi di codice.
- Titoli in stile setext (sottolineati con `===`) non riconosciuti.
- Aprire un recinto ` ``` ` senza chiuderlo rende codice tutto il resto del documento,
  come vuole il Markdown: il testo sotto si riorganizza finché non lo chiudi.

## Difetti noti

- **⌘` , ⇧⌘' e ⇧⌘- non rispondono** con tastiere non statunitensi. I comandi
  funzionano dal menu Formato.
- Le tabelle non hanno righe di separazione fra le celle, solo il filetto sotto
  l'intestazione: le colonne si leggono dall'allineamento.

## Contribuire

Vedi [CONTRIBUTING.md](CONTRIBUTING.md). Segnalazioni e pull request sono
benvenute; i [modelli di issue](.github/ISSUE_TEMPLATE) chiedono le poche cose
che di solito contano davvero.

## Licenza

[MIT](LICENSE) © 2026 Simone Billeri.
