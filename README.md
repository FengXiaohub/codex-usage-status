# Codex & Antigravity Usage Status

**[English](README.md) | [简体中文](README.zh-CN.md)**

Small, privacy-first macOS menu-bar app for showing **OpenAI Codex** and **Google Antigravity** (Gemini Models & Claude/GPT Models) usage quotas at a glance.

![Codex & Antigravity 3-column menu-bar status](docs/assets/menu-bar-3col.png)

---

## v0.4.4 update: Direct local Antigravity daemon IPC & zero-CPU-loop stability

- **Direct `127.0.0.1` loopback query (replaces `agy` CLI spawning)**: Reads live Antigravity quotas directly from the running Antigravity desktop daemon (`~/.gemini/antigravity/daemon/hub_*.json` → `RetrieveUserQuotaSummary` over `127.0.0.1`, bypassing VPN/PAC/system proxies via `connectionProxyDictionary = [:]`). Eliminates spawning `agy` subprocesses, cuts query latency to ~5 ms, and prevents macOS `sandboxd` TCC thread exhaustion on Login Item auto-start.
- **Fixes 99.5% CPU appearance KVO loop**: Observes `NSApp.effectiveAppearance` with resolved light/dark deduplication instead of `NSStatusBarButton.effectiveAppearance`, keeping idle CPU at `0.0%`.
- **Isolated `codex` working directory & quiet idle state**: Runs `codex app-server` in a dedicated `0700` temporary directory; when Antigravity desktop is not open yet at boot, `G`/`A` columns quietly retain cached values or show `--` instead of flashing red `?`, and sync automatically once Antigravity launches.

## v0.4.2 update: Stability, system proxy & instant theme sync

- **Automatic macOS system proxy inheritance**: When launched via Login Items or Finder (LaunchServices), the app dynamically reads macOS system proxy settings (`CFNetworkCopySystemProxySettings`) and injects them into `agy` / `codex` subprocesses so proxy users work out of the box.
- **Anti-flicker resilience**: Adds a 35-second Antigravity timeout, automatic single retry, 5-second post-wake refresh delay, and stale-while-revalidate caching (retaining the last valid quota across 1–2 transient network blips instead of flashing red `?`).
- **Instant Dark / Light mode redraw & hardened IPC**: Automatically re-renders when macOS appearance changes, brings the Settings dialog to front, and ignores `SIGPIPE` with safe Swift `FileHandle` writes.

## v0.4.0 update: 3-column horizontal Codex + Antigravity display

The menu-bar badge now combines **three quota groups** side-by-side in a single compact `NSStatusItem`:

- **`C` (Codex)**: 5-hour and weekly quota windows from the local Codex app-server (`/Applications/ChatGPT.app` or `/Applications/Codex.app`).
- **`G` (Antigravity Gemini Models)**: 5-hour and weekly quota windows for the Gemini model group (`Gemini 4 Neon / Carbon / Argon / Hydrogen`, `Orchestrator`, `Gemini 3.8 Flash`).
- **`A` (Antigravity Claude & GPT Models)**: 5-hour and weekly quota windows for the Antigravity third-party model group (`Claude Opus / Sonnet`, `GPT-OSS`).

### Default display layout (`Quota & Reset Times`)

By default, the menu bar uses the `Quota & Reset Times` style arranged horizontally across three columns (`C | G | A`), with a bold single-letter label on the left of each two-line column:

```text
C 88%·21:05      | G 83%·明天00:55  | A 100%·明天01:28
  0%·周三15:32   |   91%·12月1日    |   100%·12月1日
```

In English locales:

```text
C 88%·21:05      | G 83%·Tomorrow 00:55 | A 100%·Tomorrow 01:28
  0%·Wed15:32    |   91%·Dec 1 14:55    |   100%·Dec 1 20:28
```

- **Top row**: 5-hour (`5H`) remaining percentage and reset time.
- **Bottom row**: Weekly (`7D`) remaining percentage and reset time.
- **Graceful partial availability**: Codex and Antigravity are queried concurrently. If one tool is not installed or unavailable, the remaining columns still render normally.
- **Three switchable styles**: You can switch between `Quota & Reset Times` (default), `Double Ring`, and `Large Readout` from the menu bar under `Display Style`.

---

## Previous updates

### v0.3.2 update

The macOS app supports the current ChatGPT desktop bundle, where Codex is packaged at `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`. Older ChatGPT and standalone Codex paths remain supported.

### v0.3.1 update

The macOS app detects the Codex executable in both the current ChatGPT desktop app and the legacy standalone Codex app. This fixes the red `?` state that appeared when only `/Applications/ChatGPT.app` was installed.

### v0.3.0 update

The badge adapts automatically to the quota windows returned by Codex:

- Plus-style accounts with 5-hour and weekly windows keep the two-line reset-time display.
- Pro-style accounts that expose only the weekly window show one larger, centered line such as `43%·Sun12:57` (or `43%·周日12:57` in Chinese).
- The 5H menu item and 5H visualization are hidden when no 5-hour window is available.

### v0.2.0 update

Added the compact `Quota & Reset Times` display style and English/Chinese localization.

![Codex Usage Status menu-bar badge](docs/assets/menu-bar-badge.png)

