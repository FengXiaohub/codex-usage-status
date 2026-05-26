# GitHub issue draft

Title: Show Codex usage limits in an always-visible desktop/menu-bar location

## Problem

Codex desktop already shows 5-hour and weekly usage limits in Settings, but the data is hidden behind multiple clicks. Users who actively manage their working sessions need a low-friction way to see remaining usage and reset times.

## Proposal

Add an always-visible compact usage indicator:

- macOS menu-bar/tray title, for example `5h 66% 7d 63%`
- optional compact header/status pill inside the Codex desktop window
- dropdown details for reset times
- manual refresh action

## Safety constraints

- Use only existing official usage-limit data sources.
- Do not expose tokens, cookies, sessions, OAuth credentials, or refresh tokens.
- Do not increase polling frequency beyond the existing conservative refresh cadence.
- Do not implement account switching, limit bypassing, login retry automation, or credit-purchase automation.

## Related implementation note

The local app-server already exposes a read-only `account/rateLimits/read` method. A companion implementation can use this method safely without reading credential files directly.
