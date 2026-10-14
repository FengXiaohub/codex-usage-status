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

Run these checks from the repository root. Use Node.js 20 or later for the existing Node tests:

```sh
npm test
```

For a Swift release build without writing build output into this repository, use a fresh scratch directory outside it (Swift 6 and the macOS build tools are required):

```sh
BUILD_SCRATCH="$(mktemp -d)"
swift build --package-path macos/CodexUsageStatus --scratch-path "$BUILD_SCRATCH" -c release
```

Do not add build output to Git, including `dist/`, `.build/`, or untracked validation directories. Check `git status` before staging files.

`npm run build:macos` replaces the app in `dist/`. The packaging scripts also replace release archives in `dist/`. `npm run start:macos` stops a running CodexUsageStatus process; `npm run install:macos` stops it and replaces the installed app. Do not use these scripts for routine checks when preserving an existing app.

A successful source build does not verify the installed app, its account connection, signing or notarization, or release readiness.
