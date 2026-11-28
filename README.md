# Codex & Antigravity Usage Status

**[English](README.md) | [简体中文](README.zh-CN.md)**

Small, privacy-first macOS menu-bar app for showing **OpenAI Codex** and **Google Antigravity** (Gemini Models & Claude/GPT Models) live usage quotas, reset times, and local token consumption at a glance.

![Codex & Antigravity 3-column menu-bar status](docs/assets/menu-bar-3col.png)

---

## v0.5.0 update: Token usage statistics, low-quota red alert & column visibility

- **Token usage in the dropdown menu**: a new `Token usage · Today / 7 days` section shows today's and the last 7 days' token consumption for `[C] Codex`, `[G] Gemini` and `[A] Claude & GPT`, plus a grand total. Each row has a submenu with an input / cached (with cache hit %) / output (reasoning) breakdown, call counts, and a today-first per-model list. Clicking any quota or token row copies it to the clipboard (clicking the Token header copies the full summary).
- **Red capsule badge & optional notification below 15%**: any remaining quota readout strictly below `15%` in the menu-bar badge is rendered as a high-contrast crimson capsule with crisp white bold text, plus an optional macOS notification (`Low-Quota Notifications`, at most once per reset cycle).
- **Hide individual quota columns**: the new `Visible Quotas` submenu lets you independently hide `[C] Codex`, `[G] Gemini` or `[A] Claude & GPT` from the menu bar and quota list (persisted across restarts, keeping at least one visible; Token usage stats remain available).
- **One-click Launch at Login & power-friendly background**: toggle macOS auto-start directly from the menu (`SMAppService.mainApp`); background quota timers pause automatically while the display sleeps, use coalesced timer tolerance, and perform zero background disk scans (token logs are incrementally read only when opening the menu or refreshing manually).
- **Local, read-only and incremental**: counts come from local Codex session logs (`~/.codex/sessions/**/rollout-*.jsonl`, `token_count` events) and Antigravity conversation transcripts (`~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl`). Only token numbers, model names and timestamps are decoded; conversation text is never stored or uploaded. Files are read incrementally, so refreshes stay cheap. Compressed Codex history (`.jsonl.zst`) is skipped.
- **Totals include cached input**: Codex `input_tokens` already include cached tokens and Antigravity reports cache reads separately; both are normalized to `input (uncached) + cached + output`.
- **Correct Codex window label**: Codex can now return a single 30-day window. The menu bar, dropdown, tooltips and CLI label the window from its real length (`5H` / `7D` / `30D`) instead of always showing `7D` (the CLI previously showed it as `5h`). Resets more than 6 days away show a date instead of a weekday.
- **Stability**: a refresh watchdog (90 s) prevents a stuck query from silencing refreshes; the Codex reader no longer blocks waiting for stderr EOF; a malformed response from one Antigravity daemon falls through to the next; the client version reported to Codex now follows the app version.
- **Debug helper**: `CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus --tokens` prints the token summary in Terminal.

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

## Quick install (via AI Agent or one-line Terminal command)

No Xcode or source build needed. Paste this prompt into **Codex, Antigravity, Claude Code**, or any coding agent:

```text
Install and launch the latest release of FengXiaohub/codex-usage-status into /Applications on my Mac: https://github.com/FengXiaohub/codex-usage-status
```

Or run this one-liner in Terminal (or let your Agent execute it) — it auto-detects Apple Silicon (`arm64`) vs Intel (`x86_64`), downloads the latest GitHub Release ZIP, installs to `/Applications`, clears Gatekeeper quarantine, and starts the app:

```sh
ARCH="$(uname -m)"; [[ "$ARCH" == "x86_64" && "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]] && ARCH="arm64"
TAG="$(basename "$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/FengXiaohub/codex-usage-status/releases/latest)")"
TMP_DIR="$(mktemp -d)" && trap 'rm -rf "$TMP_DIR"' EXIT
curl -fL "https://github.com/FengXiaohub/codex-usage-status/releases/download/${TAG}/CodexUsageStatus-${TAG#v}-macos-${ARCH}.zip" -o "$TMP_DIR/app.zip" && ditto -x -k "$TMP_DIR/app.zip" "$TMP_DIR"
pkill -x CodexUsageStatus 2>/dev/null || true
rm -rf /Applications/CodexUsageStatus.app && ditto "$TMP_DIR/CodexUsageStatus.app" /Applications/CodexUsageStatus.app
xattr -cr /Applications/CodexUsageStatus.app && open -n /Applications/CodexUsageStatus.app
```

---

## Manual install from release

1. Download the latest release ZIP for your Mac from [GitHub Releases](https://github.com/FengXiaohub/codex-usage-status/releases/latest):
   - **Apple Silicon (M1 / M2 / M3 / M4)**: `CodexUsageStatus-0.5.0-macos-arm64.zip`
   - **Intel Mac**: `CodexUsageStatus-0.5.0-macos-x86_64.zip`
2. Unzip it.
3. Move `CodexUsageStatus.app` to `/Applications`.
4. Open `CodexUsageStatus.app`.

### First-launch & auto-sync notes

- **Gatekeeper warning (unsigned build)**: Because release ZIPs are ad-hoc signed, macOS may show an unidentified-developer prompt on first launch. You can allow it in **System Settings > Privacy & Security > Open Anyway**, or run:
  ```sh
  xattr -cr /Applications/CodexUsageStatus.app
  ```
- **Menu-bar-only & Launch at Login**: The app does not appear in the Dock. Click the menu-bar icon and toggle **Launch at Login** to start automatically when you sign in.
- **Automatic sync with client updates**: The app reads live quotas directly from your installed `ChatGPT.app` / `Codex.app` and running `Antigravity.app` local daemon without hardcoding model lists, and automatically refreshes whenever those clients update or launch.

---

## Known limitations

- Codex desktop must be installed at `/Applications/ChatGPT.app` or `/Applications/Codex.app` (unless `CODEX_BIN` is set), or Antigravity desktop must be installed and running at `/Applications/Antigravity.app`.
- You must already be signed in to the respective desktop app.
- Live usage depends on Codex's local app-server method `account/rateLimits/read` and Antigravity's local `127.0.0.1` `RetrieveUserQuotaSummary` endpoint.
- Compressed Codex session archives (`.jsonl.zst`) are skipped for token statistics; active uncompressed sessions and Antigravity conversation transcripts within the 7-day window are counted.
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
  - `App/`: status item lifecycle, menu actions, low-quota notification tracker, refresh scheduling, and configuration.
  - `Codex/`: concurrent local Codex `app-server` JSON-RPC client and Antigravity `127.0.0.1` local daemon reader.
  - `Domain/`: rate-limit response models, Antigravity quota models, 3-column usage normalization, and token report models.
  - `Tokens/`: 256 KB zero-copy incremental token log scanner.
  - `UI/`: 3-column horizontal badge styles, `< 15%` red capsule badge, column visibility, and AppKit drawing code.
  - `Tests/`: Swift `XCTest` unit test suite.
- `src/`: Node CLI probe for diagnostics and tests.
- `test/`: Node tests for Codex & Antigravity response normalization and sensitive-output redaction.
- `scripts/`: build, run, install, and release packaging scripts.
- `.github/workflows/`: CI and release artifact workflows.
- `docs/`: architecture, structure, release, and upstream integration notes.

See [docs/project-structure.md](docs/project-structure.md) for the source layout and dependency boundaries.
