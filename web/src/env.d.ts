/// <reference path="../.astro/types.d.ts" />
/// <reference types="astro/client" />
/// <reference types="@astrojs/cloudflare" />

type Runtime = import("@astrojs/cloudflare").Runtime<{
  WAITLIST_DB: import("@cloudflare/workers-types").D1Database;
}>;

declare namespace App {
  interface Locals extends Runtime {}
}
