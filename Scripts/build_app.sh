#!/bin/bash
# Compila Aurora e assembla il bundle Aurora.app (non serve Xcode, bastano i
# Command Line Tools).
#
#   ./Scripts/build_app.sh [debug|release]
#
# Variabili d'ambiente, tutte facoltative:
#   AURORA_SIGN_IDENTITY   nome del certificato "Developer ID Application: …".
#                          Se manca si firma ad-hoc: l'app parte su questa
#                          macchina ma Gatekeeper la blocca se scaricata.
#   AURORA_VERSION         versione da scrivere nel bundle (default: quella
#                          già in Resources/Info.plist).
#   AURORA_UNIVERSAL=1     compila per Apple silicon e Intel insieme. Serve per
#                          i rilasci: una macchina sola non basta più a definire
#                          "il Mac". Richiede Xcode completo, non solo i Command
#                          Line Tools, ed è il solo passaggio che lo richieda:
#                          per questo lo fa l'integrazione continua, non tu.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/Aurora.app"
ICONSET="$ROOT/.build/AppIcon.iconset"
ICNS="$ROOT/.build/AppIcon.icns"

# --- Icona -----------------------------------------------------------------
# Rigenerata solo se il disegno è cambiato: compilare lo script costa qualche
# secondo, e un'icona ferma non ha motivo di ripagarlo a ogni build.
if [[ ! -f "$ICNS" || "$ROOT/Scripts/make_icon.swift" -nt "$ICNS" ]]; then
    echo "Disegno l'icona…"
    mkdir -p "$ROOT/.build"
    swift "$ROOT/Scripts/make_icon.swift" "$ICONSET"
    iconutil -c icns -o "$ICNS" "$ICONSET"
fi

# --- Traduzioni ------------------------------------------------------------
python3 "$ROOT/Scripts/make_strings.py" >/dev/null

# --- Compilazione ----------------------------------------------------------
# Una stringa e non un array: bash 3.2, quello che macOS ha di serie, con
# `set -u` considera non definito un array vuoto espanso.
ARCHS=""
if [[ "${AURORA_UNIVERSAL:-}" == "1" ]]; then
    # SwiftPM delega a xcbuild per le build a più architetture, e xcbuild arriva
    # con Xcode. Si chiede a xcodebuild se risponde invece di cercare xcbuild in
    # un percorso: con Xcode installato sta dentro Xcode.app, e dov'è di preciso
    # dipende da dove Xcode è stato messo.
    if ! xcodebuild -version >/dev/null 2>&1; then
        echo "AURORA_UNIVERSAL=1 richiede Xcode completo, e qui è attivo $(xcode-select -p)." >&2
        echo "Con i soli Command Line Tools togli la variabile: la build esce per" >&2
        echo "l'architettura di questa macchina. L'universale lo fa il workflow di rilascio." >&2
        exit 1
    fi
    ARCHS="--arch arm64 --arch x86_64"
fi

swift build -c "$CONFIG" $ARCHS
BIN="$(swift build -c "$CONFIG" $ARCHS --show-bin-path)/Aurora"

# --- Bundle ----------------------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aurora"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Resources/"*.lproj "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -n "${AURORA_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $AURORA_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $AURORA_VERSION" "$APP/Contents/Info.plist"
fi

# --- Firma -----------------------------------------------------------------
# Il runtime irrigidito è un requisito della notarizzazione, non un extra: senza
# di esso Apple rifiuta il pacchetto. Con la firma ad-hoc non ha senso chiederlo.
if [[ -n "${AURORA_SIGN_IDENTITY:-}" ]]; then
    echo "Firmo con: $AURORA_SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp \
             --sign "$AURORA_SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    codesign --force --sign - "$APP" >/dev/null 2>&1 \
        || echo "Attenzione: firma ad-hoc non riuscita"
fi

echo "Creato $APP"
