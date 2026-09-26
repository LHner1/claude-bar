# ClaudeBar

A native macOS menu bar app for [Claude Code](https://code.claude.com), styled after [Stats](https://github.com/exelban/stats).
See at a glance whether a session is waiting for you, how much of your plan's limits you have used, and how many tokens you burn.

```
 ▣▣▣  5H    7D        ← one traffic light per session + limits in the menu bar
      38%   12%
```

## Features

- **A traffic light per session** in the menu bar (oldest session on the left, same order as in the popup):
  - 🔴 the session **needs you** (permission prompt, question …)
  - 🟡 the session is **working**, or a background shell command is still running
  - 🟢 the session is **ready** for your next prompt

  Prefer a single light? Turn off *One Traffic Light per Session* in the gear menu; each lamp then lights up when at least one session is in that state.
- **Plan limits**: 5-hour and weekly usage with reset times, plus a 24-hour history chart
- **Sessions**: every running Claude Code session with status, project, model and context usage.
  **Click a session to jump to its window**. With iTerm2 and Terminal.app it selects the exact tab.
- **Usage statistics**: tokens per hour/day and model (today, 7 days, 30 days), input/output/cache breakdown, responses and sessions
- **Status line** for Claude Code: `Opus · my-repo ⎇ main · ctx 17% · 5h 38% ↻2h52m · 7d 12%`
- Everything stays local: no network requests, no telemetry

## Requirements

- macOS 14 (Sonoma) or newer
- Claude Code with a Pro or Max plan (the limits are only reported for subscriptions)
- Xcode or the Command Line Tools (`xcode-select --install`) to build from source

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/LHner1/claude-bar/main/install.sh | bash
```

Or from a checkout:

```bash
git clone https://github.com/LHner1/claude-bar.git
cd claude-bar
./install.sh
```

The installer

1. builds the app from source and installs it to `~/Applications/ClaudeBar.app`
2. sets ClaudeBar's helper as `statusLine` in `~/.claude/settings.json` (a backup is written to `settings.json.bak-claudebar`)
3. starts the app

**Already have a status line?** It is kept. ClaudeBar records the data and then runs your previous
command with the same input, so your status line looks exactly like before.

Options: `--no-statusline` (don't touch settings), `--no-launch`.
To start ClaudeBar automatically, enable **Launch at Login** in the gear menu.

## How it works

| Data | Source |
| --- | --- |
| Session status | `~/.claude/sessions/<pid>.json`, written by Claude Code (`idle`, `busy`, `shell`, `waiting`) |
| Plan limits | the `rate_limits` field Claude Code passes to the [status line](https://code.claude.com/docs/en/statusline); the helper stores it in `~/.claude/claude-bar/` |
| Token usage | the session transcripts in `~/.claude/projects/**/*.jsonl` |
| Window focus | the session's TTY, matched against iTerm2/Terminal.app tabs via AppleScript; for other hosts (Ghostty, Warp, VS Code, JetBrains, Claude desktop …) the owning app is activated |

Limits only update while a Claude Code session is running. When none is, the popup shows the last known values and how old they are.

The first time you click a session, macOS asks whether ClaudeBar may control your terminal app. That permission is needed to select the right tab.

## Privacy & security

- **No network access.** ClaudeBar and its helper never open a connection; nothing leaves your Mac.
- **Transcripts stay unread.** From `~/.claude/projects` only the token counts, model name and timestamp of each response are used; message content is ignored and nothing derived from it is stored.
- **Private files.** Everything under `~/.claude/claude-bar/` is created with `0700`/`0600` permissions, so other users on the Mac can't read your project paths or usage.
- **Hardened runtime.** The app is signed with the hardened runtime, which blocks code injection into the process that holds the terminal Automation permission.
- **Minimal AppleScript.** Scripts only select the tab whose TTY matches a running session; they never send keystrokes or text.
- **Defensive parsing.** Session IDs, TTY names and folder paths from local files are validated before they're used in file names, scripts or `open` calls.

The installer only edits the `statusLine` key in `~/.claude/settings.json` and keeps a backup next to it.

## Uninstall

```bash
./uninstall.sh           # removes the app and restores your previous status line
./uninstall.sh --purge   # also deletes ~/.claude/claude-bar
```

## Development

```bash
./scripts/build-app.sh                                   # builds build/ClaudeBar.app
open build/ClaudeBar.app --args --show-popup             # opens the popup right after launch
```

The project is a plain Swift package with two executables: `ClaudeBar` (the app) and
`claude-bar-statusline` (the status line helper, bundled inside the app).

## Disclaimer

ClaudeBar is an unofficial community project and is not affiliated with or endorsed by Anthropic.
It reads files that Claude Code writes locally; their format is not a stable API and may change.

## License

[MIT](LICENSE)
