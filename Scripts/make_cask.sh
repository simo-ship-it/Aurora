#!/bin/bash
# Aggiorna packaging/homebrew/aurora.rb sulla versione appena pubblicata.
#
#   ./Scripts/make_cask.sh 0.1.0
#
# Scarica l'archivio del rilascio e ne calcola l'impronta: Homebrew rifiuta un
# cask la cui sha256 non corrisponde al file, ed è la sola garanzia che chi
# installa riceva quello che è stato pubblicato.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Uso: $0 <versione>   (per esempio 0.1.0)" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK="$ROOT/packaging/homebrew/aurora.rb"
URL="https://github.com/simo-ship-it/Aurora/releases/download/v$VERSION/Aurora-$VERSION.zip"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Scarico $URL"
curl -fsSL --retry 3 -o "$TMP/Aurora.zip" "$URL"
SHA="$(shasum -a 256 "$TMP/Aurora.zip" | cut -d' ' -f1)"

/usr/bin/sed -i '' \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
    "$CASK"

echo "Aggiornato $CASK"
echo "  version $VERSION"
echo "  sha256  $SHA"
echo
echo "Ora copialo nel tap:"
echo "  cp $CASK ../homebrew-aurora/Casks/aurora.rb"
echo "  (cd ../homebrew-aurora && git commit -am \"Aurora $VERSION\" && git push)"
