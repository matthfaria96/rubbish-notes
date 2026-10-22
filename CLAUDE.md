# Rubbish Notes — read this first

Plain-text notes app for macOS (SwiftUI + AppKit, Swift Package, no Xcode project).
This file is the state of the project, so a new session doesn't have to read the
whole codebase. Keep it current when something here changes.

Last updated 2026-10-22. Version in `Support/Info.plist`: **0.8.0**, installed on
the owner's Mac but **not published**. The latest public release is **v0.7.0**.

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
swift test                          # 40 tests (Swift Testing), Tests/RubbishNotesTests
scripts/build-app.sh --install      # universal app → build/ and /Applications
```

- `build-app.sh` restamps the binary's SDK version with `vtool`. Without it,
  SwiftPM records sdk 15.0 and macOS 26+ runs the app without Liquid Glass.
- Version: `CFBundleShortVersionString` in `Support/Info.plist`.
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
  and reopen it at the end. Both copies are named "Rubbish Notes", so clicks
  and captures can land on the real notes.
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

## How it works

Notes are real `.txt` files in the sandbox container
(`~/Library/Containers/local.rubbishnotes.app/Data/Library/Application Support/Rubbish Notes/{Notes,Archive,Trash}`),
plus `notes-index.json` (box, pin, status, order, `attachments`, footer
`blocks`) and `Attachments/<note id>/` for images.

| File | Holds |
|---|---|
| `NoteStore.swift` | Notes, boxes, select/rename/move/trash, undo, file watching, index (selecting saves it 1 s later, debounced). `pinnedNotes(in:)`, `listNotes(in:)`, `openNote(_:in:)`. |
| `NoteStore+Organize.swift` | Status, drag order (`reorder`, `reorderPinned`), export entry point, footer blocks API, image attachments, `ThumbnailCache`. |
| `MainView.swift` | Window: editor, footer (blocks button left, status + counts centred, images right; middle shrinks on narrow windows), corner panels, lightbox, toolbar (title, Find / Export / ··· group, (+) note block, focus bolt at the far right), layout switch, theme colours. |
| `SidebarView.swift` | Vertical list: search, pinned + list sections, drag reorder, Delete All / Empty Trash chips, `BoxSwitcher`. With `browsing:` it is the tabs layout's All Notes panel (switching boxes there doesn't move the window). `NoteContextMenu` is shared with the tabs. |
| `NoteStrip.swift` | Tabs layout (Settings › General › Window › Notes list): box menu, scrolling tabs (pinned first, names truncate, drag one onto another), All Notes panel, new note. |
| `Editor.swift` | `EditorTextView` (TextKit 1 NSTextView): plain-text paste, images to attachments, arrow cursor over the footer and panels, Esc closes find, note-block overlays and dragging. |
| `InlineBlocks.swift` | Note blocks inside the text. In the .txt: `⟦bloco⟧` / `⟦bloco recolhido⟧`, optionally `⟦bloco: Name⟧`, then the text, then `⟦/bloco⟧`. In the editor: one attachment character whose cell reserves room; `InlineBlockHost` (SwiftUI) sits on top. Header click folds; ··· = Change Name, Copy, Export (text/PDF/Markdown), Delete (confirmed). `BlockGrip` drags in document coordinates with edge auto-scroll and an accent drop line. |
| `NoteExport.swift` | Export note as PDF or text (title, text with blocks open, footer blocks); with images, a .zip. Block export. `ExportMenu`. |
| `AttachmentViews.swift` | Footer image button, empty-state hint panel, `ImageLightbox` (themed, filmstrip, never Quick Look — the owner forbade it). |
| `BlocksView.swift` | Footer blocks panel (200–520 pt tall). |
| `FloatingPanel.swift` | `footerPanel` look; `FooterPanelZones` closes panels on outside clicks and keeps the arrow cursor over them. |
| `NoteFooter.swift` | `StatusDots` (click a dot to set it; current one ringed, name beside it) and the sidebar `StatusMark`. |
| `TitleField.swift` | Click-to-rename title in the toolbar; `RenameField` (AppKit, focus reaches into the toolbar). |
| `EditorTheme.swift` | 13 themes, each a distinct colour family; a theme colours the whole window, Settings and the lightbox. |
| `WindowLook.swift` | Glass sidebar backdrop, `themedForeground`. |
| `SettingsView.swift`, `AboutView.swift` | Tabs General / Editor / Themes / About. Window: notes list layout, glass sidebar (on), see-through window (on, 95 %). |
| `Compat.swift` | Glass helpers with macOS 15 fallbacks; `FooterMetrics` (corner buttons 64×32, footer height 32). |
| `RubbishNotesApp.swift` | App, menus, `Prefs` keys, notifications, `TextFinder`. |

## Things learned the hard way

- Serialize the editor text by attribute runs; going character by character
  splits emoji.
- SwiftUI text editors and gestures hosted inside the note's NSTextView don't
  get the mouse: block text areas and the drag handle are AppKit views, and
  `EditorTextView.hitTest` routes clicks to block overlays.
- Toolbar menus drop item icons unless each item has `.labelStyle(.titleAndIcon)`.
- A method named `open` on `NoteStore` clashes with Darwin's `open()` (file watching).
- Popovers can flip downward; footer panels are drawn in the note area instead.
