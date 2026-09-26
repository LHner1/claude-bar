#!/bin/bash
# Builds build/ClaudeBar.app from source.
#
#   ./scripts/build-app.sh                              build for this Mac
#   ./scripts/build-app.sh --arch arm64 --arch x86_64   universal build (needs Xcode)
#
# Extra arguments go to `swift build`. CLAUDEBAR_VERSION=1.2.3 sets the app version.
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer a full Xcode toolchain if one is installed but not selected.
if [ -z "${DEVELOPER_DIR:-}" ] && [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
    [ -n "$XCODE" ] && export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi

# Some Command Line Tools releases can't initialise SwiftPM's newer build system;
# fall back to the native one in that case.
FLAGS=(-c release "$@")
if ! swift build "${FLAGS[@]}"; then
    echo "==> Retrying with the native build system"
    FLAGS+=(--build-system native)
    swift build "${FLAGS[@]}"
fi
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"

APP=build/ClaudeBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/ClaudeBar" "$BIN/claude-bar-statusline" "$APP/Contents/MacOS/"
cp scripts/statusline.sh "$APP/Contents/Resources/"
if [ -n "${CLAUDEBAR_VERSION:-}" ]; then
    VERSION="${CLAUDEBAR_VERSION#v}"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $CLAUDEBAR_VERSION" >&2; exit 1; }
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature with the hardened runtime: blocks code injection (e.g. DYLD_INSERT_LIBRARIES),
# so nothing can piggyback on the Automation permission the user grants ClaudeBar.
codesign --force --options runtime --sign - "$APP/Contents/MacOS/claude-bar-statusline"
codesign --force --options runtime --entitlements Support/ClaudeBar.entitlements --sign - "$APP"

echo "==> Built $APP"
