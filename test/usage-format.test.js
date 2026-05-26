import assert from "node:assert/strict";
import test from "node:test";

import { redactSensitive } from "../src/app-server-client.js";
import { formatMenuTitle, normalizeUsage } from "../src/usage-format.js";

test("normalizes Codex 5-hour and weekly windows", () => {
  const usage = normalizeUsage({
    rateLimitsByLimitId: {
      codex: {
        limitId: "codex",
        planType: "plus",
        primary: {
          usedPercent: 34,
          windowDurationMins: 300,
          resetsAt: 1780000000,
        },
        secondary: {
          usedPercent: 37,
          windowDurationMins: 10080,
          resetsAt: 1780500000,
        },
      },
    },
  });

  assert.equal(usage.limitId, "codex");
  assert.equal(usage.planType, "plus");
  assert.equal(usage.fiveHour.remainingPercent, 66);
  assert.equal(usage.weekly.remainingPercent, 63);
  assert.equal(formatMenuTitle(usage), "Codex 5h 66% 7d 63%");
});

test("falls back to backward-compatible single snapshot", () => {
  const usage = normalizeUsage({
    rateLimits: {
      limitId: "codex",
      primary: {
        usedPercent: 0,
        windowDurationMins: 300,
      },
      secondary: {
        usedPercent: 101,
        windowDurationMins: 10080,
      },
    },
  });

  assert.equal(usage.fiveHour.remainingPercent, 100);
  assert.equal(usage.weekly.remainingPercent, 0);
});

test("redacts sensitive app-server stderr snippets", () => {
  const redacted = redactSensitive(
    [
      "token: sk-local-development-secret",
      "Authorization = Bearer should-not-survive",
      "api_key=also-should-not-survive",
      "aaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbb.cccccccccccccccccccc",
    ].join("\n"),
  );

  assert.match(redacted, /token: \[redacted\]/);
  assert.match(redacted, /Authorization = \[redacted\]/);
  assert.match(redacted, /api_key=\[redacted\]/);
  assert.match(redacted, /\[redacted-jwt\]/);
  assert.doesNotMatch(redacted, /should-not-survive|also-should-not-survive/);
});
