# Rubbish Notes — handoff

Read this first in a new session. Last updated 2026-10-20, version **0.8.0** (installed locally, not published).

## State

- **Feature-complete.** The owner is now only testing. Don't add features or
  redesign unless asked; fix what they report.
- **Don't publish** (tag, GitHub release, site) unless the owner asks in that
  message. Install locally and commit locally.
- Only one release exists on GitHub: the latest (v0.7.0). The owner has asked twice to
  delete old releases after publishing a new one.
- witchmymac.com (repo `~/Documents/witchmymac`) lists the app. Its download
  button reads `apps.js` (`tag`, `file`). Screenshots and copy were redone for
  0.6.0; the owner said not to touch the site again, except keeping the
  download link pointing at the current release so it never breaks.

## Build, test, install, release

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # tests need Xcode
swift test                                  # 35 tests (Swift Testing)
scripts/build-app.sh --install              # universal app into /Applications
```

- `build-app.sh` restamps the binary's SDK version with `vtool`. Without it,
  SwiftPM records sdk 15.0 and macOS 26+ runs the app in its old look, with no
  Liquid Glass. Check with `vtool -show-build ".../MacOS/RubbishNotes"`.
- Version: `CFBundleShortVersionString` in `Support/Info.plist`.
- Release (only when asked):
  `~/Documents/witchmymac-release/make-dmg.sh "build/Rubbish Notes.app" RubbishNotes-X.Y.Z ~/Documents/witchmymac-release/dist`,
  then `git tag vX.Y.Z && git push origin master vX.Y.Z`, then
  `gh release create vX.Y.Z -R matthfaria96/rubbish-notes <dmg>` (notes in
  Portuguese), then update `apps.js` in the site repo and bump `?v=` in
  `index.html`.
- The old pipeline in `~/Library/Caches/witchmymac-release` was wiped by a disk
  cleanup. Only `make-dmg.sh` was rewritten, in `~/Documents/witchmymac-release`.
- Strings: add rows to `scripts/make-strings.py` (en, pt, es, fr, de, it), then
  run `python3 scripts/make-strings.py Support/Localizations`.

## How the owner wants things checked

- No more testing in the macOS 15 VM ("if it works on older versions, fine").
- Design target: Apple style on macOS 26+ with Liquid Glass. The owner's Mac
  runs macOS 27.
- Check visuals by capturing only the app's window
  (`screencapture -x -o -l <window id>`, owner name "Rubbish Notes"). Never
  capture the whole screen. Capture fails while the screen is locked.
- Real mouse clicks on the host: a JXA script posting CGEvents through
  `osascript -l JavaScript` works. "System Events click at" goes through
  accessibility and can hit the wrong view. System Events keystrokes drop digits.
- Before driving a test copy, quit the owner's app (`osascript -e 'quit app id "local.rubbishnotes.app"'`): both have the owner name "Rubbish Notes", so captures and clicks can land on their real notes. Reopen it after.
- Screenshots for the site must never show the owner's real notes. Run a copy
  of the app with another bundle id (own sandbox) and fill it with sample notes.
- The owner writes in Portuguese. Answer in Portuguese.

## Architecture (Sources/RubbishNotes)

| File | What it holds |
|---|---|
| `NoteStore.swift` | Notes are real `.txt` files in the sandbox container (`~/Library/Containers/local.rubbishnotes.app/.../Rubbish Notes/{Notes,Archive,Trash}`), plus `notes-index.json` (pins, box, status, rank, `attachments`, `blocks`). Selecting a note saves the index 1 s later (debounced) so fast clicking doesn't stall. `trashAllInbox()` backs "Delete All". |
| `NoteStore+Organize.swift` | Status (open/in progress/done), drag order, blocks API, image attachments (`Attachments/<note id>/`), `ThumbnailCache`. |
| `MainView.swift` | Window: editor, footer (blocks button left, word count centred, images pile or hint right), corner panels, lightbox, toolbar (`TitleField` + buttons), window opacity and theme colours (`WindowConfigurator`). |
| `SidebarView.swift` | Fixed search field, list (context menu starts with "Change Name", renaming in place), centred "Delete All", box switcher. No double-click or pencil button: they caused stalls. |
| `TitleField.swift` | Click-to-rename title in the toolbar (pencil icon); `RenameField` is an AppKit field, because SwiftUI focus doesn't reach into the toolbar. |
| `AttachmentViews.swift` | Image pile, `ImagesHintButton`/`ImagesHintPanel`, `ImageLightbox` (themed, filmstrip, "…" menu with Save All / Delete All). Never uses Quick Look (the owner forbade the native previewer). |
| `BlocksView.swift` | Blocks panel (200 to 520 pt tall, grows with its blocks); typing is buffered so no key is lost. |
| `FloatingPanel.swift` | `footerPanel`: the corner panels always open upward, drawn in the note area (popovers flipped down). |
| `WindowLook.swift` | Glass sidebar backdrop (behind-window blur tinted by the theme), `themedForeground`. |
| `EditorTheme.swift` | 13 themes, each a different colour family. A theme colours the whole window, the lightbox and Settings. |
| `SettingsView.swift`, `AboutView.swift` | Tabs General / Editor / Themes / About. Window section: glass sidebar (on), see-through window (on, 90 %, slider 50 to 100 %). |
| `Editor.swift` | NSTextView; the cursor is an arrow over the bottom 64 pt (footer); image-only paste goes to attachments. |
| `InlineBlocks.swift` | Note blocks inside the text (toolbar +). Saved in the .txt as `⟦bloco⟧`/`⟦bloco recolhido⟧` … `⟦/bloco⟧`; in the editor an attachment cell reserves room and `EditorTextView.layoutInlineBlocks()` lays an `InlineBlockHost` over it. Serialize by attribute runs (per-character broke emoji). Exports show them open. |
| `Compat.swift` | Glass helpers with macOS 15 fallbacks. |
