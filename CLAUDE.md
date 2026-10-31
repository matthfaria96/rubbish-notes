# Rubbish Notes — read this first

Plain-text notes app for macOS (SwiftUI + AppKit, Swift Package, no Xcode project).
This file is the state of the project, so a new session doesn't have to read the
whole codebase. Keep it current when something here changes.

Last updated 2026-10-31. Version **1.1.2** (build 7) is the current GitHub
release. Build 8 (library backup .zip, Open Files for outside .txt/.md) is
installed locally for testing, not released. The project lives on the external disk
(`/Volumes/MacMiniDev/Moved/VSCode Temp/Rubbish Notes`; `~/Documents/VSCode Temp`
is a symlink to it).

## Where things stand

- **Feature-complete.** The owner is now testing. Fix what they report, keep it
  light and fluid; don't add features or redesign unless asked.
- **Don't publish** (tag, GitHub release, site) unless the owner asks in that
  message. Otherwise: build, install to /Applications, commit locally.
- When a new release is published, delete the older GitHub releases and their
  tags (the owner wants only the latest).
- witchmymac.com (repo `~/Documents/witchmymac`) lists the app. Don't touch the
  site, except `apps.js` (`tag`, `file`) so the download link always points at
  the current release, plus bumping `?v=` on `apps.js` in `index.html`.
- The owner writes in Portuguese; answer in Portuguese.

## Build, test, install, release

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # tests need Xcode
swift test                          # 78 tests (Swift Testing), Tests/RubbishNotesTests
scripts/build-app.sh --install      # universal app → build/ and /Applications
```

- `build-app.sh` restamps the binary's SDK version with `vtool`. Without it,
  SwiftPM records sdk 15.0 and macOS 26+ runs the app without Liquid Glass.
- Version: `CFBundleShortVersionString` in `Support/Info.plist`; bump
  `CFBundleVersion` for each build handed to the owner.
- Strings: add rows to `scripts/make-strings.py` (key, en, pt, es, fr, de, it),
  then `python3 scripts/make-strings.py Support/Localizations`. The script
  refuses duplicate keys. Interpolated SwiftUI text uses keys like `%lld pt`.
- Release (only when asked):
  1. `~/Documents/witchmymac-release/make-dmg.sh "build/Rubbish Notes.app" RubbishNotes-X.Y.Z ~/Documents/witchmymac-release/dist`
  2. `git tag vX.Y.Z && git push origin master vX.Y.Z`
  3. `gh release create vX.Y.Z -R matthfaria96/rubbish-notes <dmg> --title "Rubbish Notes X.Y.Z" --notes "..."` (notes in Portuguese)
  4. delete older releases: `gh release delete vOLD -R matthfaria96/rubbish-notes --yes --cleanup-tag`
  5. site: `apps.js` tag/file, `apps.js?v=` in `index.html`, commit, push
- Build output (`.build/`, `build/`) is disposable; delete it to free space.

## In-app updates (Sparkle 2)

- Sparkle 2.10 via SwiftPM; `AppUpdater.swift` (`start()` in `applicationDidFinishLaunching`,
  `CheckForUpdatesButton` after About in the app menu and in Settings › About). Test copies
  (another bundle id) never check unless `RUBBISHNOTES_UPDATES=1`.
- Feed `https://witchmymac.com/appcast/rubbishnotes.xml` (site repo `appcast/`), key and daily
  check in `Support/Info.plist`. The full flow is `~/Documents/witchmymac-release/UPDATES.md`.
- Sandboxed: `SUEnableInstallerLauncherService` + `SUEnableDownloaderService` in Info.plist,
  the `-spks`/`-spki` mach-lookup exceptions in the entitlements, and `build-app.sh` signs
  Sparkle's `Downloader.xpc` with `Support/SparkleDownloader.entitlements` (the app itself
  stays without network access). Sparkle's MIT notice is in the Licenses sheet.
- Every release: bump `CFBundleVersion` (Sparkle compares it), sign with
  `~/Documents/witchmymac-release/sign-app.sh "build/Rubbish Notes.app"` before `make-dmg.sh`,
  then `APP_NAME="Rubbish Notes" make-appcast-item.sh <dmg> <version> <build> 15.0 <url> notes.html`
  and add the item to the appcast.

## Testing on the owner's Mac (no VM)

- Don't use the macOS 15 VM ("if it works on older versions, fine"). Target is
  Apple style on macOS 26+ with Liquid Glass; the owner runs macOS 27.
