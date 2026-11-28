import { spawn } from "node:child_process";
import { accessSync, constants, mkdirSync, readdirSync, readFileSync, statSync } from "node:fs";
import http from "node:http";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

function isolatedWorkingDir() {
  const dir = join(tmpdir(), "codex-usage-status-empty-cwd");
  try {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
  } catch {
    // ignore
  }
  return dir;
}

const DEFAULT_CODEX_PATHS = [
  "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
  "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
  "/Applications/ChatGPT.app/Contents/Resources/codex",
  "/Applications/Codex.app/Contents/Resources/codex",
];

const DEFAULT_AGY_PATHS = [
  join(homedir(), ".local/bin/agy"),
  "/usr/local/bin/agy",
  "/opt/homebrew/bin/agy",
];

const DEFAULT_TIMEOUT_MS = 20_000;

const PACKAGE_VERSION = (() => {
  try {
    return JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).version ?? "dev";
  } catch {
    return "dev";
  }
})();

function resolveExecutable(envValue, candidates) {
  if (envValue) {
    return envValue;
  }
  for (const candidate of candidates) {
    try {
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      // continue
    }
  }
  return candidates[0];
}

export class AppServerClient {
  constructor(options = {}) {
    this.codexBin = resolveExecutable(options.codexBin ?? process.env.CODEX_BIN, DEFAULT_CODEX_PATHS);
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.nextId = 1;
    this.pending = new Map();
    this.stderrTail = "";
  }

  async start() {
    if (this.child) {
      return;
    }

    this.child = spawn(this.codexBin, ["app-server", "--listen", "stdio://"], {
      cwd: isolatedWorkingDir(),
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env },
    });

    this.child.stderr.setEncoding("utf8");
    this.child.stderr.on("data", (chunk) => {
      this.stderrTail = redactSensitive(`${this.stderrTail}${chunk}`).slice(-4000);
    });

    this.child.on("error", (error) => {
      for (const { reject, timeout } of this.pending.values()) {
        clearTimeout(timeout);
        reject(error);
      }
      this.pending.clear();
      this.child = undefined;
    });

    this.child.on("exit", () => {
      for (const { reject, timeout } of this.pending.values()) {
        clearTimeout(timeout);
        reject(new Error("Codex app-server exited before responding."));
      }
      this.pending.clear();
    });

    const lines = createInterface({ input: this.child.stdout });
    lines.on("line", (line) => {
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }

      if (message.id === undefined) {
        return;
      }

      const pending = this.pending.get(String(message.id));
      if (!pending) {
        return;
      }

      this.pending.delete(String(message.id));
      clearTimeout(pending.timeout);

      if (message.error) {
        pending.reject(new Error(JSON.stringify(message.error)));
      } else {
        pending.resolve(message.result ?? message);
      }
    });
  }

  async initialize() {
    await this.request("initialize", {
      clientInfo: {
        name: "codex_usage_status",
        title: "Codex Usage Status",
        version: PACKAGE_VERSION,
      },
      capabilities: {
        experimentalApi: true,
      },
    });
    this.notify("initialized");
  }

  async readRateLimits() {
    return this.request("account/rateLimits/read");
  }

  async request(method, params) {
    await this.start();

    const id = this.nextId++;
    const payload = params === undefined ? { method, id } : { method, id, params };
    const line = `${JSON.stringify(payload)}\n`;

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(String(id));
        reject(new Error(`Timed out waiting for ${method}. ${this.stderrTail}`.trim()));
      }, this.timeoutMs);

      this.pending.set(String(id), { resolve, reject, timeout });
      this.child.stdin.write(line, (error) => {
        if (error) {
          clearTimeout(timeout);
          this.pending.delete(String(id));
          reject(error);
        }
      });
    });
  }

  notify(method, params) {
    if (!this.child) {
      throw new Error("Codex app-server is not running.");
    }

    const payload = params === undefined ? { method } : { method, params };
    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  async close() {
    if (!this.child) {
      return;
    }

    this.child.stdin.end();
    await new Promise((resolve) => {
      const timeout = setTimeout(() => {
        this.child.kill("SIGTERM");
        resolve();
      }, 1000);
      this.child.once("exit", () => {
        clearTimeout(timeout);
        resolve();
      });
    });
    this.child = undefined;
  }
}

export async function readCodexRateLimits(options = {}) {
  const client = new AppServerClient(options);
  try {
    await client.initialize();
    return await client.readRateLimits();
  } finally {
    await client.close();
  }
}

function isProcessAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function discoverLiveAntigravityDaemons() {
  const daemonDir = join(homedir(), ".gemini/antigravity/daemon");
  let entries;
  try {
    entries = readdirSync(daemonDir);
  } catch {
    return [];
  }

  const candidates = entries
    .filter((name) => name.startsWith("hub_") && name.endsWith(".json"))
    .map((name) => {
      const fullPath = join(daemonDir, name);
      let mtimeMs = 0;
      try {
        mtimeMs = statSync(fullPath).mtimeMs;
      } catch {
        // ignore
      }
      return { fullPath, mtimeMs };
    })
    .sort((a, b) => b.mtimeMs - a.mtimeMs);

  const live = [];
  for (const { fullPath } of candidates) {
    try {
      const parsed = JSON.parse(readFileSync(fullPath, "utf8"));
      if (
        isProcessAlive(parsed?.pid) &&
        Number.isInteger(parsed?.httpPort) &&
        parsed.httpPort > 0 &&
        parsed.httpPort <= 65535 &&
        typeof parsed?.csrfToken === "string" &&
        parsed.csrfToken.length > 0
      ) {
        live.push({ port: parsed.httpPort, csrfToken: parsed.csrfToken });
      }
    } catch {
      // skip malformed discovery file
    }
  }
  return live;
}

export async function readAntigravityQuota(options = {}) {
  const timeoutMs = options.timeoutMs ?? 10_000;
  const daemons = discoverLiveAntigravityDaemons();
  if (daemons.length === 0) {
    throw new Error("Antigravity desktop app is not running.");
  }

  let lastError = new Error("Antigravity local daemon did not return quota data.");
  for (const daemon of daemons) {
    try {
      const payload = await new Promise((resolve, reject) => {
        const req = http.request(
          {
            hostname: "127.0.0.1",
            port: daemon.port,
            path: "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Connect-Protocol-Version": "1",
              "x-antigravity-csrf-token": daemon.csrfToken,
              "Content-Length": 2,
            },
            timeout: timeoutMs,
          },
          (res) => {
            let body = "";
            res.setEncoding("utf8");
            res.on("data", (chunk) => {
              body += chunk;
            });
            res.on("end", () => {
              if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
                reject(new Error(`Antigravity local daemon returned HTTP ${res.statusCode ?? "unknown"}`));
                return;
              }
              try {
                resolve(JSON.parse(body));
              } catch (parseError) {
                reject(parseError);
              }
            });
          },
        );
        req.on("timeout", () => {
          req.destroy(new Error("Timed out querying Antigravity local daemon."));
        });
        req.on("error", reject);
        req.write("{}");
        req.end();
      });
      return payload;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

export function redactSensitive(value) {
  return value
    .replace(/[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/g, "[redacted-jwt]")
    .replace(/((?:token|cookie|session|authorization|api[_-]?key)\s*[:=]\s*)[^\r\n]+/gi, "$1[redacted]");
}
