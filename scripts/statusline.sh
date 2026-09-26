#!/bin/bash
# Connects ClaudeBar to the Claude Code status line, or undoes it.
#
#   statusline.sh enable [ClaudeBar.app]   use ClaudeBar's helper as statusLine (your previous one keeps working)
#   statusline.sh disable                  restore the status line you had before
#
# Without an app path, the app this script is bundled in is used.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
CONFIG="$HOME/.claude/claude-bar/config.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 not found. Run: xcode-select --install" >&2; exit 1; }

case "${1:-}" in
enable)
    if [ -n "${2:-}" ]; then
        APP="$2"
    else
        APP="$(cd "$(dirname "$0")/../.." && pwd)"
    fi
    HELPER="$APP/Contents/MacOS/claude-bar-statusline"
    [ -x "$HELPER" ] || { echo "Status line helper not found: $HELPER" >&2; exit 1; }

    python3 - "$SETTINGS" "$HELPER" "$CONFIG" <<'PY'
import json, os, shutil, sys

os.umask(0o077)  # config and backups are private to the user
settings_path, command, config_path = sys.argv[1:4]
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)

current = settings.get("statusLine") or {}
config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

if current.get("command") == command:
    print("    status line already configured")
    sys.exit(0)

if "claude-bar-statusline" not in current.get("command", ""):
    if current.get("command"):
        # Keep the user's own status line: ClaudeBar records the data and prints its output instead.
        config["wrapped_command"] = current["command"]
        config["previous_statusline"] = current
        print(f"    keeping your existing status line: {current['command']}")
    else:
        config.pop("wrapped_command", None)
        config["previous_statusline"] = None

os.makedirs(os.path.dirname(config_path), exist_ok=True)
os.chmod(os.path.dirname(config_path), 0o700)
with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".bak-claudebar")
    print(f"    backup: {settings_path}.bak-claudebar")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
settings["statusLine"] = {**{k: v for k, v in current.items() if k not in ("type", "command")},
                          "type": "command", "command": command}
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("    statusLine updated in", settings_path)
PY
    ;;
disable)
    python3 - "$SETTINGS" "$CONFIG" <<'PY'
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
    ;;
*)
    sed -n '2,7p' "$0"
    exit 1
    ;;
esac
