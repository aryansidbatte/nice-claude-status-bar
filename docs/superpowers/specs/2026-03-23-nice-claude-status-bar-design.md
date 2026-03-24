# nice-claude-status-bar — Design Spec
_2026-03-23 (revised after spec review + design refinements)_

## Overview

A Claude Code status bar implemented as two POSIX shell scripts installed at
`~/.claude/scripts/`. Claude Code calls `context-bar.sh` via the `statusLine`
hook, which pipes a JSON blob via stdin containing live session data. The script
combines that data with a cached API call and a JSONL parse to render three
lines of information at the bottom of the terminal.

No tokens are consumed by the status bar. No Claude API calls are made.

---

## Output Format

Three lines, no trailing newline on the last line:

```
◆ Sonnet 4.6  |  ⎇  main ↑2 ●  |  ⧗ 45m
▸ 42% of 200k  |  ⊛ ~$0.031
⚡ 61% 5hr (2h 14m)  ·  ⟳ 38% weekly  ·  → 17.7%/day
```

- **Line 1** — session identity: model, git branch, session duration
- **Line 2** — session consumption: context usage, estimated cost
- **Line 3** — subscription quota: 5hr usage, weekly usage, daily pacing

Segments within a line are separated by `  |  ` (two spaces each side).
Items within the subscription line are separated by `  ·  `.
Segments that have no data are silently omitted. If an entire line has no
segments, that line is omitted too.

### Color scheme (with `--color` flag)

Three color layers:

| Layer | ANSI code | Used for |
|---|---|---|
| Teal (symbols) | `\033[38;5;66m` | Unicode symbols (`◆ ⎇ ▸ ⊛ ⚡ ⟳ →`) |
| Blue (values) | `\033[38;5;74m` | Model name, branch name, numbers, cost |
| Gray (labels) | `\033[38;5;245m` | `of`, `5hr`, `weekly`, `/day`, `\|`, `·`, `(`, `)` |

Reset: `\033[0m` after each colored token.

The `--color` flag is presence/absence only (`--color`, no argument). No ANSI
codes are emitted without the flag.

### Unicode symbols

| Symbol | Unicode | Meaning |
|---|---|---|
| `◆` | U+25C6 | Model |
| `⎇` | U+2387 | Git branch (double space before branch name) |
| `●` | U+25CF | Git dirty (uncommitted changes) |
| `⧗` | U+29D7 | Session duration |
| `▸` | U+25B8 | Context window |
| `⊛` | U+229B | Session cost |
| `⚡` | U+26A1 | 5hr subscription usage |
| `⟳` | U+27F3 | Weekly subscription usage |
| `→` | U+2192 | Daily pacing |

---

## Scripts

### `fetch-usage.sh`

Fetches Anthropic subscription throttle data from the OAuth API endpoint.

**Source:** `GET https://api.anthropic.com/api/oauth/usage`

**Required headers:**
- `Authorization: Bearer <token>`
- `anthropic-beta: oauth-2025-04-20`

