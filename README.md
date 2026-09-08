# Codex Usage Status

Small macOS menu-bar app for showing Codex usage at a glance.

## v0.2.0 update

This release adds a compact reset-time display and English localization. The new `Quota & Reset Times` style shows the precise reset point for both quota windows, with an automatically measured width for Chinese and English labels. This makes it easier to understand exactly when the 5-hour and weekly limits become available again.

![Codex Usage Status menu-bar badge](docs/assets/menu-bar-badge.png)

It displays usage as a compact side-labeled double-ring badge:

- left ring group: 5-hour remaining percentage
- right ring group: weekly remaining percentage
- ring progress: remaining quota status
- ring center number: remaining percentage
- side labels: `5H` and `7D`

The menu-bar badge is the primary interface. Clicking it only exposes the necessary actions: Refresh, Settings, and Quit.

## Update: reset-time display

This project update adds a `Quota & Reset Times` display style so you can see when each quota window resets, not only how much remains. It uses a compact two-line layout:

```text
72%·18:18
43%·周日12:57
```

The format follows the Mac's current language. In English it becomes, for example:

```text
72%·18:18
43%·Sun12:57
```

The badge width is measured from the current strings, so it stays as narrow as possible and expands only when a longer reset label such as `Tomorrow 00:13` is needed. Select it from the badge menu under `Display Style` > `Quota & Reset Times`.

Double Ring is the default display style. It uses no capsule background, and each label sits beside its own ring instead of inside the ring. A larger accessibility-oriented style is available from Display Style > Large Readout. Large Readout keeps the same two values visible in the menu bar, but prioritizes even larger readable numbers with weak `5H` / `7D` labels and thin status lines.

## Safety model

This app only calls the official local Codex app-server method `account/rateLimits/read`. It does not modify Codex, does not read `~/.codex/auth.json`, and does not handle tokens, cookies, sessions, OAuth credentials, API keys, or browser data.

See [PRIVACY.md](PRIVACY.md) for the user-facing privacy summary and [SECURITY.md](SECURITY.md) for the hard engineering boundaries.

## Requirements

- macOS 13 or later
- Codex desktop installed at `/Applications/Codex.app` or the current ChatGPT desktop app at `/Applications/ChatGPT.app`
- You are already signed in to Codex

## Install from release

1. Download the latest release ZIP for your Mac from [GitHub Releases](https://github.com/tollenceld/codex-usage-status/releases/latest):
   - Apple Silicon: `CodexUsageStatus-<version>-macos-arm64.zip`
   - Intel: `CodexUsageStatus-<version>-macos-x86_64.zip`
2. Unzip it.
3. Move `CodexUsageStatus.app` to `/Applications`.
4. Open `CodexUsageStatus.app`.

The app is a menu-bar-only app, so it does not appear in the Dock. Optional: add it to macOS System Settings > General > Login Items.

Unsigned GitHub builds may trigger macOS Gatekeeper warnings. For a public polished release, sign with an Apple Developer ID and notarize the app.

## Known limitations

- Codex desktop must be installed at `/Applications/Codex.app` or `/Applications/ChatGPT.app`, unless `CODEX_BIN` is set for development.
- You must already be signed in to Codex.
- Live usage depends on Codex's local app-server method `account/rateLimits/read`; if that local interface changes, this app may need an update.
- The app shows usage only. It cannot buy credits, switch accounts, retry login, or change limits.
- Local builds are ad-hoc signed by default. Downloaded release ZIPs may show Gatekeeper warnings until a notarized build is available.

## Build from source

For source builds:

- Swift toolchain / Xcode Command Line Tools
- Node.js 20 or later for tests and the optional CLI probe

```sh
npm test
npm run build:macos
npm run start:macos
```

The build script defaults to the Mac's hardware architecture. On Apple Silicon this creates an `arm64` app, even if Node.js is running under Rosetta. To build a specific architecture:

```sh
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
```

To install into `/Applications`:

```sh
npm run install:macos
```

The app is a menu-bar-only app, so it does not appear in the Dock.

To change the menu-bar display, click the badge and choose Display Style:

- Double Ring: compact default with side labels and circular quota indicators.
- Large Readout: larger numbers with subtle status lines for easier reading.
- Quota & Reset Times: two narrow lines showing each remaining percentage and its reset time; the weekday and relative day labels follow the Mac's current language.

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
npm run package:macos:all
```

`package:macos` creates a zipped `.app` for the current Mac architecture. `package:macos:all` creates both `arm64` and `x86_64` ZIPs plus `SHA256SUMS.txt` in `dist/`.

Release ZIPs are architecture-specific:

- `CodexUsageStatus-<version>-macos-arm64.zip` for Apple Silicon Macs.
- `CodexUsageStatus-<version>-macos-x86_64.zip` for Intel Macs.

For another MacBook, the most reliable source-build path is to clone the repository on that Mac and run `npm run install:macos`; it will build the correct native architecture there.

## Repository layout

- `macos/CodexUsageStatus/`: native AppKit menu-bar app.
  - `App/`: status item lifecycle, menu actions, refresh scheduling, and configuration.
  - `Codex/`: local Codex app-server JSON-RPC client.
  - `Domain/`: rate-limit response models and usage normalization.
  - `UI/`: badge styles and AppKit drawing code.
- `src/`: Node CLI probe for diagnostics and tests.
- `test/`: Node tests for response normalization and sensitive-output redaction.
- `scripts/`: build, run, install, and release packaging scripts.
- `.github/workflows/`: CI and release artifact workflows.
- `docs/`: architecture, structure, release, and upstream integration notes.

See [docs/project-structure.md](docs/project-structure.md) for the source layout and dependency boundaries.

