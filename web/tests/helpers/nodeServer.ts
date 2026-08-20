import { spawn, type ChildProcess } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

export interface NodeServer {
  baseUrl: string;
  stop(): Promise<void>;
}

export async function startNodeServer(databasePath: string, port: number): Promise<NodeServer> {
  let output = "";
  const child = spawn(process.execPath, ["dist/server/entry.mjs"], {
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(port),
      WAITLIST_DB_PATH: databasePath,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stdout?.on("data", (chunk) => {
    output += chunk.toString();
  });
  child.stderr?.on("data", (chunk) => {
    output += chunk.toString();
  });

  const baseUrl = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`Dokploy server exited before becoming ready.\n${output}`);
    }
    try {
      const response = await fetch(baseUrl);
      if (response.ok) break;
    } catch {
      // The server has not bound its port yet.
    }
    await delay(100);
  }

  try {
    const response = await fetch(baseUrl);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
  } catch (error) {
    child.kill("SIGTERM");
    throw new Error(`Dokploy server did not become ready: ${String(error)}\n${output}`);
  }

  return {
    baseUrl,
    async stop() {
      await stopChild(child);
    },
  };
}

async function stopChild(child: ChildProcess): Promise<void> {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  const deadline = Date.now() + 5_000;
  while (child.exitCode === null && Date.now() < deadline) {
    await delay(50);
  }
  if (child.exitCode === null) child.kill("SIGKILL");
}
