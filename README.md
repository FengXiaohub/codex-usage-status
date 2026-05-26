# Codex Usage Status

Small macOS menu-bar app for showing Codex usage at a glance.

It displays usage as a compact double-ring badge:

- left ring: 5-hour remaining percentage
- right ring: weekly remaining percentage
- ring progress: remaining quota
- center number: remaining percentage
- small in-ring labels: `5h` and `W`

The menu-bar badge is the primary interface. Clicking it only exposes the necessary actions: Refresh, Settings, and Quit.

Double Ring is the default display style. A larger accessibility-oriented style is available from Display Style > Large Readout. Large Readout keeps the same two values visible in the menu bar, but prioritizes readable numbers with weak `5h` / `W` labels and thin status lines instead of centered rings.

## Safety model

This app only calls the official local Codex app-server method `account/rateLimits/read`. It does not modify Codex, does not read `~/.codex/auth.json`, and does not handle tokens, cookies, sessions, OAuth credentials, API keys, or browser data.

See [SECURITY.md](SECURITY.md) for the hard boundaries.

## Requirements

- macOS 13 or later
- Codex desktop installed at `/Applications/Codex.app`
- You are already signed in to Codex

For source builds:

- Swift toolchain / Xcode Command Line Tools
- Node.js 20 or later for tests and the optional CLI probe

## Quick start from source

```sh
npm test
npm run build:macos
npm run start:macos
```

To install into `/Applications`:

```sh
npm run install:macos
```

The app is a menu-bar-only app, so it does not appear in the Dock.

To change the menu-bar display, click the badge and choose Display Style:

- Double Ring: compact default with two circular quota indicators.
- Large Readout: larger numbers with subtle status lines for easier reading.

The default refresh interval is 120 seconds, with a 60-second minimum. To override it:

```sh
CODEX_USAGE_REFRESH_SECONDS=180 npm run start:macos
```

## CLI probe

The CLI uses the same safe app-server source and is useful for debugging:

```sh
npm run usage
npm run usage:json
```

The CLI output remains text-based for logs and tests even though the macOS menu-bar UI is a graphic badge.

If your Codex binary lives somewhere else:

```sh
CODEX_BIN=/path/to/codex npm run usage
```

## Release package

```sh
npm run package:macos
```

This creates a zipped `.app` and `SHA256SUMS.txt` in `dist/`.

Unsigned GitHub builds may trigger macOS Gatekeeper warnings. For a public polished release, sign with an Apple Developer ID and notarize the app.

## Repository layout

- `macos/CodexUsageStatus/`: native AppKit menu-bar app.
- `src/`: Node CLI probe and shared response formatter tests.
- `scripts/`: build, run, install, and release packaging scripts.
- `.github/workflows/`: CI and release artifact workflows.
- `docs/`: architecture, release, and upstream integration notes.
