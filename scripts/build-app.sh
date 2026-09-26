#!/bin/bash
# Builds build/ClaudeBar.app from source.
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer a full Xcode toolchain if one is installed but not selected.
if [ -z "${DEVELOPER_DIR:-}" ] && [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
    [ -n "$XCODE" ] && export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi

# Some Command Line Tools releases can't initialise SwiftPM's newer build system;
# fall back to the native one in that case.
FLAGS=(-c release)
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

# Ad-hoc signature – enough to run locally built apps.
codesign --force --sign - "$APP/Contents/MacOS/claude-bar-statusline"
codesign --force --sign - "$APP"

echo "==> Built $APP"
