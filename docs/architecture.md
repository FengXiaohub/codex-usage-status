# Architecture

## Goal

Display Codex quota status where it is visible at a glance:

- 5-hour usage window
- weekly usage window
- reset times
- manual refresh state

## Data flow

```mermaid
flowchart LR
  A["Menu-bar app or CLI"] -->|"stdio JSON-RPC"| B["codex app-server"]
  B -->|"official Codex auth path"| C["Codex backend"]
  C -->|"rate-limit snapshot"| B
  B -->|"sanitized usage response"| A
```

## JSON-RPC method

The project calls:

```json
{"method":"account/rateLimits/read","id":2}
```

The relevant response fields are:

- `rateLimits.primary.usedPercent`
- `rateLimits.primary.windowDurationMins`
- `rateLimits.primary.resetsAt`
- `rateLimits.secondary.usedPercent`
- `rateLimits.secondary.windowDurationMins`
- `rateLimits.secondary.resetsAt`
- `rateLimitsByLimitId.codex` when present

The UI displays remaining percent as `100 - usedPercent`.

## Why not patch Codex.app?

Patching the packaged desktop app breaks the official app signature and ASAR integrity model. That is brittle, hard to share safely, and can cause launch crashes. This repository only builds its own companion menu-bar app and leaves the official Codex bundle untouched.
