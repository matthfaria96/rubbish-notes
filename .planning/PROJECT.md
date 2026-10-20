# Rubbish Notes

Plain-text notes app for macOS (SwiftUI + AppKit, Swift Package, built with `scripts/build-app.sh`). Every note is a `.txt` file; `notes-index.json` keeps box, pinning, dates, status, manual order and image attachments.

## Constraints
- Runs on macOS 15 Sequoia and newer; Liquid Glass only behind `#available(macOS 26, *)` (see `Compat.swift`).
- Builds with the Command Line Tools alone: no `@State` macro (use `ViewState`).
- App Sandbox, no network.
