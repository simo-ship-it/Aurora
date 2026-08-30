# Distribuzione

## Perché una formula e non un cask

Aurora ha un'interfaccia, quindi la strada naturale sarebbe un **cask**: scarica
l'archivio del rilascio, lo scompatta in Applicazioni, finito.

Il problema è la quarantena. Ogni file scaricato viene marcato da macOS, e
Gatekeeper lo blocca se l'app non è firmata con un **Developer ID** e
notarizzata da Apple. Quella firma esiste solo dentro l'Apple Developer Program,
che costa 99 $ l'anno. Con la firma ad-hoc che lo script di compilazione usa in
sua assenza il messaggio è tipicamente *"Aurora è danneggiata e non può essere
aperta"*: la formulazione peggiore possibile, perché suggerisce un download
corrotto invece di un permesso mancante. Si sblocca con

```bash
xattr -dr com.apple.quarantine /Applications/Aurora.app
```

ma è una cosa che va spiegata a ogni persona che installa.

La quarantena però riguarda i file **scaricati**, non quelli compilati sul
posto. Una formula che prende il sorgente ed esegue `Scripts/build_app.sh` sulla
macchina di chi installa aggira il problema all'origine: nessun blocco, nessun
comando da spiegare. Chi installa da Homebrew ha già i Command Line Tools, che
sono l'unica cosa che serve, e paga una quarantina di secondi di compilazione.

Se un giorno ci sarà un Developer ID, il cask torna a essere la scelta migliore
e questa cartella andrà rifatta: il workflow di rilascio sa già firmare e
notarizzare, e pubblica comunque l'archivio a ogni versione.

## Creare il tap (una volta sola)

Un tap è un normale repository GitHub il cui nome comincia per `homebrew-`:

```bash
gh repo create simo-ship-it/homebrew-aurora --public \
  --description "Homebrew tap for Aurora"
git clone https://github.com/simo-ship-it/homebrew-aurora
mkdir -p homebrew-aurora/Formula
```

## A ogni rilascio

Dopo che il workflow `Release` ha pubblicato il tag:

```bash
./Scripts/make_formula.sh 0.1.0
cp packaging/homebrew/aurora.rb ../homebrew-aurora/Formula/aurora.rb
cd ../homebrew-aurora && git commit -am "Aurora 0.1.0" && git push
```

Da quel momento:

```bash
brew install simo-ship-it/aurora/aurora
```

E per compilare direttamente da `main`, senza aspettare una versione:

```bash
brew install --HEAD simo-ship-it/aurora/aurora
```

## Prima di annunciarlo

```bash
brew audit --strict --online simo-ship-it/aurora/aurora
brew install simo-ship-it/aurora/aurora
brew test aurora
brew uninstall aurora
```

`brew audit` è severo su cose che si notano solo dopo: la descrizione non deve
cominciare con "A" o con il nome dell'app, la licenza dev'essere dichiarata, e
`url` e `sha256` devono corrispondere davvero.

Vale la pena provare l'installazione su una macchina che non sia quella di
sviluppo, o almeno con `HOMEBREW_NO_INSTALL_FROM_API=1`: una formula che compila
dipende dal toolchain di chi installa, ed è l'unico modo di accorgersi se manca
qualcosa che qui c'è per abitudine.

## Se un giorno ci sarà la firma Apple

Nelle impostazioni del repository servono questi segreti, e il workflow di
rilascio li usa da solo:

| Segreto | Cos'è |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | il certificato Developer ID esportato in `.p12`, codificato base64 |
| `MACOS_CERTIFICATE_PASSWORD` | la password scelta esportandolo |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Nome Cognome (TEAMID)` |
| `NOTARY_APPLE_ID` | l'Apple ID dello sviluppatore |
| `NOTARY_TEAM_ID` | l'identificativo del team |
| `NOTARY_PASSWORD` | una password per app, creata su appleid.apple.com |

Per il base64 del certificato:

```bash
base64 -i Certificati.p12 | pbcopy
```

Senza i segreti il workflow salta firma e notarizzazione: pubblica lo stesso, e
le note di rilascio avvisano che l'archivio va sbloccato a mano.
