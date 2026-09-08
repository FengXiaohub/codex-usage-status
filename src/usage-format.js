const FIVE_HOURS_MINS = 5 * 60;
const WEEK_MINS = 7 * 24 * 60;

export function normalizeUsage(rateLimitResponse, now = new Date()) {
  const snapshot =
    rateLimitResponse?.rateLimitsByLimitId?.codex ??
    rateLimitResponse?.rateLimits ??
    firstSnapshot(rateLimitResponse?.rateLimitsByLimitId);

  if (!snapshot) {
    throw new Error("Codex rate-limit response did not include a usable snapshot.");
  }

  const windows = [snapshot.primary, snapshot.secondary]
    .filter(Boolean)
    .map((window) => normalizeWindow(window, now));

  const fiveHour = windows.find((window) => approximately(window.windowDurationMins, FIVE_HOURS_MINS));
  const weekly = windows.find((window) => approximately(window.windowDurationMins, WEEK_MINS));

  return {
    limitId: snapshot.limitId ?? "codex",
    planType: snapshot.planType ?? null,
    fiveHour: fiveHour ?? windows[0] ?? null,
    weekly: weekly ?? windows[1] ?? null,
    windows,
  };
}

export function formatMenuTitle(usage) {
  const parts = [];
  if (usage.fiveHour) {
    parts.push(`5h ${usage.fiveHour.remainingPercent}%`);
  }
  if (usage.weekly) {
    parts.push(`7d ${usage.weekly.remainingPercent}%`);
  }
  return parts.length > 0 ? `Codex ${parts.join(" ")}` : "Codex usage";
}

export function formatTextStatus(usage) {
  const lines = [formatMenuTitle(usage)];
  if (usage.fiveHour) {
    lines.push(`5-hour remaining: ${usage.fiveHour.remainingPercent}%`);
    lines.push(`5-hour reset: ${formatReset(usage.fiveHour.resetsAt)}`);
  }
  if (usage.weekly) {
    lines.push(`Weekly remaining: ${usage.weekly.remainingPercent}%`);
    lines.push(`Weekly reset: ${formatReset(usage.weekly.resetsAt)}`);
  }
  return lines.join("\n");
}

function normalizeWindow(window, now) {
  const usedPercent = clampPercent(toNumber(window.usedPercent));
  const remainingPercent = clampPercent(100 - usedPercent);
  const resetsAt = typeof window.resetsAt === "number" ? new Date(window.resetsAt * 1000) : null;
  return {
    usedPercent,
    remainingPercent,
    windowDurationMins: toNumber(window.windowDurationMins),
    resetsAt,
    staleAt: new Date(now.getTime()),
  };
}

function firstSnapshot(snapshotsById) {
  if (!snapshotsById || typeof snapshotsById !== "object") {
    return null;
  }
  return Object.values(snapshotsById)[0] ?? null;
}

function toNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function clampPercent(value) {
  if (value === null) {
    return null;
  }
  return Math.max(0, Math.min(100, Math.round(value)));
}

function approximately(value, target) {
  return typeof value === "number" && Math.abs(value - target) <= 1;
}

function formatReset(date) {
  if (!date) {
    return "unknown";
  }
  return date.toLocaleString(undefined, { hour12: false });
}
