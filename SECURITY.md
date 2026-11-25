# Security policy

This project is intentionally narrow: it displays Codex and Antigravity usage status and nothing else.

## Hard boundaries

- It does not read, print, store, upload, transform, or proxy tokens, cookies, sessions, OAuth credentials, refresh tokens, or API keys.
- It does not read `~/.codex/auth.json` or Antigravity credential stores.
- It does not scrape browser state, browser cookies, web pages, screenshots, or OCR output.
- It does not simulate login or retry login flows.
- It does not modify the official Codex, ChatGPT, or Antigravity app bundles.
- It does not attempt to bypass, increase, reset, purchase, or route around usage limits.

## Data sources

The only supported live data sources are the official local CLI interfaces:

1. Codex local app-server method:
```json
{"method":"account/rateLimits/read","id":1}
```
2. Antigravity local CLI command:
```sh
agy -p "/usage" --output-format json
```

Codex and Antigravity own authentication and call their own backends. This project receives only the structured rate-limit / quota responses returned by those local interfaces.

## Refresh policy

The default menu-bar refresh interval is 120 seconds, with a 60-second minimum. Failed refreshes back off to 300 seconds. Keep refreshes conservative; usage status does not need sub-second polling.

## If this stops working

Stop at the official boundary. Do not add cookie scraping, token extraction, browser automation, OCR, or patched-app workarounds as fallbacks.
