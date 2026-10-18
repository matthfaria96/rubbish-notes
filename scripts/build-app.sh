#!/bin/bash
# Builds "build/Rubbish Notes.app" from the Swift package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Rubbish Notes"
BUNDLE="build/$APP_NAME.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/RubbishNotes" "$BUNDLE/Contents/MacOS/RubbishNotes"
cp Support/Info.plist "$BUNDLE/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift Assets/Logo.png "$ICONSET"
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$BUNDLE"
echo "Built $BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$BUNDLE" "/Applications/"
    echo "Installed /Applications/$APP_NAME.app"
fi
