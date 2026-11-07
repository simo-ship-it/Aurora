# Changelog

All notable changes to Aurora are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-11-07

### Added

- **Two documents side by side**, with a draggable divider, independent saving
  and undo, and controls to separate the documents into their own windows.
- **Interactive tables** with editable cells and contextual row and column
  controls. The source remains an ordinary Markdown table.
- **Image previews**, including relative paths, and commands to insert images
  and numbered lists.
- Underline, Setext headings, indented code blocks, reference links and bare URLs.
- **Working folder actions** to create folders, rename, move, copy, duplicate
  and delete items, with undo and automatic refresh after external changes.
- Title bar shortcuts to open the working folder in Finder, Claude Cowork or
  ChatGPT.
- **Option-drag column guides** and commands to adjust text size while writing.
- AppKit regression checks for document windows, split view, saving, undo,
  relative images and cancellation of a close with unsaved changes.
- Updated English and Italian README screenshots in light mode, dark mode and
  split view, with a script to capture the real app windows.

### Changed

- Markdown markers stay hidden while editing, including on the active line.
- The editor restores the last document at launch; the working folder remains
  accessible from the title bar instead of a separate start page.
- Improved Markdown parsing, formatting commands, table layout and file change
  handling.
- Refreshed translations across all eight supported languages.

## [0.1.0] — first release

The editor itself already worked; this release is what turns it into something
installable by someone other than its author.

### Added

- **Settings window** (**⌘,**): typeface, text size, line spacing, column width
  and appearance (system, light, dark). Values persist and apply to every open
  document at once.
- **Eight languages**, chosen from the system and falling back to English:
  English, Italian, Spanish, French, German, Brazilian Portuguese, Japanese,
  Simplified Chinese.
- **Tests** for the parser and for the index arithmetic behind the editing
  commands: `swift run AuroraCheck`. They run without Xcode, like the build.
- **An app icon**, generated from code by `Scripts/make_icon.swift`.
- Continuous integration on every push, and a release workflow that builds a
  universal binary (Apple silicon and Intel), signs and notarizes it when the
  credentials are configured, and publishes it with its checksum.
- A Homebrew formula, and the instructions to serve it from a tap. It builds from
  source on the installing machine rather than shipping a binary: Aurora is not
  signed with an Apple Developer ID, so a downloaded copy would be quarantined
  and refused at first launch, while a locally compiled one never is.
- MIT licence.

### Changed

- **Bundle identifier** is now `io.github.simo-ship-it.Aurora`, on a domain that
  is actually controlled. Settings written by earlier development builds under
  `com.aurora.markdown` are not carried over.
- The parser moved into its own module, `AuroraCore`, which imports only
  Foundation. The boundary is what makes it testable, and what keeps it honest
  about knowing nothing of views.
- Aurora no longer claims ownership of every plain text file. It is the owner of
  Markdown documents and merely an alternative for `.txt`, so installing it does
  not make it the default application for every log and note on the disk.

### Fixed

- **Emphasis no longer swallows the trailing line break.** On a document ending
  with a newline, ⌘A followed by ⌘B put the closing `**` on a line of its own and
  the emphasis never closed. Whitespace at either end of the selection now stays
  outside the markers.
- **A new window opens at a usable size.** Assigning a view controller resizes
  the window to what its view asks for, and a scroll view asks for nothing, so
  the window collapsed to its own minimum. It was invisible while a saved window
  position existed — that is, to everyone except a first-time user.
