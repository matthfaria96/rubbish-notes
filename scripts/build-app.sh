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

# AppIcon is the default (blue); AppIconRed is the alternate icon offered in Settings.
make_icon() {
    local logo="$1" name="$2" backdrop="$3"
    local iconset="build/$name.iconset"
    rm -rf "$iconset"
    swift scripts/make-icon.swift "$logo" "$iconset" "$backdrop"
    iconutil -c icns "$iconset" -o "$BUNDLE/Contents/Resources/$name.icns"
}
make_icon Assets/Logo.png AppIcon 0E1118
make_icon Assets/LogoRed.png AppIconRed ED0D0D

codesign --force --sign - "$BUNDLE"
echo "Built $BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$BUNDLE" "/Applications/"
    echo "Installed /Applications/$APP_NAME.app"
fi
