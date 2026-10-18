# Rubbish Notes

A plain-text notes app for macOS. Every note is a real `.txt` file, saved a moment after you stop typing. Paste anything and only the words arrive.

## Build

Requires macOS 26+ and the Xcode Command Line Tools (full Xcode is not needed).

```sh
scripts/build-app.sh            # builds build/Rubbish Notes.app
scripts/build-app.sh --install  # also copies it to /Applications
```

The app icon is generated from `Assets/Logo.png` by `scripts/make-icon.swift`.

## Where notes live

- Notes: `~/Library/Application Support/Rubbish Notes/Notes/*.txt`
- Pins and recency: `~/Library/Application Support/Rubbish Notes/notes-index.json`

Edits made to those files in other apps show up in Rubbish Notes. Deleted notes go to the Finder Trash.

## Design

Native macOS 26+ look: a `NavigationSplitView` with the system glass sidebar and search, a unified toolbar of SF Symbols in Liquid Glass groups, the system find bar (`NSTextFinder`), a glass capsule for word counts, `ContentUnavailableView` for empty states and a grouped `Form` for Settings. The logo's red is the only brand color (cursor and accents); everything else uses system colors, so Light, Dark and Automatic all follow Apple's palette.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘N | New note |
| ⌘O | Open a file as a note (text, Markdown, RTF, HTML) |
| ⇧⌘S | Save a copy elsewhere |
| ⌘F / ⌥⌘F | Find / find and replace in the note |
| ⌘G / ⇧⌘G | Next / previous match |
| ⌃⌘S | Show or hide the sidebar |
| ⌥⌘T | Float on top |
| ⌘= ⌘- ⌘0 | Text size |
| ⌘P | Print |
| ⌘, | Settings: appearance, font, size, spelling, ruled lines |

## Code map

| File | What it does |
| --- | --- |
| `NoteStore.swift` | Notes on disk: index, 0.6 s autosave, folder watcher, search, rename, pin, trash, import/export |
| `Editor.swift` | Plain-text `NSTextView`: system find bar, optional ruled lines, paste without formatting |
| `MainView.swift` | Split view, toolbar, glass status capsule and notices |
| `SidebarView.swift` | Pinned and other notes, Notes-style dates, context menu, swipe actions |
| `SettingsView.swift` | General and Editor settings tabs |
| `Theme.swift` | Brand red, appearance choices, font choices |

Views use `@StateObject` with `ViewState` instead of `@State`: the `@State` macro plugin ships only with full Xcode, so `@State` fails to build with the Command Line Tools alone.
