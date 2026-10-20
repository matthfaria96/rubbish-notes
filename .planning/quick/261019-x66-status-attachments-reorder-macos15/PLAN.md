---
quick_id: 261019-x66
status: complete
---
# Status dots, footer images, drag reorder, bigger rename, no drag-duplicate, macOS 15

1. Images pasted/dropped on a note are kept as attachments (`Attachments/<note id>/`) and shown as small thumbnails in the editor footer; they never enter the text.
2. Footer status: three glowing dots before the word count; a click cycles Open (red) → In progress (yellow) → Done (green). The sidebar shows the status dot before each title.
3. Notes can be dragged up and down in the sidebar (List `.onMove`); order defaults to creation date and is stored as `rank` once changed.
4. Rename button: larger, larger hit area, visible on the selected row; double-click the title also renames.
5. Remove the row `.onDrag` (dropping a row back on the window imported it as a duplicate note) and ignore drops of files from the app's own folder.
6. Deployment target macOS 15: glass, glass button styles and `ToolbarSpacer` behind availability checks; verify in the Sequoia VM.