**Auth:** OAuth access token read from macOS Keychain
(`security find-generic-password -s "Claude Code-credentials" -w`, then
`jq -r '.claudeAiOauth.accessToken'`) or from
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json` on non-macOS.

**Invocation contract:** `fetch-usage.sh` is invoked as a subprocess by
`context-bar.sh` (not sourced). `context-bar.sh` calls it as:
```sh
usage_data=$(~/.claude/scripts/fetch-usage.sh)
```
and reads its stdout.

**Output:** JSON on stdout:
```json
{
  "sessionUsage": 61,
  "sessionResetAt": "2026-03-23T14:00:00Z",
  "weeklyUsage": 38,
  "weeklyResetAt": "2026-03-27T00:00:00Z"
}
```
Or `{"error":"<reason>"}` on failure. Always exits 0.

**Caching:** File cache at `~/.cache/claude/statusline/usage.json`, valid for
180 seconds. Stale cache is served while a new fetch is in flight (via lock
file). Rate-limit responses (`429`) set a backoff lock using the `Retry-After`
header.

**Dependencies:** `sh`, `curl`, `jq`

**Key differences from forked version:**
- POSIX sh (no bashisms — no `[[`, no `$BASH_SOURCE`, no `OSTYPE`)
- `python3`, `bc`, and `awk` removed; all date arithmetic and decimal math done
  in `jq`

---

### `context-bar.sh`

Main entry point. Reads stdin JSON from Claude Code, assembles all segments,
prints up to three lines.

**Dependencies:** `sh`, `jq` (required), `curl` (required for subscription
segment), `git` (optional — git segment skipped if unavailable or not in a repo)

#### Stdin JSON shape (provided by Claude Code)

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

#### Segment: Model (line 1)

Transform `display_name` → remove `"Claude "` prefix → `"Sonnet 4.6"`.

Fallback (if `display_name` is null/empty): transform `model.id` using these
exact steps:
1. Strip leading `claude-` prefix
2. Split on `-` into words
3. Title-case the first word (model family)
4. Join remaining words (version numbers) with `.` instead of `-`
5. Result: `claude-sonnet-4-6` → `sonnet` + `4-6` → `Sonnet` + `4.6` → `Sonnet 4.6`

In `jq`: `(.model.id | ltrimstr("claude-") | split("-") | .[0] |= (.[0:1] | ascii_upcase) + .[1:] | .[0] + " " + (.[1:] | join(".")))`

If both `display_name` and `model.id` are null or empty, skip the model segment.

Display: `◆ Sonnet 4.6`

#### Segment: Git (line 1)

- Run `git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null` for branch name
- Run `git -C "$cwd" rev-list --count --left-right @{upstream}...HEAD 2>/dev/null`
  for ahead/behind counts (output format: `<behind>\t<ahead>`)
- Run `git -C "$cwd" status --porcelain 2>/dev/null` — if output is non-empty,
  the working tree is dirty; append ` ●` after the ahead/behind display
- Branch + ahead/behind display:
  - `⎇  main` — synced, clean
  - `⎇  main ●` — synced, dirty
  - `⎇  main ↑2 ●` — ahead, dirty
  - `⎇  main ↓1` — behind, clean
  - `⎇  main ↑2 ↓1 ●` — both, dirty
- Note: two spaces between `⎇` and the branch name to visually separate the
  symbol from the text
- Skip entire segment silently if: `cwd` is empty, not a git repo, `git` not
  installed, no upstream configured (ahead/behind omitted; dirty indicator still
  shown if applicable), or branch name command exits non-zero

#### Segment: Session Duration (line 1)

- Find the most recently modified `.jsonl` file in
  `~/.claude/projects/<slug>/` (same slug derivation as cost segment)
- Read the `timestamp` field of the first entry in the file (earliest line)
- `duration = now - first_timestamp`
- Format: `45m` if under 1 hour; `1h 12m` if 1 hour or more (always show both
  parts when hours > 0, e.g. `2h 0m` not `2h`)
- Skip silently if JSONL not found or timestamp not parseable

Display: `⧗ 45m`

#### Segment: Context (line 2)

- Default `context_window_size` to `200000` if the field is null, missing, or zero
- `tokens_used = input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
  (treat any missing field as 0)
- `context_k = context_window_size / 1000` — integer division, no decimals,
  append `k` (e.g. `200000 → 200k`, `128000 → 128k`)
- `pct = tokens_used * 100 / context_window_size` — integer division
- Display: `▸ 42% of 200k`

#### Segment: Session Cost (line 2)

**Finding the JSONL file:**
- Derive project slug from `cwd` by replacing every `/` with `-`
  (e.g. `/Users/you/project` → `-Users-you-project`)
- Note: slug derivation is not collision-free — two different paths can produce
  the same slug. This is a known limitation inherited from Claude Code's own
  storage format. Use the most recently modified `.jsonl` file in
  `~/.claude/projects/<slug>/` as the current session file; do not attempt
  exact matching.
- Skip silently if the directory does not exist or contains no `.jsonl` files

**Deduplication rule:**
Claude Code writes two assistant entries per turn for some turns: an early
streaming entry with `output_tokens: 0` followed by a final entry with the
actual `output_tokens`. Skip any `assistant` entry where
`message.usage.output_tokens == 0`. Only count entries where `output_tokens > 0`.

**Cost calculation:**
Sum across all `assistant` entries in the file where `output_tokens > 0`:
- `input_tokens * input_rate`
- `cache_creation_input_tokens * cache_write_rate`
- `cache_read_input_tokens * cache_read_rate`
- `output_tokens * output_rate`

Pricing (per million tokens, hardcoded):

| Model match (from `message.model`) | Input | Cache write | Cache read | Output |
|---|---|---|---|---|
| contains `sonnet-4` | $3.00 | $3.75 | $0.30 | $15.00 |
| contains `opus-4` | $15.00 | $18.75 | $1.50 | $75.00 |
| contains `haiku-4` | $0.80 | $1.00 | $0.08 | $4.00 |
| default (no match) | $3.00 | $3.75 | $0.30 | $15.00 |

Use the model from `message.model` field of each JSONL entry (not the stdin
model), since a session could theoretically switch models.

**Cost formatting** — jq's `tostring` drops trailing zeros, so use string-padding:
```jq
($cost * 1000 | round) as $m |
($m / 1000 | tostring) as $s |
"~$" + if ($s | test("\\.")) then
  $s + "0" * (3 - ($s | split(".")[1] | length))
else
  $s + ".000"
end
```

Skip silently if the raw summed cost is zero (i.e., no billable tokens found).
Do not skip if the cost is non-zero but rounds to `$0.000` — show `⊛ ~$0.000`.

Display: `⊛ ~$0.031`

#### Segment: Subscription Usage (line 3)

- Invoke `~/.claude/scripts/fetch-usage.sh` as subprocess; read stdout
- Skip entire segment silently if output is empty, contains `"error"` key, or
  subprocess fails
- Parse `sessionUsage` (5hr %) and `sessionResetAt` (reset timestamp)
- Parse `weeklyUsage` (7-day %) and `weeklyResetAt` (weekly reset timestamp)
- **Date arithmetic:** Use `jq`'s `fromdate` builtin. This only handles UTC
  ISO 8601 strings in the exact format `"YYYY-MM-DDTHH:MM:SSZ"` (no fractional
  seconds, no timezone offset). If the timestamp does not match this format,
  skip the countdown/pacing display rather than erroring.
- Reset countdown: `diff = resetAt_epoch - now_epoch`; format as `Xh Ym` if
  `diff >= 3600` (always show both parts, e.g. `2h 0m` not `2h`), else `Xm`;
  show `resetting` if `diff <= 0`
- Pacing: if `weeklyResetAt_epoch <= now_epoch`, skip pacing display entirely.
  Otherwise: `days_remaining = (weeklyResetAt_epoch - now_epoch) / 86400`;
  floor to minimum 0.1; `pacing = (100 - weeklyUsage) / days_remaining`;
  format to 1 decimal place

Display: `⚡ 61% 5hr (2h 14m)  ·  ⟳ 38% weekly  ·  → 17.7%/day`

---

## Repository Structure

```
nice-claude-status-bar/
├── context-bar.sh        # main script (install to ~/.claude/scripts/)
├── fetch-usage.sh        # usage fetcher (install to ~/.claude/scripts/)
├── README.md
├── .gitignore
└── forked/               # original reference implementation (unchanged)
    ├── context-bar.sh
    ├── fetch-usage.sh
    └── README.md
```

---

## settings.json Snippet

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh"
  }
}
```

---

## Error Handling

- Every segment is wrapped in logic that produces empty string on any failure
- No `set -e`; all errors handled explicitly
- `jq` failures produce empty string via `// empty` fallbacks
- `git` commands run with `2>/dev/null`; non-zero exit → skip segment
- `curl` failures fall through to stale cache, then empty segment
- `fetch-usage.sh` subprocess failure → skip subscription segment
- The script always exits 0 and always produces valid output (possibly empty
  if all segments fail)
- POSIX sh compatibility: use `.` for sourcing (not `source`); no `[[`, no
  `$BASH_SOURCE`, no process substitution

---

## Non-Goals

- No token count display beyond context % (raw counts removed per design decision)
- No autocompact threshold warning (Claude Code's built-in warning is sufficient)
- No support for non-Claude models (Claude Code only uses Claude)
- No persistent session cost tracking across restarts
- No named color themes (blue accent only when `--color` is passed)
