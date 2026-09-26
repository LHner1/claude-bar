#!/bin/bash
# Removes ClaudeBar and restores your previous Claude Code status line.
#
#   ./uninstall.sh           remove the app, keep collected data
#   ./uninstall.sh --purge   also delete ~/.claude/claude-bar
set -euo pipefail

APP_DIR="${CLAUDEBAR_APP_DIR:-$HOME/Applications}"
DATA_DIR="$HOME/.claude/claude-bar"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

pkill -x ClaudeBar 2>/dev/null || true

"$(dirname "$0")/scripts/statusline.sh" disable

rm -rf "$APP_DIR/ClaudeBar.app"
echo "Removed $APP_DIR/ClaudeBar.app"

if [ "$PURGE" = 1 ]; then
    rm -rf "$DATA_DIR"
    echo "Deleted $DATA_DIR"
fi
