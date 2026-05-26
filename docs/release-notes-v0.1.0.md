# Codex Usage Status v0.1.0

Initial public release.

## Highlights

- Native macOS menu-bar app for Codex usage status.
- Default side-labeled double-ring badge for 5-hour and 7-day remaining quota.
- Optional Large Readout style for easier reading.
- Manual refresh, display style switcher, settings summary, and quit action.
- Conservative automatic refresh interval with failed-refresh backoff.
- Read-only local data source through Codex app-server `account/rateLimits/read`.

## Privacy and safety

- Does not read `~/.codex/auth.json`.
- Does not handle tokens, cookies, sessions, OAuth credentials, API keys, browser data, screenshots, or OCR output.
- Does not modify the official Codex app.
- Does not bypass, increase, reset, purchase, or route around Codex usage limits.

## Downloads

- `CodexUsageStatus-0.1.0-macos-arm64.zip`: Apple Silicon Macs.
- `CodexUsageStatus-0.1.0-macos-x86_64.zip`: Intel Macs.
- `SHA256SUMS.txt`: checksums for both ZIP files.

Unsigned GitHub builds may trigger macOS Gatekeeper warnings. A future polished binary release should use Apple Developer ID signing and notarization.
