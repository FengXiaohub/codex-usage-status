# Upstream desktop integration RFC

This is the preferred path if the Codex desktop UI source accepts external contributions or internal patches.

## Existing implementation hook

The packaged desktop app already fetches usage data through its own settings flow. Static inspection showed:

- usage query key: `rate-limit-status`
- backend path: `/wham/usage`
- refresh interval: one minute
- parsed fields: `primary_window`, `secondary_window`, `used_percent`, `reset_at`, `credits`, `plan_type`
- main-process tray data already includes a `usageLimits` array

## Proposed change

Add a compact always-visible usage indicator using existing in-app data:

- macOS tray badge: double-ring status item, with `5h` on the left and `W` on the right
- optional large readout style with larger numbers and subtle status lines
- optional renderer header pill in a low-noise corner of the Codex window
- minimal dropdown actions for refresh, settings, and quit

## Constraints

- Do not add new backend endpoints.
- Do not increase refresh frequency beyond the existing one-minute cadence.
- Do not expose or log credentials.
- Do not add login automation, account switching, or credit-purchase automation.
- Do not patch the signed production app bundle after build.

## Minimal desktop patch shape

1. Reuse the existing usage-limit parser.
2. Send compact usage summary to the main process with existing tray state updates.
3. On macOS, render a custom tray image instead of a flat text title.
4. Keep reset details in Settings or tooltip-level disclosure.
5. Leave Settings as the canonical detailed view.
