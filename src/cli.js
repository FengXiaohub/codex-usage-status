#!/usr/bin/env node
import { readAntigravityQuota, readCodexRateLimits } from "./app-server-client.js";
import { formatCombinedTextStatus, normalizeAntigravityUsage, normalizeUsage } from "./usage-format.js";

const args = new Set(process.argv.slice(2));

const [codexResult, agyResult] = await Promise.allSettled([
  readCodexRateLimits().then((raw) => normalizeUsage(raw)),
  readAntigravityQuota().then((raw) => normalizeAntigravityUsage(raw)),
]);

const combined = {
  codex: codexResult.status === "fulfilled" ? codexResult.value : null,
  gemini: agyResult.status === "fulfilled" ? agyResult.value.gemini : null,
  claudeGpt: agyResult.status === "fulfilled" ? agyResult.value.claudeGpt : null,
  errors: {
    codex: codexResult.status === "rejected" ? codexResult.reason?.message ?? String(codexResult.reason) : null,
    antigravity: agyResult.status === "rejected" ? agyResult.reason?.message ?? String(agyResult.reason) : null,
  },
};

if (!combined.codex && !combined.gemini && !combined.claudeGpt) {
  console.error(
    `Unable to read Codex or Antigravity usage safely: Codex(${combined.errors.codex}) / Antigravity(${combined.errors.antigravity})`,
  );
  process.exitCode = 1;
} else if (args.has("--json")) {
  console.log(JSON.stringify(combined, null, 2));
} else {
  console.log(formatCombinedTextStatus(combined));
}
