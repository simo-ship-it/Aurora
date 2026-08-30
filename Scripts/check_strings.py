#!/usr/bin/env python3
"""Verifica che ogni testo mostrato dall'app abbia una chiave tradotta.

Serve in integrazione continua: una voce di menu aggiunta senza traduzione
compila e funziona — mostra l'inglese — e per questo passerebbe inosservata
finche' qualcuno non apre l'app in un'altra lingua.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def keys_in_code():
    keys = {"Heading %d"}          # il menu Formato numera i titoli con String(format:)
    for path in (ROOT / "Sources" / "Aurora").glob("*.swift"):
        source = path.read_text()
        keys |= set(re.findall(r'localized\("((?:[^"\\]|\\.)*)"\)', source))
        # SlashCommand traduce il titolo dentro il proprio init
        keys |= set(re.findall(r'SlashCommand\("((?:[^"\\]|\\.)*)"', source))
    return keys


def keys_in_strings(path):
    return set(re.findall(r'^"((?:[^"\\]|\\.)*)" =', path.read_text(encoding="utf-8"), re.M))


def main():
    used = keys_in_code()
    problems = []

    english = ROOT / "Resources" / "en.lproj" / "Localizable.strings"
    if not english.exists():
        print("Manca %s: esegui Scripts/make_strings.py" % english, file=sys.stderr)
        return 1

    base = keys_in_strings(english)
    for key in sorted(used - base):
        problems.append("nessuna traduzione per %r (aggiungila a Scripts/make_strings.py)" % key)
    for key in sorted(base - used):
        problems.append("%r è tradotta ma non più usata nel codice" % key)

    # Ogni lingua deve coprire esattamente le stesse chiavi dell'inglese.
    for folder in sorted((ROOT / "Resources").glob("*.lproj")):
        keys = keys_in_strings(folder / "Localizable.strings")
        for key in sorted(base - keys):
            problems.append("%s: manca %r" % (folder.name, key))

    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("Localizzazione a posto: %d voci in %d lingue."
          % (len(base), len(list((ROOT / "Resources").glob("*.lproj")))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
