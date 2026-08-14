// Runs an axe-core accessibility scan against the built landing page and
// its confirmation pages, served by the real local Worker. Fails the
// process (non-zero exit) if any violation is found, matching the "Axe
// scan reports no violations" U21 test scenario.

import { chromium } from "playwright";
import AxeBuilder from "@axe-core/playwright";
import { startDevServer } from "../helpers/devServer.ts";

const PAGES_TO_SCAN = ["/", "/join/thanks/", "/join/invalid/", "/join/rate-limited/", "/join/error/"];

async function main() {
  const server = await startDevServer(8801);
  const browser = await chromium.launch();
  let hadViolations = false;

  try {
    for (const path of PAGES_TO_SCAN) {
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.goto(`${server.baseUrl}${path}`, { waitUntil: "networkidle" });

      const results = await new AxeBuilder({ page }).analyze();

      if (results.violations.length > 0) {
        hadViolations = true;
        console.error(`\n✗ Accessibility violations on ${path}:`);
        for (const violation of results.violations) {
          console.error(`  [${violation.impact}] ${violation.id}: ${violation.description}`);
          for (const node of violation.nodes) {
            console.error(`    - ${node.target.join(", ")}`);
          }
        }
      } else {
        console.log(`✓ ${path}: no violations`);
      }

      await context.close();
    }
  } finally {
    await browser.close();
    await server.stop();
  }

  if (hadViolations) {
    console.error("\nAccessibility check failed.");
    process.exit(1);
  }

  console.log("\nAll pages passed the accessibility scan.");
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
