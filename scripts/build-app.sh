#!/bin/bash
# Builds "build/Rubbish Notes.app" from the Swift package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Rubbish Notes"
# Absolute: actool runs through a shared agent that resolves relative paths
# against whatever directory it was first started from.
BUNDLE="$PWD/build/$APP_NAME.app"

# Universal (Apple Silicon + Intel) when the toolchain allows it.
if swift build -c release --arch arm64 --arch x86_64; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "Universal build unavailable; building for $(uname -m) only."
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/RubbishNotes" "$BUNDLE/Contents/MacOS/RubbishNotes"
# SwiftPM records the deployment target as the SDK version, which makes newer
# macOS run the app in its old look (no Liquid Glass). Stamp the real SDK.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
if [ -n "$SDK_VERSION" ]; then
    vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace \
        -output "$BUNDLE/Contents/MacOS/RubbishNotes" "$BUNDLE/Contents/MacOS/RubbishNotes"
fi
cp Support/Info.plist "$BUNDLE/Contents/Info.plist"
# Moves notes from before the sandbox into the container on first launch.
cp Support/container-migration.plist "$BUNDLE/Contents/Resources/container-migration.plist"
# Translations: one <lang>.lproj per language.
cp -R Support/Localizations/*.lproj "$BUNDLE/Contents/Resources/"

# AppIcon is the default (blue); AppIconRed is the alternate icon offered in Settings.
make_icon() {
    local logo="$1" name="$2" backdrop="$3"
    local iconset="build/$name.iconset"
    rm -rf "$iconset"
    swift scripts/make-icon.swift "$logo" "$iconset" "$backdrop"
    iconutil -c icns "$iconset" -o "$BUNDLE/Contents/Resources/$name.icns"
}
# With Xcode, compile the layered macOS 26 icon (Assets/AppIcon.icon: glass,
# dark and tinted variants) into Assets.car plus an .icns fallback.
# Without Xcode, fall back to a flat icon rendered from the logo.
XCODE_DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -x "$XCODE_DEV/usr/bin/actool" ]]; then
    DEVELOPER_DIR="$XCODE_DEV" xcrun actool --compile "$BUNDLE/Contents/Resources" \
        --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
        --output-partial-info-plist "$PWD/build/icon-partial.plist" \
        --errors --warnings "$PWD/Assets/AppIcon.icon" >/dev/null
    echo "Icon: layered Assets/AppIcon.icon (Xcode actool)"
else
    make_icon Assets/Logo.png AppIcon 0E1118
    echo "Icon: flat fallback from Assets/Logo.png (Xcode not found)"
fi
make_icon Assets/LogoRed.png AppIconRed ED0D0D

# Ad-hoc signature with the hardened runtime (blocks DYLD_* injection and
# unsigned code) and the App Sandbox entitlements.
codesign --force --options runtime --entitlements Support/RubbishNotes.entitlements --sign - "$BUNDLE"
echo "Built $BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$BUNDLE" "/Applications/"
    echo "Installed /Applications/$APP_NAME.app"
fi
