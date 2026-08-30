# Distribuzione

## Homebrew

Aurora è un'app con interfaccia, quindi si distribuisce come **cask**, non come
formula.

Il repository ufficiale `homebrew-cask` accetta solo progetti già noti — almeno
75 stelle, oppure 30 fork, oppure 30 watcher. Un progetto appena pubblicato
viene rifiutato, e non è un giudizio sul software: serve a tenere fuori i
pacchetti che nessuno manterrà. Fino ad allora la strada è un tap proprio.

### Creare il tap (una volta sola)

Un tap è un normale repository GitHub il cui nome comincia per `homebrew-`:

```bash
gh repo create simo-ship-it/homebrew-aurora --public \
  --description "Homebrew tap for Aurora"
git clone https://github.com/simo-ship-it/homebrew-aurora
mkdir -p homebrew-aurora/Casks
```

### A ogni rilascio

Dopo che il workflow `Release` ha pubblicato l'archivio:

```bash
./Scripts/make_cask.sh 0.1.0
cp packaging/homebrew/aurora.rb ../homebrew-aurora/Casks/aurora.rb
cd ../homebrew-aurora && git commit -am "Aurora 0.1.0" && git push
```

Da quel momento:

```bash
brew install --cask simo-ship-it/aurora/aurora
```

### Prima di annunciarlo

```bash
brew audit --cask --online simo-ship-it/aurora/aurora
brew install --cask simo-ship-it/aurora/aurora
brew uninstall --cask aurora
```

`brew audit` è severo su cose che si notano solo dopo: la descrizione non deve
cominciare con "A" o con il nome dell'app, la `livecheck` deve funzionare, i
percorsi di `zap` devono esistere davvero.

## Firma e notarizzazione

Finché l'app non è firmata con un **Developer ID**, chi la scarica trova un
messaggio che dice che è danneggiata — non che è di uno sviluppatore
sconosciuto: proprio danneggiata. È il singolo ostacolo che perde più utenti, e
non si aggira con una nota nel README.

Serve l'iscrizione all'Apple Developer Program (99 $ l'anno). Poi, nelle
impostazioni del repository, questi segreti:

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

Il workflow di rilascio salta firma e notarizzazione se i segreti non ci sono:
pubblica lo stesso, con un avviso nelle note. Nessuno dei due passaggi va
aggiunto a mano.