- **Never touch the owner's notes.** Test with a copy that has its own sandbox:
  copy `build/Rubbish Notes.app`, set `CFBundleIdentifier` to
  `local.rubbishnotes.check` with `plutil`, re-sign with
  `codesign --force --options runtime --entitlements Support/RubbishNotes.entitlements --sign -`.
  Its notes live in `~/Library/Containers/local.rubbishnotes.check/…`; delete
  that container and `defaults delete local.rubbishnotes.check` afterwards.
- **Quit the owner's app first** (`osascript -e 'quit app id "local.rubbishnotes.app"'`)
  and reopen it at the end. Before every click or capture, check with
  `ps -axo pid,command | grep MacOS/RubbishNotes` that only the test copy runs:
  the owner's app was once relaunched seconds after being quit. Both copies are named "Rubbish Notes", so clicks
  and captures can land on the real notes.
- Screenshots without clicks: launch with `RUBBISHNOTES_SHOWCASE` (comma list, `Showcase.swift`):
  `blocks` opens the footer blocks panel, `lightbox` the open note's first image,
  `settings=general|editor|themes|about` opens Settings on that tab. Prefs can be
  passed as launch arguments (`-RubbishNotes.editorTheme paper`,
  `-RubbishNotes.activeNoteID <uuid>`). Used for the witchmymac showcase page;
  remove `container-migration.plist` from such a copy so it never moves the
  owner's files into its container.
- Look only at the app's window: `swiftc scripts/ui-test/winid.swift -o winid`,
  then `screencapture -x -o -l$(./winid "Rubbish Notes") out.png`
  (`./winid "Rubbish Notes" Temas` picks a window by title). Never capture the
  whole screen. Captures fail while the screen is locked or the window is on
  another Space; retry after a few seconds.
- Real mouse input: `osascript -l JavaScript scripts/ui-test/jclick.js X Y`,
  `jdrag.js X1 Y1 X2 Y2 [holdSeconds]`, `jmove.js X Y`, `jscroll.js X Y ticks lines`.
  "System Events click at" goes through accessibility and can hit the wrong
  view. System Events `keystroke` drops digits (a test-tool quirk, not the app).
- Position the test window: `tell application "System Events" to tell (first
  process whose bundle identifier is "local.rubbishnotes.check")` → set
  position / size of window 1.
