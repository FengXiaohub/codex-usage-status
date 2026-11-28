# Privacy

Codex & Antigravity Usage Status is intentionally narrow: it shows local Codex and Antigravity usage status and token consumption in the macOS menu bar.

## What the app reads

1. **Codex quota**: the local Codex app-server, started as a child process, answering one read-only method:
```json
{"method":"account/rateLimits/read","id":2}
```
2. **Antigravity quota**: the running Antigravity desktop daemon on `127.0.0.1`, using the port and per-session CSRF token from its local discovery file (`~/.gemini/antigravity/daemon/hub_*.json`), with one read-only request: `RetrieveUserQuotaSummary`.
3. **Token statistics (v0.5.0+)**: local log files that Codex and Antigravity already write:
   - `~/.codex/sessions/**/rollout-*.jsonl` (and uncompressed files in `~/.codex/archived_sessions`): only `token_count` events and the model name from `turn_context` lines are decoded.
   - `~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl`: only `input_tokens`, `output_tokens`, `cache_read_tokens`, `model` and `created_at` are decoded.

   These files also contain conversation text. The app scans them only for lines carrying token markers, keeps only numbers, model names and dates in memory, and never stores, logs or transmits the text. Only files modified within the last 7 days are read.

Codex and Antigravity themselves own authentication. This companion app receives only usage percentages, reset times and token counts.

## What the app does not read

- It does not read `~/.codex/auth.json` or Antigravity credential stores.
- It does not read browser cookies, browser storage, OAuth credentials, refresh tokens, API keys, or account passwords.
- It does not scrape Codex or Antigravity UI pages, browser pages, screenshots, or OCR output.
- It does not modify the official Codex, ChatGPT, or Antigravity app bundles or their log files.
- It does not bypass, increase, reset, purchase, or route around usage limits.

## What leaves your Mac

Nothing. This app does not upload usage or token data to this project, to the author, or to any third-party service, and it writes no token cache to disk.

The only network activity involved is whatever the official Codex app-server performs as part of your signed-in account flow. The Antigravity query stays on the `127.0.0.1` loopback interface.

## Refresh behavior

The default refresh interval is 120 seconds and the minimum is 60 seconds. Failed refreshes retry after 30 seconds while cached values are still shown, then back off to 120 seconds. Token statistics are recomputed on each refresh and when the menu is opened (at most every 15 seconds), reading only newly appended bytes.
