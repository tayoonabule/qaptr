import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";

// Static-first Astro site deployed to Cloudflare Pages, with one
// server-rendered endpoint (src/pages/api/waitlist.ts) for the waitlist
// form. Per KTD12: static Astro + one Worker (Pages Function) endpoint +
// D1, no third-party form service, no client framework runtime.
//
// "hybrid" output means every page is static by default; only routes that
// opt in with `export const prerender = false` (the waitlist API route)
// run server-side. This keeps the landing page a plain static asset.
export default defineConfig({
  output: "hybrid",
  adapter: cloudflare({
    imageService: "compile",
    platformProxy: {
      enabled: true,
    },
  }),
  site: "https://qaptr.app",
  server: { port: 4321 },
});
