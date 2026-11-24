import assert from "node:assert/strict";
import test from "node:test";

import { redactSensitive } from "../src/app-server-client.js";
import { formatMenuTitle, normalizeAntigravityUsage, normalizeUsage } from "../src/usage-format.js";

test("normalizes Antigravity Gemini and Claude/GPT quota groups", () => {
  const agy = normalizeAntigravityUsage({
    status: "SUCCESS",
    command: {
      name: "usage",
      data: {
        groups: [
          {
            name: "Gemini Models",
            buckets: [
              {
                id: "gemini-weekly",
                name: "Weekly Limit Remaining",
                window: "weekly",
                remaining_fraction: 0.9336,
                reset_time: "2026-12-01T06:55:17Z",
              },
              {
                id: "gemini-5h",
                name: "Five Hour Limit Remaining",
                window: "5h",
                remaining_fraction: 0.9233,
                reset_time: "2026-11-24T16:55:17Z",
              },
            ],
          },
          {
            name: "Claude and GPT models",
            buckets: [
              {
                id: "3p-weekly",
                name: "Weekly Limit Remaining",
                window: "weekly",
                remaining_fraction: 1,
                reset_time: "2026-12-01T12:21:12Z",
              },
              {
                id: "3p-5h",
                name: "Five Hour Limit Remaining",
                window: "5h",
                remaining_fraction: 0.85,
                reset_time: "2026-11-24T17:21:12Z",
              },
            ],
          },
        ],
      },
    },
  });

  assert.equal(agy.gemini.label, "G");
  assert.equal(agy.gemini.fiveHour.remainingPercent, 92);
  assert.equal(agy.gemini.weekly.remainingPercent, 93);
  assert.equal(formatMenuTitle(agy.gemini), "Antigravity Gemini 5h 92% 7d 93%");

  assert.equal(agy.claudeGpt.label, "A");
  assert.equal(agy.claudeGpt.fiveHour.remainingPercent, 85);
  assert.equal(agy.claudeGpt.weekly.remainingPercent, 100);
  assert.equal(formatMenuTitle(agy.claudeGpt), "Antigravity Claude & GPT 5h 85% 7d 100%");
});

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
