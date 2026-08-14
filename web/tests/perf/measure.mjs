// Measures Largest Contentful Paint and total transferred bytes on a
// throttled mobile profile, matching the Measurement protocol's website
// budgets: LCP < 1800ms, transferred bytes < 250 KB. Boots its own local
// server so it can run standalone in CI or locally with `npm run
// test:perf`.

import { chromium } from "playwright";
import { startDevServer } from "../helpers/devServer.ts";

async function main() {
  const server = await startDevServer(8802);
  const browser = await chromium.launch();

  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 }, // iPhone 12-class viewport
      userAgent:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    });

    const page = await context.newPage();
    const client = await context.newCDPSession(page);

    // Emulate a throttled "Slow 4G"-ish mobile connection and mid-tier
    // mobile CPU, per Lighthouse's mobile throttling defaults.
    await client.send("Network.enable");
    await client.send("Network.emulateNetworkConditions", {
      offline: false,
      downloadThroughput: (1.6 * 1024 * 1024) / 8, // 1.6 Mbps
      uploadThroughput: (0.75 * 1024 * 1024) / 8, // 0.75 Mbps
      latency: 150, // ms round trip
    });
    await client.send("Emulation.setCPUThrottlingRate", { rate: 4 });

    let totalBytes = 0;
    page.on("response", async (response) => {
      try {
        const body = await response.body();
        totalBytes += body.length;
      } catch {
        // Some responses (e.g. redirects, opaque) have no body to read.
      }
    });

    await page.goto(`${server.baseUrl}/`, { waitUntil: "load" });

    const lcp = await page.evaluate(
      () =>
        new Promise((resolve) => {
          let value = 0;
          new PerformanceObserver((list) => {
            const entries = list.getEntries();
            const last = entries[entries.length - 1];
            if (last) value = last.startTime;
          }).observe({ type: "largest-contentful-paint", buffered: true });
          setTimeout(() => resolve(value), 200);
        }),
    );

    console.log(`LCP: ${lcp.toFixed(1)} ms (budget: < 1800 ms)`);
    console.log(`Transferred bytes: ${totalBytes} (budget: < 250000 bytes)`);

    const budgetsMet = lcp < 1800 && totalBytes < 250_000;
    if (!budgetsMet) {
      console.error("PERFORMANCE BUDGET EXCEEDED");
      process.exitCode = 1;
      return;
    }
    console.log("Performance budgets met.");
  } finally {
    await browser.close();
    await server.stop();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
