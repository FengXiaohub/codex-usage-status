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
    label: "C",
    title: "Codex",
    planType: snapshot.planType ?? null,
    fiveHour: fiveHour ?? windows[0] ?? null,
    weekly: weekly ?? windows[1] ?? null,
    windows,
  };
}

export function normalizeAntigravityUsage(agyResponse, now = new Date()) {
  const groups = agyResponse?.response?.groups ?? agyResponse?.command?.data?.groups;
  if (!Array.isArray(groups) || groups.length === 0) {
    throw new Error("Antigravity usage response did not include quota groups.");
  }

  const geminiGroup =
    groups.find((group) => /gemini/i.test(group?.displayName ?? group?.name ?? "")) ??
    groups.find((group) => group?.buckets?.some((bucket) => /^gemini/i.test(bucket?.bucketId ?? bucket?.id ?? "")));

  const claudeGptGroup =
    groups.find((group) => /claude|gpt/i.test(group?.displayName ?? group?.name ?? "")) ??
    groups.find((group) => group?.buckets?.some((bucket) => /^3p/i.test(bucket?.bucketId ?? bucket?.id ?? "")));

  return {
    gemini: geminiGroup ? normalizeAntigravityGroup(geminiGroup, "antigravity-gemini", "G", "Antigravity Gemini", now) : null,
    claudeGpt: claudeGptGroup ? normalizeAntigravityGroup(claudeGptGroup, "antigravity-3p", "A", "Antigravity Claude & GPT", now) : null,
  };
}

function normalizeAntigravityGroup(group, limitId, label, title, now) {
  const buckets = Array.isArray(group.buckets) ? group.buckets : [];
  const fiveHourBucket = buckets.find((bucket) => bucket.window === "5h" || /5h|five hour/i.test(bucket.bucketId ?? bucket.id ?? bucket.displayName ?? bucket.name ?? ""));
  const weeklyBucket = buckets.find((bucket) => bucket.window === "weekly" || /weekly/i.test(bucket.bucketId ?? bucket.id ?? bucket.displayName ?? bucket.name ?? ""));

  const fiveHour = fiveHourBucket ? normalizeAntigravityBucket(fiveHourBucket, FIVE_HOURS_MINS, now) : null;
  const weekly = weeklyBucket ? normalizeAntigravityBucket(weeklyBucket, WEEK_MINS, now) : null;

  return {
    limitId,
    label,
    title,
    groupName: group.displayName ?? group.name ?? title,
    fiveHour,
    weekly,
    windows: [fiveHour, weekly].filter(Boolean),
  };
}

function normalizeAntigravityBucket(bucket, durationMins, now) {
  const rawFraction = typeof bucket.remainingFraction === "number"
    ? bucket.remainingFraction
    : bucket.remaining_fraction;
  const fraction = typeof rawFraction === "number" && Number.isFinite(rawFraction)
    ? rawFraction
    : null;
  const remainingPercent = fraction === null ? null : clampPercent(fraction * 100);
  const usedPercent = remainingPercent === null ? null : clampPercent(100 - remainingPercent);
  const rawReset = bucket.resetTime ?? bucket.reset_time;
  const parsedDate = rawReset ? new Date(rawReset) : null;
  const resetsAt = parsedDate && !Number.isNaN(parsedDate.getTime()) ? parsedDate : null;

  return {
    usedPercent,
    remainingPercent,
    windowDurationMins: durationMins,
    resetsAt,
    staleAt: new Date(now.getTime()),
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
  const prefix = usage.title ?? "Codex";
  return parts.length > 0 ? `${prefix} ${parts.join(" ")}` : `${prefix} usage`;
}

export function formatCombinedTextStatus(combined) {
  const sections = [];
  if (combined.codex) {
    sections.push(formatTextStatus(combined.codex));
  }
  if (combined.gemini) {
    sections.push(formatTextStatus(combined.gemini));
  }
  if (combined.claudeGpt) {
    sections.push(formatTextStatus(combined.claudeGpt));
  }
  return sections.join("\n\n");
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
