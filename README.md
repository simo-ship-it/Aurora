# Aurora

[![CI](https://github.com/simo-ship-it/Aurora/actions/workflows/ci.yml/badge.svg)](https://github.com/simo-ship-it/Aurora/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native Markdown editor for macOS, written in Swift and AppKit. Like Typora, it
shows text already formatted **as you write it**: there is no separate preview
pane, just one writing surface where Markdown markers hide when the cursor
leaves the line and come back the moment you return to it.

The file on disk stays plain Markdown: no proprietary format, no conversion.

*[Leggimi in italiano](README.it.md)*

<!-- TODO: add a screenshot or a short GIF here — for an editor that sells
     itself on how text looks while you type, the feature table is not enough. -->

## Install

```bash
brew install simo-ship-it/aurora/aurora
```

That is a formula, not a cask: it fetches the source and builds Aurora on your
own machine, which takes about a minute and needs only Xcode's Command Line
Tools. The reason is Gatekeeper. Aurora is not signed with an Apple Developer
ID — that requires a paid membership — so a *downloaded* copy would be
quarantined and refused at first launch. Something compiled locally never is.

A `.zip` is attached to every [release](https://github.com/simo-ship-it/Aurora/releases)
as well. If you use it, macOS will block the app until you clear the quarantine
flag yourself:

```bash
xattr -dr com.apple.quarantine /Applications/Aurora.app
```

Requires macOS 13 or later.

## Build from source

Only Xcode's Command Line Tools are needed — not the full Xcode.

```bash
./Scripts/build_app.sh
```

The script compiles with SwiftPM and assembles `Aurora.app` in the project
folder. Then just open it:

```bash
open Aurora.app Esempio.md
```

For everyday development `swift build` alone is convenient too, but opening
files from Finder and the document menus only work when running the `.app`
bundle.

## What it supports

| Element | Rendering |
| --- | --- |
| Headings `#` … `######` | Six levels, each with its own size |
| `**bold**`, `*italic*`, `***both***` | Real font, markers hidden |
| `~~strikethrough~~`, `==highlight==` | Struck through, yellow background |
| `` `inline code` `` | Monospaced with a background |
| ` ``` ` and `~~~` blocks | Grey surface, delimiter lines hidden |
| Blockquotes `>` (nested too) | Side bar and indent per level |
| Lists `-`, `*`, `+`, `1.`, `1)` | Drawn bullets, automatic indents |
| Task lists `- [ ]` / `- [x]` | Clickable box, completed item struck through |
| `[text](url)` and `<url>` | Coloured link, ⌘-click to open |
| `---`, `***`, `___` | Drawn horizontal rule |
| Tables `\| a \| b \|` | Aligned columns, bold header, `:---:` alignments |

## Writing

- **Return** continues the list, the numbering or the blockquote of the current
  line; on an empty item it leaves the list.
- **Tab** and **⇧Tab** both increase the indent of list items. To decrease it
  you remove the spaces by hand: that is a choice, not an oversight.
- **⌘B**, **⌘I**, **⇧⌘X**, **⇧⌘H** apply and remove bold, italic,
  strikethrough and highlight.
- **⌘1 … ⌘6** set the heading level, **⌘0** returns to paragraph.
- **⇧⌘U** bulleted list, **⇧⌘T** task list, **⌥⌘K** code block, **⌘K** link.
- **/** opens the command menu (see below).
- **⌘F** searches the document, using the system find bar.
- Clicking a `[ ]` box ticks it; **⌘-click** on a link opens it.

Inline code, blockquote and horizontal rule are reached from the **Format**
menu: their shortcuts (⌘`, ⇧⌘', ⇧⌘-) are declared on punctuation keys that sit
elsewhere on non-US layouts — Italian among them — so they do not respond.

Undo/redo, autosave, versions, recent documents and window tabs are the standard
macOS ones.

## Command menu

Typing **/** at the start of a line, or after a space, opens a list of every
formatting command: headings, lists, blockquote, code block, horizontal rule,
link, bold, italic, strikethrough, highlight, inline code. Typing on filters the
list, **↑ ↓** move through it, **Return** or a click applies, **Esc** dismisses.
Whatever you typed after the slash disappears along with the menu.

Filtering matches the name but also the syntax: `/###` finds Heading 3 and
`/---` the horizontal rule, for those who already know Markdown.

Inside a word a slash stays a slash — `http://example.com` and `and/or` open
nothing — and inside a code block the menu does not appear at all.

Every entry calls the command that already exists in the Format menu: the
command menu is a way to reach them by typing, not a second implementation.

## Working folder

The folder button in the title bar opens the tree of the folder you are working
in: subfolders expand in place, files open with one click. To pick another one,
**⌘⇧O** or a click on the folder name at the top of the panel.

A folder's children are read from disk only when it is expanded, so a deep tree
costs nothing while it stays closed. The chosen folder and which ones are open
survive quitting the app. If you have not chosen one yet, the panel adopts the
folder of the first document you open.

It lists only `.md`, `.markdown`, `.mdown`, `.mkd`, `.mdtext` and `.txt`: it is
there to write, not to browse the disk. The first time you point it inside
Documents, Desktop or Downloads, macOS asks for permission to read them.

## Settings

**⌘,** opens Settings: typeface, text size, line spacing, column width, and
whether the app follows the system appearance or stays light or dark. The
sliders show the value while you drag them but only commit when you let go —
every change restyles every open document, and doing that on each notch of the
slider would make the drag stutter on long files.

The default typeface is the system one, which is not just one family among the
others: it follows optical sizing and the accessibility settings. Code stays
monospaced whatever you choose, because lining up in columns is the whole reason
it is monospaced.

## Language

Aurora follows the system language, and falls back to English. It ships with
English, Italian, Spanish, French, German, Brazilian Portuguese, Japanese and
Simplified Chinese.

Translations live in one table, `Scripts/make_strings.py`, rather than scattered
across eight files: adding a phrase means adding one line per language, and a
language that forgets it is caught by `Scripts/check_strings.py`, which CI runs
on every push. The key is the English sentence itself, so a string that has not
been translated yet shows up in English instead of exposing an internal name.

## How it is built

```
Sources/AuroraCore/
  MarkdownParser.swift     block and inline analysis (indices only, no copying)
  MarkdownEditing.swift    text edits that are pure index arithmetic

Sources/Aurora/
  main.swift               application startup
  AppDelegate.swift        menus and life cycle
  Localization.swift       one lookup, English keys
  Settings.swift           preferences, and the only place the theme is built
  SettingsWindowController.swift  the Settings window
  MarkdownDocument.swift   NSDocument: UTF-8 reading and writing
  EditorViewController.swift  writing area, centred column, scrolling
  MarkdownTextView.swift   NSTextView: hidden glyphs, decorations, editing commands
  MarkdownStyler.swift     from the analysis to the text attributes
  SlashMenu.swift          the command menu that opens with "/"
  TableLayout.swift        cells, columns and alignments of tables
  Workspace.swift          working folder and tree state, on UserDefaults
  WorkspaceBrowser.swift   title bar button and file tree
  Theme.swift              fonts, light/dark colours, metrics

Sources/AuroraCheck/       the tests (see below)
```

`AuroraCore` is a module of its own, and imports only Foundation. That boundary
is not bureaucracy: it is how the compiler holds the parser to what it promises —
read the text, return indices, know nothing about fonts, colours or views. It is
also what makes it testable on its own.

The delicate part is hiding the syntax without touching the text. Aurora uses
the TextKit 1 stack and, through the layout manager delegate, assigns the null
glyph to characters carrying an internal attribute: the markers stay in the
document but take up no space. When the selection enters a line, the attribute
is removed and the markers reappear in grey.

To stay fluid on large files, styling is not recomputed everywhere on every
keystroke: it updates the lines that changed, those entering or leaving the
selection, and those appearing as you scroll. The only case that needs more is
opening or closing a code fence, which changes the look of everything that
follows: the styler notices by comparing the fence state before and after the
edit.

The drawn decorations — the code surface, the quote bar, the horizontal rule,
the list markers — never ask the layout where a character's glyph is. They
cannot: hidden characters have the null glyph, and the layout attributes them to
the *previous* line's fragment, so every decoration would land one line too high.
Instead the visible line fragments are enumerated and the ones that **begin**
inside the decorated range are kept: the fragment of the right line always begins
in there, at most containing only its own line break.

Tables are the only place where drawing interferes with text spacing. TextKit
can lay out real tables, but it wants one cell per paragraph, whereas here a
whole row is a single paragraph. Columns are obtained instead by measuring the
cells and widening, with kerning, the character preceding each one, so that it
falls into place; the vertical bars stay in the text but become transparent, and
reappear in grey when the cursor is on the line. The row of dashes hides like any
other marker and the header rule is drawn in its place. The file on disk does not
change by a single byte.

Then there is a rule that keeps the text still while you write: **a line's
vertical geometry does not depend on the cursor, and no kind of line adds space
above or below itself**. Separation comes from blank lines — which in Markdown
are also how separation is written in the file. Without this constraint the text
runs out from under your fingers: the space would appear the instant the line
changes nature, that is, while you are still writing inside it. This is why
`paragraphStyle` is not given the selection state: the constraint is enforced by
the compiler, not by the memory of whoever touches the file. All that remains is
the extra body height of a heading, two points.

## Tests

```bash
swift run AuroraCheck
```

The tests are an executable rather than a test target because XCTest and
swift-testing ship with Xcode, while building Aurora needs only the Command Line
Tools: tying the tests to Xcode would mean they do not run on the machine where
the app is developed. They cover the parser — headings, lists, task boxes,
blockquotes, fences, tables, document edges — and the index arithmetic behind the
editing commands.

## Current limits

- Images `![](…)` are shown as links, not embedded.
- Code blocks indented by four spaces are not recognised as such (the fence
  delimiters are required), so as not to disturb nested lists.
- No syntax highlighting inside code blocks.
- Setext headings (underlined with `===`) are not recognised.
- Opening a ` ``` ` fence without closing it turns the rest of the document into
  code, as Markdown intends: the text below reflows until you close it.

## Known defects

- **⌘` , ⇧⌘' and ⇧⌘- do not respond** on non-US keyboards. The commands work
  from the Format menu.
- Tables have no separating lines between cells, only the rule under the header:
  the columns are read from the alignment.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and pull requests are
welcome; the [issue templates](.github/ISSUE_TEMPLATE) ask for the few things
that usually turn out to matter.

## License

[MIT](LICENSE) © 2026 Simone Billeri.
