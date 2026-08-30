# Contributing to Aurora

Thanks for looking. Bug reports, translations and pull requests are all welcome.

## Getting set up

You need Xcode's Command Line Tools, not the full Xcode:

```bash
xcode-select --install
```

Then:

```bash
swift build                  # compile
swift run AuroraCheck        # run the tests
./Scripts/build_app.sh       # assemble Aurora.app
open Aurora.app Esempio.md
```

`Esempio.md` exercises most of what the editor renders; it is the quickest way
to see whether a change broke something visual.

## Before opening a pull request

```bash
swift build -c release
swift run AuroraCheck
python3 Scripts/check_strings.py
```

CI runs exactly these, plus a full bundle build. A pull request that adds
user-visible text without adding it to the translation table will fail on the
third one — that is the point of it.

## Adding or changing user-visible text

Never write a display string as a literal. Call `localized("The English
sentence")`, then add that sentence to the table in `Scripts/make_strings.py`
with a translation for every language, and regenerate:

```bash
python3 Scripts/make_strings.py
```

Commit the regenerated `Resources/*.lproj/*.strings` along with your change. If
you do not speak one of the languages, say so in the pull request and put in your
best attempt — a rough translation that someone can correct beats a language
silently falling back to English.

## Adding a language

Add its code to `LANGUAGES` in `Scripts/make_strings.py`, fill in that column for
every entry, and run the script. Nothing else needs to change: the build script
copies every `.lproj` folder it finds into the bundle.

## Where things go

The parser and anything that is pure index arithmetic belong in
`Sources/AuroraCore`, which imports only Foundation and must stay that way — the
module boundary is what keeps it testable. Everything that touches AppKit lives
in `Sources/Aurora`. Tests go in `Sources/AuroraCheck`.

If you add logic to a view that could have been written against text and indices
alone, consider moving that part into `AuroraCore` and testing it there. The
editing commands are the kind of code that produces Markdown that *looks* right
until someone reads it back.

## Style

Follow what the surrounding code already does. Two things worth knowing:

- Comments explain *why*, not what. The code says what it does.
- A line's vertical geometry must never depend on the selection. If a change
  makes a line taller or shorter depending on where the cursor is, the text will
  move under the writer's hands — see the README section on this.

## Reporting a bug

Please include your macOS version, whether you are on Apple silicon or Intel,
and the smallest piece of Markdown that reproduces the problem. For anything
about how text is laid out, a screenshot is worth more than a description.
