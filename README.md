# Rubbish Notes

A plain-text notes app for macOS. Every note is a real `.txt` file, saved a moment after you stop typing. Paste anything and only the words arrive.

## Build

Requires macOS 26+ and the Xcode Command Line Tools (full Xcode is not needed).

```sh
scripts/build-app.sh            # builds build/Rubbish Notes.app
scripts/build-app.sh --install  # also copies it to /Applications
```

The app icon is generated from `Assets/Logo.png` by `scripts/make-icon.swift`. `Assets/LogoRed.png` becomes the alternate red icon offered in Settings › General (it swaps the Dock icon and the accent color; Finder keeps the default icon, since changing it would modify the signed bundle).

## Where notes live

Everything lives in `~/Library/Application Support/Rubbish Notes/`:

- `Notes/` (Inbox), `Archive/` and `Trash/`: one `.txt` file per note. Moving a note between Inbox, Archive and Trash moves its file.
- `notes-index.json`: box, pinning and dates.

Trashed notes can be restored until you choose Empty Trash, which deletes them permanently after a confirmation. Edits made to the files in other apps show up in Rubbish Notes, including in-place edits to the open note.

## Design

Native macOS 26+ look: a `NavigationSplitView` with the system glass sidebar and search, a unified toolbar of SF Symbols in Liquid Glass groups, the system find bar (`NSTextFinder`), a glass capsule for word counts, `ContentUnavailableView` for empty states and a grouped `Form` for Settings. The app icon's color is the only brand color (cursor and accents); everything else uses system colors, so Light, Dark and Automatic all follow Apple's palette.

## Themes and focus

Settings › Themes previews and applies editor themes: Default (system colors) plus Dracula, Nord, One Dark, Monokai, Tokyo Night, Catppuccin Mocha and Latte, Gruvbox Dark, Rosé Pine, Solarized Dark and Light, and GitHub Light. Hovering a theme previews it; clicking applies it. While Appearance is Automatic, a dark or light theme also sets the window's look.

Focus Mode (the bolt in the toolbar, ⇧⌘F) hides the sidebar, the Inbox/Archive/Trash switch, the word count and every other toolbar button, leaving only the text and the bolt to leave focus.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘N | New note |
| ⌘O | Open a file as a note (text, Markdown, RTF, HTML) |
| ⇧⌘S | Save a copy elsewhere |
| ⌘F / ⌥⌘F | Find / find and replace in the note |
| ⌘G / ⇧⌘G | Next / previous match |
| ⌘1 ⌘2 ⌘3 | Inbox, Archive, Trash |
| ⇧⌘F | Focus Mode |
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
| `SidebarView.swift` | Notes list per box, hover rename button, context menus, swipe actions, box switcher, Empty Trash |
| `SettingsView.swift` | General (appearance, app icon), Editor and Themes tabs |
| `Theme.swift` | Icon styles and accent, appearance choices, font choices |
| `EditorTheme.swift` | Editor color themes and the theme preview |

Views use `@StateObject` with `ViewState` instead of `@State`: the `@State` macro plugin ships only with full Xcode, so `@State` fails to build with the Command Line Tools alone.
