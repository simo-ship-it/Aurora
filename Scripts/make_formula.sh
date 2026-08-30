#!/bin/bash
# Aggiorna packaging/homebrew/aurora.rb sulla versione appena pubblicata.
#
#   ./Scripts/make_formula.sh 0.1.0
#
# Scarica l'archivio del sorgente generato da GitHub per il tag e ne calcola
# l'impronta: Homebrew rifiuta una formula la cui sha256 non corrisponde, ed è
# la sola garanzia che chi compila parta davvero da quel codice.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Uso: $0 <versione>   (per esempio 0.1.0)" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMULA="$ROOT/packaging/homebrew/aurora.rb"
URL="https://github.com/simo-ship-it/Aurora/archive/refs/tags/v$VERSION.tar.gz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Scarico $URL"
curl -fsSL --retry 3 -o "$TMP/sorgente.tar.gz" "$URL"
SHA="$(shasum -a 256 "$TMP/sorgente.tar.gz" | cut -d' ' -f1)"

/usr/bin/sed -i '' \
    -e "s|^  url \".*\"$|  url \"$URL\"|" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
    "$FORMULA"

echo "Aggiornato $FORMULA"
echo "  versione $VERSION"
echo "  sha256   $SHA"
echo
echo "Ora copiala nel tap:"
echo "  cp $FORMULA ../homebrew-aurora/Formula/aurora.rb"
echo "  (cd ../homebrew-aurora && git commit -am \"Aurora $VERSION\" && git push)"
