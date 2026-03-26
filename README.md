# nice-claude-status-bar

A Claude Code status bar implemented as two POSIX shell scripts. Shows model, git branch, session duration, context usage, cost, and subscription quota — updated automatically at the bottom of your terminal.

```
◆ Sonnet 4.6  |  ⎇  main ↑2 ●  |  ⧗ 45m
▸ 42% of 200k  |  ⊛ ~$0.031
⚡ 61% 5hr (2h 14m)  ·  ⟳ 38% weekly  ·  → 17.7%/day
```

No tokens are consumed. No Claude API calls are made.

---

## Requirements

- **jq** — required. `brew install jq` (macOS) or `apt install jq` (Linux)
- **curl** — required for the subscription quota line (line 3). Pre-installed on macOS.
- **git** — optional. The git segment is silently skipped if unavailable or not in a repo.

---

## Installation

**1. Copy the scripts:**

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
    "command": "~/.claude/scripts/context-bar.sh --color"
  }
}
```

Remove `--color` if you prefer plain text (no ANSI color codes).

**3. Restart Claude Code.** The status bar appears at the bottom of your terminal.

---

## Themes

Set a color theme by creating `context-bar.conf` in the same directory as the installed script (for a standard install, `~/.claude/scripts/context-bar.conf`):

```sh
THEME=catppuccin-mocha
```

Available themes:

| Theme | Style |
|---|---|
| `teal` | Default — teal symbols, blue values |
| `amber` | Warm gold |
| `rose` | Soft rose/pink |
| `green` | Forest green |
| `purple` | Muted purple |
| `mono` | Near-white monochrome |
| `red` | Red |
| `orange` | True orange |
| `yellow` | Golden yellow |
| `cyan` | Bright cyan |
| `blue` | Cool blue |
| `pink` | Vivid pink |
| `lavender` | Soft lavender |
| `mint` | Mint green |
| `catppuccin-mocha` | Catppuccin Mocha (mauve + blue, truecolor) |
| `gruvbox` | Gruvbox (orange + yellow, truecolor) |

If the file is absent or the theme name is unrecognized, `teal` is used. Labels and separators (`of`, `5hr`, `weekly`, `|`, `·`) are always gray regardless of theme.

---

## What each line shows

### Line 1 — session identity

| Segment | Example | Description |
|---|---|---|
| `◆ Sonnet 4.6` | model name | Derived from Claude Code's stdin. "Claude " prefix stripped. |
| `⎇  main ↑2 ●` | git branch | Branch name, ahead (`↑`) / behind (`↓`) counts, dirty indicator (`●`) |
| `⧗ 45m` | session duration | Time since the first entry in the current session's JSONL file |

### Line 2 — session consumption

| Segment | Example | Description |
|---|---|---|
| `▸ 42% of 200k` | context usage | `(input + cache_creation + cache_read) / context_window_size` |
| `⊛ ~$0.031` | estimated cost | Summed from JSONL token counts using hardcoded per-model pricing |

### Line 3 — subscription quota

| Segment | Example | Description |
|---|---|---|
| `⚡ 61% 5hr (2h 14m)` | 5-hour usage | % of 5hr rolling window used; countdown to reset |
| `⟳ 38% weekly` | weekly usage | % of weekly quota used |
| `→ 17.7%/day` | daily pacing | Remaining quota divided by days until weekly reset |

Line 3 requires valid Anthropic OAuth credentials (see below). It is silently omitted if credentials are missing or the API is unreachable.

---

## Subscription quota (line 3)

Line 3 is powered by `fetch-usage.sh`, which calls the Anthropic OAuth usage API. It reads your credentials from:

- **macOS:** the system Keychain (`Claude Code-credentials` entry)
- **Linux/other:** `~/.claude/.credentials.json`

These credentials are written automatically when you log in to Claude Code, so no extra setup is needed. Results are cached for 3 minutes at `~/.cache/claude/statusline/usage.json` to avoid hammering the API.

---

## Segment behavior

Every segment is independently optional. If a segment's data is unavailable, it is silently omitted. If an entire line has no segments, that line is omitted too. The script always exits 0 and always produces valid output.

| Condition | Effect |
|---|---|
| Not in a git repo | git segment hidden |
| No upstream branch | ahead/behind counts hidden; dirty indicator still shown |
| No JSONL file for CWD | duration and cost segments hidden |
| No credentials / API error | line 3 hidden entirely |

---

## How it works

Claude Code calls `context-bar.sh` via the `statusLine` hook on every status refresh, piping a JSON blob via stdin:

```json
{
  "model": { "id": "claude-sonnet-4-6", "display_name": "Claude Sonnet 4.6" },
  "cwd": "/Users/you/project",
  "context_window": {
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 12000,
      "cache_creation_input_tokens": 50000,
      "cache_read_input_tokens": 22000
    }
  }
}
```

`context-bar.sh` then:

1. Parses model name and context stats from stdin
2. Runs `git` commands in the CWD for branch and dirty state
3. Finds the most recently modified `.jsonl` file in `~/.claude/projects/<slug>/` and reads it for session start time and token counts
4. Invokes `fetch-usage.sh` as a subprocess for subscription quota (served from cache when fresh)
5. Assembles and prints up to three lines

---

## Cost pricing

Hardcoded rates (per million tokens):

| Model | Input | Cache write | Cache read | Output |
|---|---|---|---|---|
| `sonnet-4` | $3.00 | $3.75 | $0.30 | $15.00 |
| `opus-4` | $15.00 | $18.75 | $1.50 | $75.00 |
| `haiku-4` | $0.80 | $1.00 | $0.08 | $4.00 |
| default | $3.00 | $3.75 | $0.30 | $15.00 |

Model is read per-entry from the JSONL file (not from stdin), so a session that switches models is priced correctly.

---

## Extending

Each segment is a shell function in `context-bar.sh`:

- `segment_model` — line 1, model name
- `segment_git` — line 1, branch info
- `segment_duration` — line 1, session duration
- `segment_context` — line 2, context %
- `segment_cost` — line 2, estimated cost
- `segment_subscription` — line 3, quota data

To add a segment, write a `segment_<name>` function that prints to stdout (empty output = omit), then wire it into `assemble_output`.

---

## Files

```
nice-claude-status-bar/
├── context-bar.sh     # main script — install to ~/.claude/scripts/
└── fetch-usage.sh     # subscription quota fetcher — install to ~/.claude/scripts/
```