---

## Safety model

This app strictly respects local credential boundaries:

- **Codex**: Only calls the official local Codex app-server method `account/rateLimits/read` in an isolated temporary working directory.
- **Antigravity**: Only calls the local Antigravity desktop daemon's read-only `RetrieveUserQuotaSummary` RPC over `127.0.0.1` using the session-local `csrfToken` from `~/.gemini/antigravity/daemon/hub_*.json`.
- It **does not** modify Codex or Antigravity, **does not** read `~/.codex/auth.json` or Antigravity OAuth/Keychain credential stores, and **does not** touch user documents, cookies, API keys, or browser data.

See [PRIVACY.md](PRIVACY.md) for the user-facing privacy summary and [SECURITY.md](SECURITY.md) for the hard engineering boundaries.

---

## Requirements

- macOS 13 or later
- At least one of the following installed and signed in:
  - **Codex**: `/Applications/ChatGPT.app` or `/Applications/Codex.app` (override with `CODEX_BIN`)
  - **Antigravity**: `/Applications/Antigravity.app` (signed in and running)

---

## Install from release

1. Download the latest release ZIP for your Mac from [GitHub Releases](https://github.com/FengXiaohub/codex-usage-status/releases/latest):
   - **Apple Silicon (M1 / M2 / M3 / M4)**: `CodexUsageStatus-0.4.4-macos-arm64.zip`
   - **Intel Mac**: `CodexUsageStatus-0.4.4-macos-x86_64.zip`
2. Unzip it.
3. Move `CodexUsageStatus.app` to `/Applications`.
4. Open `CodexUsageStatus.app`.

### First-launch & auto-sync notes

- **Gatekeeper warning (unsigned build)**: Because release ZIPs are ad-hoc signed, macOS may show an unidentified-developer prompt on first launch. You can allow it in **System Settings > Privacy & Security > Open Anyway**, or run:
  ```sh
  xattr -cr /Applications/CodexUsageStatus.app
  ```
- **Menu-bar-only**: The app does not appear in the Dock. Optional: add it to **macOS System Settings > General > Login Items** to launch automatically at login.
- **Automatic sync with client updates**: The app reads live quotas directly from your installed `ChatGPT.app` / `Codex.app` and `agy` CLI without hardcoding model lists, and automatically refreshes whenever those clients update or launch.

---

## Known limitations

- Codex desktop must be installed at `/Applications/ChatGPT.app` or `/Applications/Codex.app` (unless `CODEX_BIN` is set), and Antigravity CLI must be installed at `~/.local/bin/agy`, `/usr/local/bin/agy`, or `/opt/homebrew/bin/agy` (unless `AGY_BIN` is set).
- You must already be signed in to the respective CLI/app.
- Live usage depends on Codex's local app-server method `account/rateLimits/read` and Antigravity's `agy -p "/usage" --output-format json`.
- The app shows usage only. It cannot buy credits, switch accounts, retry login, or change limits.

---

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

To change the menu-bar display, click the badge and choose `Display Style`:

- **Quota & Reset Times** (Default): three horizontal columns (`C`, `G`, `A`), each showing two narrow lines for the 5-hour and weekly remaining percentages and reset times.
- **Double Ring**: compact circular quota indicators with side labels for each column.
- **Large Readout**: larger numbers with subtle status progress lines under each value.

The default refresh interval is 120 seconds, with a 60-second minimum. To override it:

```sh
CODEX_USAGE_REFRESH_SECONDS=180 npm run start:macos
```

---

## CLI probe

The Node.js CLI probe queries both Codex and Antigravity in parallel using the same safe local commands:

```sh
npm run usage
npm run usage:json
```

You can also run the native macOS binary in single-shot diagnostic mode:

```sh
./dist/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus --once
# Example output: C 5h 88% 7d 0% | G 5h 83% 7d 91% | A 5h 100% 7d 100%
```

If your binaries live in custom paths:

```sh
CODEX_BIN=/path/to/codex AGY_BIN=/path/to/agy npm run usage
```

---

## Release package

```sh
npm run package:macos
npm run package:macos:all
```

`package:macos` creates a zipped `.app` for the current Mac architecture. `package:macos:all` creates both `arm64` and `x86_64` ZIPs plus `SHA256SUMS.txt` in `dist/`.

---

## Repository layout

- `macos/CodexUsageStatus/`: native AppKit menu-bar app.
  - `App/`: status item lifecycle, menu actions, refresh scheduling, and configuration.
  - `Codex/`: concurrent local Codex `app-server` JSON-RPC client and Antigravity `agy` CLI runner.
  - `Domain/`: rate-limit response models, Antigravity quota models, and 3-column usage normalization.
  - `UI/`: 3-column horizontal badge styles and AppKit drawing code.
- `src/`: Node CLI probe for diagnostics and tests.
- `test/`: Node tests for Codex & Antigravity response normalization and sensitive-output redaction.
- `scripts/`: build, run, install, and release packaging scripts.
- `.github/workflows/`: CI and release artifact workflows.
- `docs/`: architecture, structure, release, and upstream integration notes.

See [docs/project-structure.md](docs/project-structure.md) for the source layout and dependency boundaries.
