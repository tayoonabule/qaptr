import { spawn, spawnSync, type ChildProcessByStdio } from "node:child_process";
import type { Readable } from "node:stream";
import { setTimeout as delay } from "node:timers/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = path.resolve(fileURLToPath(import.meta.url), "../../..");

export interface DevServer {
  baseUrl: string;
  stop(): Promise<void>;
}

/**
 * Boots `wrangler dev` against Astro's generated Worker configuration on a
 * fixed test port, waiting until it accepts connections. Used by both the e2e
 * and accessibility suites so both exercise the real Worker code path
 * (validation, rate limiting, D1) rather than a mocked server.
 */
export async function startDevServer(port = 8799): Promise<DevServer> {
  const migration = spawnSync(
    "npx",
    [
      "wrangler",
      "d1",
      "migrations",
      "apply",
      "qaptr-waitlist",
      "--local",
      "--persist-to",
      ".wrangler/state",
    ],
    {
      cwd: webRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  if (migration.status !== 0) {
    throw new Error(
      `wrangler could not initialize the local D1 schema.\n${migration.stdout}${migration.stderr}`,
    );
  }

  const child: ChildProcessByStdio<null, Readable, Readable> = spawn(
    "npx",
    [
      "wrangler",
      "dev",
      "--config",
      "dist/server/wrangler.json",
      "--persist-to",
      ".wrangler/state",
      "--port",
      String(port),
      "--compatibility-date=2026-08-01",
    ],
    {
      cwd: webRoot,
      stdio: ["ignore", "pipe", "pipe"],
      // Run in its own process group so `stop()` can kill the whole tree
      // (npx -> wrangler -> the underlying workerd runtime), not just the
      // immediate child. Killing only the top process otherwise leaves
      // workerd running and holding the port/fds open, which hangs the
      // Node test runner's own shutdown.
      detached: true,
    },
  );

  let ready = false;
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk.toString();
    if (output.includes("Ready on")) ready = true;
  });
  child.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });

  const baseUrl = `http://localhost:${port}`;

  const deadline = Date.now() + 30_000;
  while (!ready && Date.now() < deadline) {
    await delay(200);
  }
  if (!ready) {
    if (typeof child.pid === "number") {
      try {
        process.kill(-child.pid, "SIGTERM");
      } catch {
        child.kill("SIGTERM");
      }
    } else {
      child.kill("SIGTERM");
    }
    throw new Error(`wrangler dev did not become ready in time.\nOutput:\n${output}`);
  }

  // Give the local Miniflare runtime a brief extra moment to finish
  // binding D1/routes after printing "Ready on", to avoid flaky first
  // requests in CI.
  await delay(300);

  return {
    baseUrl,
    async stop() {
      if (typeof child.pid === "number") {
        try {
          // Negative pid signals kill(2) to target the whole process
          // group created by `detached: true` above, so npx, wrangler,
          // and workerd all receive the signal instead of just npx.
          process.kill(-child.pid, "SIGTERM");
        } catch {
          // Process group may already be gone; fall back to a direct kill.
          child.kill("SIGTERM");
        }
      } else {
        child.kill("SIGTERM");
      }
      await delay(300);
    },
  };
}
