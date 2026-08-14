import { test } from "node:test";
import assert from "node:assert/strict";
import { checkRateLimit, hashClientKey, type RateLimitDb } from "../../src/lib/ratelimit.ts";

/**
 * A tiny in-memory stand-in for D1Database that implements exactly the
 * subset of the API `checkRateLimit` uses: prepare().bind().first()/run().
 * This exercises the real SQL statements against sql.js-free logic by
 * hand-implementing the same semantics the real SQLite schema enforces
 * (single row per client_key, upsert on conflict).
 */
function createFakeDb(): RateLimitDb {
  const rows = new Map<string, { window_start: string; request_count: number }>();

  return {
    prepare(query: string) {
      return {
        bind(...values: unknown[]) {
          return {
            async first<T>(): Promise<T | null> {
              if (query.startsWith("SELECT")) {
                const [clientKey] = values as [string];
                const row = rows.get(clientKey);
                // Return a fresh copy, matching how a real D1 driver
                // deserializes each row rather than handing back a live
                // reference into internal state.
                return (row ? { ...row } : null) as T | null;
              }
              throw new Error(`Unexpected first() call for query: ${query}`);
            },
            async run(): Promise<unknown> {
              if (query.startsWith("INSERT")) {
                const [clientKey, windowStart] = values as [string, string];
                rows.set(clientKey, { window_start: windowStart, request_count: 1 });
                return { success: true };
              }
              if (query.startsWith("UPDATE")) {
                const [clientKey] = values as [string];
                const row = rows.get(clientKey);
                if (row) row.request_count += 1;
                return { success: true };
              }
              throw new Error(`Unexpected run() call for query: ${query}`);
            },
          };
        },
      };
    },
  };
}

test("hashClientKey produces a stable, non-reversible-looking digest", async () => {
  const a = await hashClientKey("203.0.113.5");
  const b = await hashClientKey("203.0.113.5");
  const c = await hashClientKey("203.0.113.6");

  assert.equal(a, b, "same input hashes identically");
  assert.notEqual(a, c, "different inputs hash differently");
  assert.equal(a.length, 64, "sha-256 hex digest is 64 characters");
  assert.ok(!a.includes("203.0.113"), "hash does not contain the raw IP");
});

test("allows requests under the limit and denies once the limit is reached", async () => {
  const db = createFakeDb();
  const key = await hashClientKey("198.51.100.7");
  const options = { limit: 3, windowSeconds: 60 };

  const first = await checkRateLimit(db, key, options);
  assert.equal(first.allowed, true);
  assert.equal(first.remaining, 2);

  const second = await checkRateLimit(db, key, options);
  assert.equal(second.allowed, true);
  assert.equal(second.remaining, 1);

  const third = await checkRateLimit(db, key, options);
  assert.equal(third.allowed, true);
  assert.equal(third.remaining, 0);

  const fourth = await checkRateLimit(db, key, options);
  assert.equal(fourth.allowed, false, "fourth request in the same window is denied");
});

test("does not cross-contaminate limits between different client keys", async () => {
  const db = createFakeDb();
  const options = { limit: 1, windowSeconds: 60 };
  const keyA = await hashClientKey("10.0.0.1");
  const keyB = await hashClientKey("10.0.0.2");

  const resultA = await checkRateLimit(db, keyA, options);
  assert.equal(resultA.allowed, true);

  const resultB = await checkRateLimit(db, keyB, options);
  assert.equal(resultB.allowed, true, "a different client key has its own budget");

  const resultADenied = await checkRateLimit(db, keyA, options);
  assert.equal(resultADenied.allowed, false, "client A is now over its own limit");
});