- **Prefer accessibility actions over real input.** Other apps (and other
  sessions) may be using the screen: `keystroke` goes to whatever app is in
  front, and the test window has been clicked and closed by someone else
  mid-test. Through System Events on that process: `set selected of row N of
  outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of
  window 1`, `click menu item "Nova Sub-nota" of menu "Arquivo" of menu bar 1`,
  `perform action "AXPress"` on a row's button, `set value of text area 1 …`
  (plain windows: `window "x.txt – Texto simples"`). Alerts and save panels
  are windows of the process too (`click button "Salvar" of splitter group 1
  of window "Salvar"`). Setting a SwiftUI TextField's value this way doesn't
  reach its binding (search can't be driven like that).
- Outside files: `open -a "<copy>.app" file.txt` (the sandbox grants access).
  The copy declares public.plain-text, so unregister it before deleting it:
  `lsregister -u "<copy>.app"`. Never press Settings › Make Default on a test
  copy: it changes the owner's default .txt app.

## How it works

Notes are real `.txt` files in the sandbox container
(`~/Library/Containers/local.rubbishnotes.app/Data/Library/Application Support/Rubbish Notes/{Notes,Archive,Trash}`),
plus `notes-index.json` (box, pin, status, order, `attachments`, footer
`blocks`, `parent` for sub-notes, `subnotesCollapsed` on parents) and
`Attachments/<note id>/` for images.

Sub-notes are ordinary .txt notes in their parent's folder, linked by id in
the index (one level deep). They are listed under the parent while both are
in the same box (`nestedIDs`, `outline(_:query:keep:)`), travel with it in
`move` (archive, trash, restore, undo) and are deleted with it from the
Trash after a confirmation (`requestDeletePermanently`). A missing parent
releases them (`releaseOrphans`).

Files opened from the Finder / Open With / the Dock / File › Open go through
`FileOpening`: a note's own file opens that note, other plain text (.txt, .md)
goes to **Open Files** (`OpenedFiles`), RTF/HTML are imported as before.
Dropping a file on the window still imports it as a note.

Open Files is a sidebar section above Pinned (inbox only). The file is
edited in the notes window with a plain `NSTextView` (`PlainFileEditor`):
no blocks, images, status, sub-notes, export or pin. **No autosave** (the
owner's rule: only notes save themselves): changes wait in `OpenedFiles`
(`unsaved`, kept per file while another file or a note is shown, orange dot
on the row, "Not Saved" + Save in the footer) until Save (⌘S, toolbar,
footer) or Save As (⇧⌘S: name, folder, .txt/.md format; the list then
follows the new file). Remove from List and quitting ask Save / Don't Save /
Cancel. The toolbar has Find, Save and ··· (Save, Save As, Show in Finder,
Open in Separate Window = `PlainTextDocument`, also without autosave, Copy to
My Notes, Remove from List). The list lives in
`RubbishNotes.openedFiles` with security-scoped bookmarks
(`files.bookmarks.app-scope` entitlement), so it survives relaunches. Writes
are in place (not atomic: the sandbox grants the file, not its folder) in the
encoding it was read in (BOM kept; bytes that didn't decode → read only). `NoteStore.willSelectNote` makes any note selection
(even of the open note) leave the file.

Backup (File › Export/Import Backup…, Settings › General › Backup):
one .zip with Notes/Archive/Trash, `notes-index.json`, `Attachments/`,
`Settings.plist` (`LibraryBackup.settingKeys` only) and a manifest. Import
asks Replace All (the current library moves to a new dated `Rubbish Notes (before
import …)` folder next to the notes folder, never overwritten; any failure rolls back; then `reloadFromDisk`) or Add to My Notes
(`mergeLibrary`: clashing ids get new ones, names get numbers, sub-notes
follow). `ZipReader` unzips in-process (stored/deflate, CRC, no `..`, keeps
file dates); index entries with unsafe names are dropped.

| File | Holds |
|---|---|
| `NoteStore.swift` | Notes, boxes, select/rename/move/trash (sub-notes go along), undo, file watching, index (selecting saves it 1 s later, debounced). `pinnedNotes(in:)`, `listNotes(in:)` (top-level only), `openNote(_:in:)`. |
| `NoteStore+Subnotes.swift` | Sub-notes: `newSubnote`, `subnotes(of:)`, collapse state, `outline` (rows for the lists, search included), `outlineMove` (drag maps to top-level order), `NoteListItem`. |
| `NoteStore+Files.swift` | Import (Open…, drops on the window), Save a Copy, `libraryNote(at:)` / `isInLibrary` for files opened from outside. |
| `NoteStore+Organize.swift` | Status, drag order (`reorder`, `reorderPinned`), export entry point, footer blocks API, image attachments, `ThumbnailCache`. |
| `MainView.swift` | Window: editor, footer (blocks button left, status + counts centred, images right; middle shrinks on narrow windows), corner panels, lightbox, toolbar (title, Find / Export / ··· group, (+) note block, focus bolt at the far right), layout switch, theme colours. |
| `SidebarView.swift` | Vertical list: search, pinned + list sections (rows from `outline`, sub-notes indented), drag reorder, Delete All / Empty Trash chips, `BoxSwitcher`. With `browsing:` it is the tabs layout's All Notes panel (switching boxes there doesn't move the window). `NoteContextMenu` (New Sub-note, Show/Hide Sub-notes) is shared with the tabs. |
| `SubnoteViews.swift` | `SubnoteToggle` (count + chevron glass capsule on a parent), `NotesSectionHeader` with the Collapse/Expand all chip, `subnoteIndent` (indent + accent guide line). |
| `NoteStrip.swift` | Tabs layout (Settings › General › Window › Notes list): box menu, scrolling tabs (pinned first, names truncate, drag one onto another; sub-notes follow their parent with ↳, the open one stays even when hidden), All Notes panel, new note. |
| `Editor.swift` | `EditorTextView` (TextKit 1 NSTextView): plain-text paste, images to attachments, arrow cursor over the footer and panels, Esc closes find, note-block overlays and dragging. |
| `InlineBlocks.swift` | Note blocks inside the text. In the .txt: `⟦bloco⟧` / `⟦bloco recolhido⟧`, optionally `⟦bloco: Name⟧`, then the text, then `⟦/bloco⟧`. In the editor: one attachment character whose cell reserves room; `InlineBlockHost` (SwiftUI) sits on top. Header click folds; ↖↘ shows it large (`BlockLightbox`); ··· = Change Name, Copy, Export (text/PDF/Markdown), Delete (confirmed). `BlockGrip` drags in document coordinates with edge auto-scroll and an accent drop line. |
| `BlockLightbox.swift` | A note block shown large over the note (`OpenBlock`, sent by the editor with `.showBlockLarge`): edit, ··· menu (`BlockMenuItems`, shared with the inline block), Esc / shrink / click outside closes. |
| `NoteExport.swift` | Export note as PDF or text (title, text with blocks open, footer blocks; with images, a .zip) or Markdown (`# title`, the text without its note blocks, then each note block and footer block as a `##` section; images left out). Block export. `ExportMenu`. |
| `SubnoteExport.swift` | Markdown of a parent with sub-notes: asks (`askIncludeSubnotes`), then one .zip with `<parent>/<parent>.md` (ending in links) and one .md per sub-note (`markdownFileNames`: sanitized, no case-insensitive repeats). |
| `PlainTextDocument.swift` | NSDocument for an outside file in its own window (Open in Separate Window): plain `NSTextView`, autosave in place 1 s after typing, original encoding kept. `PlainTextLook` (plain text view setup, font/spacing/theme) is shared with Open Files. |
| `OpenedFiles.swift` | Open Files model: list + bookmarks in UserDefaults, the active file's text, in-place saving (0.6 s), file watching. |
| `OpenedFileViews.swift` | `OpenedFileDetail` (editor + kind/counts footer, unreadable state), `OpenedFileRow`, `OpenedFileMenu`, `OpenedFileToolbar`, `PlainFileEditor`. |
| `LibraryBackup.swift` | Backup .zip export/import, Replace All / Add to My Notes. |
| `ZipReader.swift` | Minimal in-sandbox unzip (no `ditto`), `CRC32`. |
| `FileOpening.swift` | Routes files opened from outside (note / Open Files / import), File › Open panel; `DefaultTextApp` (Settings › Text Files › Make Default for .txt and .md via `NSWorkspace.setDefaultApplication`). |
| `AttachmentViews.swift` | Footer image button, empty-state hint panel, `ImageLightbox` (themed, filmstrip, never Quick Look — the owner forbade it). |
| `BlocksView.swift` | Footer blocks panel (200–520 pt tall). |
| `FloatingPanel.swift` | `footerPanel` look; `FooterPanelZones` closes panels on outside clicks and keeps the arrow cursor over them. |
| `NoteFooter.swift` | `StatusDots` (click a dot to set it; current one ringed, name beside it) and the sidebar `StatusMark`. |
| `TitleField.swift` | Click-to-rename title in the toolbar; `RenameField` (AppKit, focus reaches into the toolbar). |
| `EditorTheme.swift` | 13 themes, each a distinct colour family; a theme colours the whole window, Settings and the lightbox. |
| `WindowLook.swift` | Glass sidebar backdrop, `themedForeground`. |
| `SettingsView.swift`, `AboutView.swift` | Tabs General / Editor / Themes / About. Window: notes list layout, glass sidebar (on), see-through window (on, 95 %). Text Files: make the app the default for .txt. |
| `Compat.swift` | Glass helpers with macOS 15 fallbacks; `FooterMetrics` (corner buttons 64×32, footer height 32). |
| `RubbishNotesApp.swift` | App, menus (New Sub-note ⌥⌘N, View › Collapse/Expand All Sub-notes; Save/Save a Copy/Print go to a plain window first), `AppDelegate` (opened files, notes window kept closed on file launches, Dock reopen), `Prefs` keys, notifications, `TextFinder`. |

## Things learned the hard way

- Serialize the editor text by attribute runs; going character by character
  splits emoji.
- SwiftUI text editors and gestures hosted inside the note's NSTextView don't
  get the mouse: block text areas and the drag handle are AppKit views, and
  `EditorTextView.hitTest` routes clicks to block overlays.
- Toolbar menus drop item icons unless each item has `.labelStyle(.titleAndIcon)`.
- A method named `open` on `NoteStore` clashes with Darwin's `open()` (file watching).
- Popovers can flip downward; footer panels are drawn in the note area instead.
- Under SwiftUI, `NSAppleEventManager.currentAppleEvent` is nil in
  `applicationWillFinishLaunching`; tell a file launch by
  `launchIsDefaultUserInfoKey` in `applicationDidFinishLaunching` (the open
  event arrives before it).
- `Info.plist` declares the document type without `NSDocumentClass`, so AppKit
  never opens untitled documents; `PlainTextDocument` overrides
  `readableTypes`/`writableTypes` instead.
- Text changes that skip the undo manager (accessibility, services) don't mark
  an NSDocument edited; the plain window calls `updateChangeCount` itself.
- Toolbar/menu labels picked with `cond ? "A" : "B"` must go through `L()`:
  the ternary makes a `String`, which SwiftUI doesn't translate.
