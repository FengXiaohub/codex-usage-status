# Technical review

## Current architecture

The app is intentionally split into two pieces:

- Native macOS UI: AppKit status item in `macos/CodexUsageStatus`.
- Probe/test layer: Node client and formatter tests in `src/` and `test/`.

The production app does not need Node at runtime. It directly spawns:

```sh
/Applications/Codex.app/Contents/Resources/codex app-server --listen stdio://
```

Then it sends the official JSON-RPC method:

```json
{"method":"account/rateLimits/read","id":2}
```

## Why this is safer than patching Codex.app

Patching the packaged Codex desktop bundle breaks signing and ASAR integrity assumptions. A companion app keeps Codex untouched and relies on the same official local app-server boundary used by supported integrations.

## Menu-bar display

The menu-bar title is compact and semantic:

```text
5h 54% 7d 62%
```

This avoids spending width on the product name. The icon identifies the status item, while the text is reserved for the two values users need most.

## Refresh behavior

Refresh is intentionally conservative:

- automatic refresh every 120 seconds by default
- 60-second minimum if overridden with `CODEX_USAGE_REFRESH_SECONDS`
- failed refreshes back off to 300 seconds
- no overlapping refreshes
- manual refresh from the menu
- 20-second timeout per app-server request

## Known limitations

- The app assumes Codex is installed at `/Applications/Codex.app` unless `CODEX_BIN` is set.
- Public release builds should be Developer ID signed and notarized.
- The menu-bar companion cannot draw inside the official Codex desktop window. That requires an upstream Codex desktop change.

## Good next issues

- User preference for title style: compact, detailed, icon-only.
- Optional LaunchAgent helper for start-at-login.
- Notarized release pipeline.
- Better error menu with a copyable diagnostic summary that still redacts secrets.
