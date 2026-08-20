import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import node from "@astrojs/node";
import { fileURLToPath } from "node:url";

const deploymentTarget = process.env.QAPTR_DEPLOY_TARGET ?? "cloudflare";
const isDokploy = deploymentTarget === "dokploy";

// Static-first Astro site with one server-rendered waitlist endpoint. The
// default adapter targets Cloudflare Workers + D1, while
// `QAPTR_DEPLOY_TARGET=dokploy` selects a standalone Node server + SQLite.
// Both modes keep the landing page as plain prerendered assets with no client
// framework runtime or third-party form service.
//
// Astro 7's static output prerenders pages by default while routes that export
// `prerender = false` run server-side through the selected adapter. This keeps
// the landing page static and the waitlist endpoint dynamic.
export default defineConfig({
  output: "static",
  adapter: isDokploy
    ? node({ mode: "standalone" })
    : cloudflare({
        imageService: "compile",
        platformProxy: {
          enabled: true,
        },
      }),
  site: process.env.PUBLIC_SITE_URL ?? "https://qaptr.headless.com",
  server: { port: 4321, host: true },
  vite: {
    resolve: {
      alias: {
        "@waitlist-db": fileURLToPath(
          new URL(
            isDokploy
              ? "./src/lib/waitlist-db-node.ts"
              : "./src/lib/waitlist-db-cloudflare.ts",
            import.meta.url,
          ),
        ),
      },
    },
  },
});
