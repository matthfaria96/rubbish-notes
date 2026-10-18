# Rubbish Notes

A plain-text notes app for macOS. Every note is a real `.txt` file, saved a moment after you stop typing. Paste anything and only the words arrive.

## Build

Requires macOS 26+ and the Xcode Command Line Tools (full Xcode is not needed).

```sh
scripts/build-app.sh            # builds build/Rubbish Notes.app
scripts/build-app.sh --install  # also copies it to /Applications
```

Tests use Swift Testing, which needs Xcode (the Command Line Tools lack its macros). Point at Xcode without changing the system setting:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

They run against temporary folders and their own preferences, never the real notes.

The app icon is the layered macOS 26 icon `Assets/AppIcon.icon` (open it in Xcode's Icon Composer to edit): a gradient background and the origami as a glass layer, cut out of `Assets/Logo.png` with Vision by `scripts/cutout-subject.swift`. With Xcode installed, `build-app.sh` compiles it with `actool`, which gives macOS the light, dark and tinted versions; without Xcode it falls back to a flat icon rendered from `Assets/Logo.png` by `scripts/make-icon.swift`. `Assets/LogoRed.png` becomes the alternate red icon offered in Settings › General (it swaps the Dock icon and the accent color; Finder keeps the default icon, since changing it would modify the signed bundle).

## Where notes live

The app runs in the App Sandbox, so everything lives in its container, `~/Library/Containers/local.rubbishnotes.app/Data/Library/Application Support/Rubbish Notes/`:

- `Notes/` (Inbox), `Archive/` and `Trash/`: one `.txt` file per note. Moving a note between Inbox, Archive and Trash moves its file.
- `notes-index.json`: box, pinning and dates.

Notes from before the sandbox (in `~/Library/Application Support/Rubbish Notes/`) are moved into the container by macOS on the first sandboxed launch, as listed in `Support/container-migration.plist`.

New notes take their first line as their title until you rename them. Archiving, trashing and restoring can be undone with ⌘Z or the Undo button in the notice that follows.

Trashed notes can be restored until you choose Empty Trash, which deletes them permanently after a confirmation. Edits made to the files in other apps show up in Rubbish Notes, including in-place edits to the open note.

## Security

- App Sandbox (`Support/RubbishNotes.entitlements`): access to its own container, plus files you choose in Open/Save panels or drop on the window, and printing. No network access.
- Hardened runtime, ad-hoc signed by `scripts/build-app.sh`.
- Outside edits are never overwritten: if a note's file changed since the app last read or wrote it, the app keeps the other version and saves its own text as "<name> (conflict).txt".
- Imports: plain text, Markdown, RTF and HTML only, up to 20 MB. File names are cleaned of path separators, control and direction-override characters and leading dots.

## Design

Native macOS 26+ look: a `NavigationSplitView` with the system glass sidebar and search, a unified toolbar of SF Symbols in Liquid Glass groups, the system find bar (`NSTextFinder`), a glass capsule for word counts, `ContentUnavailableView` for empty states and a grouped `Form` for Settings. The app icon's color is the only brand color (cursor and accents); everything else uses system colors, so Light, Dark and Automatic all follow Apple's palette.

## Languages

English, Portuguese, Spanish, French, German and Italian, in `Support/Localizations/<lang>.lproj/Localizable.strings`, generated from one table by `python3 scripts/make-strings.py Support/Localizations`. By default the app follows the Mac's language; Settings › General › Language overrides it for this app and offers to restart, since macOS applies an app's language at launch. The welcome note is written in the app's language.

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
| `Localization.swift` | `L()` lookups and the in-app language choice |
| `Theme.swift` | Icon styles and accent, appearance choices, font choices |
| `EditorTheme.swift` | Editor color themes and the theme preview |

Views use `@StateObject` with `ViewState` instead of `@State`: the `@State` macro plugin ships only with full Xcode, so `@State` fails to build with the Command Line Tools alone.
