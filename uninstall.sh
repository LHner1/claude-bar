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

python3 - "$HOME/.claude/settings.json" "$DATA_DIR/config.json" <<'PY'
import json, os, sys

settings_path, config_path = sys.argv[1:3]
if not os.path.exists(settings_path):
    sys.exit(0)
with open(settings_path) as f:
    settings = json.load(f)
current = settings.get("statusLine") or {}
if "claude-bar-statusline" not in current.get("command", ""):
    sys.exit(0)

previous = None
if os.path.exists(config_path):
    with open(config_path) as f:
        previous = json.load(f).get("previous_statusline")

if previous:
    settings["statusLine"] = previous
    print("Restored previous status line:", previous.get("command"))
else:
    settings.pop("statusLine", None)
    print("Removed ClaudeBar status line")
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

rm -rf "$APP_DIR/ClaudeBar.app"
echo "Removed $APP_DIR/ClaudeBar.app"

if [ "$PURGE" = 1 ]; then
    rm -rf "$DATA_DIR"
    echo "Deleted $DATA_DIR"
fi
