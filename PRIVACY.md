# Privacy

Codex & Antigravity Usage Status is intentionally narrow: it shows local Codex and Antigravity usage status in the macOS menu bar.

## What the app reads

The app reads only the structured usage responses returned by the official local CLI interfaces:

1. **Codex**: local Codex app-server method:
```json
{"method":"account/rateLimits/read","id":2}
```
2. **Antigravity**: local Antigravity CLI read-only command:
```sh
agy -p "/usage" --output-format json
```

Codex and Antigravity themselves own authentication. This companion app receives only the usage percentages and reset times returned through those local interfaces.

## What the app does not read

- It does not read `~/.codex/auth.json` or Antigravity credential stores.
- It does not read browser cookies, browser storage, sessions, OAuth credentials, refresh tokens, API keys, or account passwords.
- It does not scrape Codex or Antigravity UI pages, browser pages, screenshots, or OCR output.
- It does not modify the official Codex, ChatGPT, or Antigravity app bundles.
- It does not bypass, increase, reset, purchase, or route around usage limits.

## What leaves your Mac

This app does not upload usage data to this project, to the author, or to any third-party service.

The only network activity involved is whatever the official Codex app-server or Antigravity CLI performs as part of your signed-in account flow. This project does not handle those credentials or proxy that traffic.

## Refresh behavior

The default refresh interval is 120 seconds. The minimum refresh interval is 60 seconds, and failed refreshes back off to 300 seconds.

Usage status does not need high-frequency polling, so the app keeps refreshes conservative.
