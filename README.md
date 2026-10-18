# Rubbish Notes

A plain-text notes app for macOS. Every note is a real `.txt` file, saved a moment after you stop typing. Paste anything and only the words arrive.

## Build

Requires macOS 14+ and the Xcode Command Line Tools (full Xcode is not needed).

```sh
scripts/build-app.sh            # builds build/Rubbish Notes.app
scripts/build-app.sh --install  # also copies it to /Applications
```

The app icon is generated from `Assets/Logo.png` by `scripts/make-icon.swift`.

## Where notes live

- Notes: `~/Library/Application Support/Rubbish Notes/Notes/*.txt`
- Pins and recency: `~/Library/Application Support/Rubbish Notes/notes-index.json`

Edits made to those files in other apps show up in Rubbish Notes. Deleted notes go to the Finder Trash.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘N | New note |
| ⌘O | Open a file as a note (text, Markdown, RTF, HTML) |
| ⇧⌘S | Save a copy elsewhere |
| ⌘F | Find & replace (Return next, ⇧Return previous, Esc close) |
| ⌥⌘S | Show or hide the sidebar |
| ⌥⌘T | Float on top |
| ⌘= ⌘- ⌘0 | Text size |
| ⌘P | Print |
| ⌘, | Settings: theme (Paper, Dark, Black, Auto), font, size, spelling, ruled paper |

## Code map

| File | What it does |
| --- | --- |
| `NoteStore.swift` | Notes on disk: index, 0.6 s autosave, folder watcher, rename, pin, trash, import/export |
| `Editor.swift` | Plain-text `NSTextView`: ruled-paper drawing, paste without formatting, search highlights |
| `Find.swift` | Find & replace state and the floating find bar |
| `MainView.swift` | Window layout: title bar, sidebar, editor card, status bar, toasts |
| `SidebarView.swift` | Pinned and recent notes, inline rename, context menu |
| `SettingsView.swift` | Theme cards and typography settings |
| `Theme.swift` | Palettes taken from the logo, font choices |

Views use `@StateObject` with `ViewState` instead of `@State`: the `@State` macro plugin ships only with full Xcode, so `@State` fails to build with the Command Line Tools alone.
