# Security policy

This project is intentionally narrow: it displays local Codex and Antigravity usage status and token consumption, and nothing else.

## Hard boundaries

- It does not read, print, store, upload, transform, or proxy tokens, cookies, sessions, OAuth credentials, refresh tokens, or API keys.
- It does not read `~/.codex/auth.json` or Antigravity credential stores.
- It does not scrape browser state, browser cookies, web pages, screenshots, or OCR output.
- It does not simulate login or retry login flows.
- It does not modify the official Codex, ChatGPT, or Antigravity app bundles or their log files.
- It does not attempt to bypass, increase, reset, purchase, or route around usage limits.
- When scanning local session logs for token statistics, it decodes only lines containing token-count fields and retains only numeric counts, model names, and timestamps in memory — never conversation text.

## Data sources

1. **Codex quota**: local Codex `app-server` read-only method in an isolated `0700` temporary working directory:
```json
{"method":"account/rateLimits/read","id":2}
```
2. **Antigravity quota**: running local Antigravity desktop daemon over `127.0.0.1` (`RetrieveUserQuotaSummary`) using the session-local port and `csrfToken` in `~/.gemini/antigravity/daemon/hub_*.json` with proxies explicitly bypassed.
3. **Token statistics**: incremental read-only byte scan of `~/.codex/sessions/**/rollout-*.jsonl` (`token_count` events) and `~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl` (`input_tokens` / `output_tokens` / `cache_read_tokens`).

Codex and Antigravity own authentication and call their own backends.

## Refresh policy

The default menu-bar refresh interval is 120 seconds (minimum 60 seconds), paused automatically while the display sleeps. Transient failures retry once after 30 seconds while retaining cached values, then back off to 120 seconds.

## If this stops working

Stop at the official boundary. Do not add cookie scraping, credential extraction, browser automation, OCR, or patched-app workarounds as fallbacks.
