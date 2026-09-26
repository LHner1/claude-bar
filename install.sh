#!/bin/bash
# ClaudeBar installer
#
#   ./install.sh                 build from this checkout and install
#   curl -fsSL https://raw.githubusercontent.com/LHner1/claude-bar/main/install.sh | bash
#
# Options:
#   --no-statusline   don't touch ~/.claude/settings.json
#   --no-launch       don't start the app after installing
set -euo pipefail

REPO_URL="${CLAUDEBAR_REPO:-https://github.com/LHner1/claude-bar.git}"
APP_DIR="${CLAUDEBAR_APP_DIR:-$HOME/Applications}"
CONFIGURE_STATUSLINE=1
LAUNCH=1

for arg in "$@"; do
    case "$arg" in
        --no-statusline) CONFIGURE_STATUSLINE=0 ;;
        --no-launch) LAUNCH=0 ;;
        -h|--help) sed -n '2,11p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Requirements ------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || fail "ClaudeBar only runs on macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 14 ] || fail "macOS 14 (Sonoma) or newer is required."
command -v swift >/dev/null 2>&1 || fail "Swift toolchain not found. Install Xcode or run: xcode-select --install"
command -v python3 >/dev/null 2>&1 || fail "python3 not found. Run: xcode-select --install"

# --- Source ------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/Package.swift" ] && [ -f "$SCRIPT_DIR/scripts/build-app.sh" ]; then
    SRC="$SCRIPT_DIR"
else
    command -v git >/dev/null 2>&1 || fail "git not found. Run: xcode-select --install"
    SRC="$(mktemp -d)/claude-bar"
    trap 'rm -rf "$(dirname "$SRC")"' EXIT
    info "Cloning $REPO_URL"
    git clone --depth 1 "$REPO_URL" "$SRC"
fi

# --- Build & install ---------------------------------------------------------

info "Building ClaudeBar (this takes a minute the first time)"
"$SRC/scripts/build-app.sh"

DEST="$APP_DIR/ClaudeBar.app"
mkdir -p "$APP_DIR"
if pgrep -x ClaudeBar >/dev/null 2>&1; then
    info "Stopping running ClaudeBar"
    pkill -x ClaudeBar || true
    sleep 1
fi
rm -rf "$DEST"
cp -R "$SRC/build/ClaudeBar.app" "$DEST"
info "Installed $DEST"

# --- Claude Code status line -------------------------------------------------

if [ "$CONFIGURE_STATUSLINE" = 1 ]; then
    info "Configuring the Claude Code status line"
    "$DEST/Contents/Resources/statusline.sh" enable
fi

if [ "$LAUNCH" = 1 ]; then
    open "$DEST"
    info "ClaudeBar is running – look for the traffic light in your menu bar."
fi
