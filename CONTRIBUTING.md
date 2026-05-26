# Contributing

Keep the project boring, narrow, and safe.

## Rules for changes

- Do not read or parse credential files.
- Do not add browser scraping, cookie access, OCR, login automation, account switching, or quota-bypass behavior.
- Keep refreshes conservative.
- Do not lower the minimum refresh interval below 60 seconds.
- Prefer the official local Codex app-server protocol.
- Keep the menu-bar title compact enough for crowded macOS menu bars.

## Local checks

```sh
npm test
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
dist/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus --once
```
