import test from "node:test";
import assert from "node:assert/strict";
import Database from "better-sqlite3";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { startNodeServer, type NodeServer } from "../helpers/nodeServer.ts";

let directory: string;
let databasePath: string;
let server: NodeServer;
const port = 8899;

test.before(async () => {
  directory = await mkdtemp(path.join(tmpdir(), "qaptr-dokploy-"));
  databasePath = path.join(directory, "waitlist.sqlite");
  server = await startNodeServer(databasePath, port);
});

test.after(async () => {
  await server.stop();
  await rm(directory, { recursive: true, force: true });
});

test("Dokploy runtime serves the site and persists an idempotent signup", async () => {
  const home = await fetch(server.baseUrl);
  assert.equal(home.status, 200);
  assert.match(await home.text(), /Remember what you did without stopping to document it/i);

  const email = `dokploy-${Date.now()}@example.com`;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const response = await submit(email, `203.0.113.${50 + attempt}`);
    assert.equal(response.status, 303);
    assert.match(response.headers.get("location") ?? "", /\/join\/thanks\/?$/);
  }

  const database = new Database(databasePath, { readonly: true });
  const row = database
    .prepare("SELECT email, source FROM waitlist WHERE email = ?")
    .get(email) as { email: string; source: string } | undefined;
  const count = database
    .prepare("SELECT COUNT(*) AS count FROM waitlist WHERE email = ?")
    .get(email) as { count: number };
  database.close();

  assert.deepEqual(row, { email, source: "hero" });
  assert.equal(count.count, 1, "duplicate signups must remain idempotent");
});

test("Dokploy runtime applies the same per-client rate limit", async () => {
  const clientIp = "203.0.113.99";
  let limited = false;
  for (let index = 0; index < 15; index += 1) {
    const response = await submit(`burst-${index}-${Date.now()}@example.com`, clientIp);
    if ((response.headers.get("location") ?? "").includes("/join/rate-limited")) {
      limited = true;
      break;
    }
  }
  assert.equal(limited, true);
});

async function submit(email: string, clientIp: string): Promise<Response> {
  return fetch(`${server.baseUrl}/api/waitlist`, {
    method: "POST",
    redirect: "manual",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      origin: server.baseUrl,
      "x-forwarded-for": clientIp,
    },
    body: new URLSearchParams({ email, source: "hero" }),
  });
}
