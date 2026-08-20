import Database from "better-sqlite3";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import type { RateLimitDb } from "./ratelimit";

let sharedDatabase: RateLimitDb | null = null;

export async function getWaitlistDb(): Promise<RateLimitDb | null> {
  if (sharedDatabase) return sharedDatabase;

  const databasePath = process.env.WAITLIST_DB_PATH;
  if (!databasePath) return null;

  mkdirSync(dirname(databasePath), { recursive: true });
  const database = new Database(databasePath, { timeout: 5_000 });
  database.pragma("journal_mode = WAL");
  database.pragma("foreign_keys = ON");
  database.exec(readFileSync(resolve(process.cwd(), "migrations/0001_waitlist.sql"), "utf8"));

  sharedDatabase = {
    prepare(query: string) {
      const statement = database.prepare(query);
      return {
        bind(...values: unknown[]) {
          return {
            async first<T = unknown>(): Promise<T | null> {
              return (statement.get(...values) as T | undefined) ?? null;
            },
            async run(): Promise<unknown> {
              return statement.run(...values);
            },
          };
        },
      };
    },
  };

  return sharedDatabase;
}
