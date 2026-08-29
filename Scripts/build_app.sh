#!/bin/bash
# Compila Aurora e assembla il bundle Aurora.app (non serve Xcode, bastano i Command Line Tools).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Aurora"
APP="$ROOT/Aurora.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aurora"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Firma ad-hoc: necessaria su Apple silicon perché il sistema esegua il bundle.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "Attenzione: firma ad-hoc non riuscita"

echo "Creato $APP"
