# nice-claude-status-bar

A Claude Code status bar that shows model, git branch, session duration, context usage, cost, and subscription quota — updated automatically at the bottom of your terminal.

```
◆ Sonnet 4.6  |  ⎇  main ↑2 ●  |  ⧗ 45m
▸ 42% of 200k  |  ⊛ ~$0.031
⚡ 61% 5hr (2h 14m)  ·  ⟳ 38% weekly  ·  → 17.7%/day
```

## Requirements

- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `curl` — pre-installed on macOS; needed for subscription quota line
- `git` — optional; git segment hidden when not in a repo

## Installation

**1. Copy the scripts to `~/.claude/scripts/`:**

```bash
mkdir -p ~/.claude/scripts
cp context-bar.sh fetch-usage.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/context-bar.sh ~/.claude/scripts/fetch-usage.sh
```

**2. Add to `~/.claude/settings.json`:**

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh"
  }
}
```

For colors, use:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh --color"
  }
}
```

**3. Restart Claude Code.** The status bar appears at the bottom of your terminal.

## What each line shows

| Line | Segments | Source |
|---|---|---|
| 1 | Model name, git branch + dirty indicator, session duration | Claude Code stdin + JSONL |
| 2 | Context window usage %, estimated session cost | Claude Code stdin + JSONL |
| 3 | 5hr subscription usage + reset countdown, weekly usage, daily pacing | Anthropic OAuth API |

Segments are silently omitted if data is unavailable (not in a git repo, no credentials, etc.).

## How it works

Claude Code calls `context-bar.sh` via the `statusLine` hook and pipes a JSON blob via stdin. This JSON contains the model, CWD, and context window stats. The script:

1. Parses model name and context data from stdin
2. Runs `git` commands in the CWD for branch info
3. Reads `~/.claude/projects/<slug>/*.jsonl` for session token counts and timestamps
4. Calls `fetch-usage.sh` (cached for 3 minutes) for subscription quota
5. Prints up to three lines

No Claude API calls are made. No tokens are consumed.

## Extending display fields

Each segment is a shell function in `context-bar.sh`:

- `segment_model` — line 1, model name
- `segment_git` — line 1, branch info
- `segment_duration` — line 1, session duration
- `segment_context` — line 2, context %
- `segment_cost` — line 2, estimated cost
- `segment_subscription` — line 3, quota data

To add a new field, write a new `segment_<name>` function that prints to stdout (empty string = omit). Then add it to the `assemble_output` function in the appropriate line.

To add new data sources, edit `fetch-usage.sh` (for API data) or read additional fields from stdin or the JSONL in a new segment function.

## Forked reference

The `forked/` directory contains the original implementation this was built from, preserved unchanged for reference.
