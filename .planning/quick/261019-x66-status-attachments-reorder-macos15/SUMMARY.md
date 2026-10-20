---
quick_id: 261019-x66
status: complete
---
# Summary

- Status (Open/In Progress/Done) with glowing footer dots and a sidebar mark; also in the row context menu.
- Footer image attachments (paste, drop on text or window); thumbnails via ImageIO, cached.
- Drag reorder in the sidebar (`rank`); new notes stay on top; moving between boxes resets the rank.
- Rename button 30 pt with a circular hit area, shown on the selected row; double-click the title renames.
- Removed the row `.onDrag` that re-imported notes as copies (“question 2”…); `importFiles` ignores files already in the note folders.
- Deployment target macOS 15.0; glass behind `#available`. Verified in the macOS 15.7.7 VM (launch, status click). 31 tests pass.
