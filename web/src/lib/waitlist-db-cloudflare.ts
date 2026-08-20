import { env } from "cloudflare:workers";
import type { D1Database } from "@cloudflare/workers-types";
import type { RateLimitDb } from "./ratelimit";

interface CloudflareEnv {
  WAITLIST_DB?: D1Database;
}

export async function getWaitlistDb(_locals: unknown): Promise<RateLimitDb | null> {
  return ((env as CloudflareEnv).WAITLIST_DB as RateLimitDb | undefined) ?? null;
}
