// Fixed-window rate limiting backed by the D1 `rate_limit_bucket` table.
// Keys are hashed client identifiers (never a raw IP), so the table
// carries no personal data on its own even though it is derived from one.

export interface RateLimitDb {
  prepare(query: string): {
    bind(...values: unknown[]): {
      first<T = unknown>(): Promise<T | null>;
      run(): Promise<unknown>;
    };
  };
}

export interface RateLimitOptions {
  /** Maximum requests allowed inside one window. */
  limit: number;
  /** Window length in seconds. */
  windowSeconds: number;
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
}

/**
 * Hashes an IP (or any client identifier) with SHA-256 so the stored key
 * cannot be reversed into the original address. Uses the Web Crypto API,
 * which is available in both the Cloudflare Workers runtime and Node's
 * test runner (via `node --test`), so this function is exercised by the
 * same code path in unit tests and in production.
 */
export async function hashClientKey(rawKey: string): Promise<string> {
  const encoded = new TextEncoder().encode(rawKey);
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Applies a fixed-window rate limit for `clientKey`. Idempotent under
 * concurrent access is not guaranteed at the SQL level (D1 has no
 * cross-statement transaction here), but the window size (60s) and the
 * generous per-window limit make double-counting from a race harmless for
 * this endpoint's purpose: keeping a single client from hammering the
 * form, not perfectly metering requests.
 */
export async function checkRateLimit(
  db: RateLimitDb,
  clientKey: string,
  options: RateLimitOptions,
): Promise<RateLimitResult> {
  const now = new Date();
  const windowStart = new Date(
    Math.floor(now.getTime() / (options.windowSeconds * 1000)) * options.windowSeconds * 1000,
  ).toISOString();

  const existing = await db
    .prepare("SELECT window_start, request_count FROM rate_limit_bucket WHERE client_key = ?")
    .bind(clientKey)
    .first<{ window_start: string; request_count: number }>();

  if (!existing || existing.window_start !== windowStart) {
    await db
      .prepare(
        `INSERT INTO rate_limit_bucket (client_key, window_start, request_count)
         VALUES (?, ?, 1)
         ON CONFLICT(client_key) DO UPDATE SET window_start = excluded.window_start, request_count = 1`,
      )
      .bind(clientKey, windowStart)
      .run();
    return { allowed: true, remaining: options.limit - 1 };
  }

  if (existing.request_count >= options.limit) {
    return { allowed: false, remaining: 0 };
  }

  // Snapshot the pre-increment count before the update. Reading
  // `existing.request_count` again after the `await` below would be
  // fragile: a driver that returns a live row reference (rather than a
  // fresh copy) could have already mutated it by the time this function
  // reads it again.
  const countBeforeIncrement = existing.request_count;

  await db
    .prepare(
      "UPDATE rate_limit_bucket SET request_count = request_count + 1 WHERE client_key = ?",
    )
    .bind(clientKey)
    .run();

  return { allowed: true, remaining: options.limit - countBeforeIncrement - 1 };
}
