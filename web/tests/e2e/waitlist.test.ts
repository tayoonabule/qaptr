import { test } from "node:test";
import assert from "node:assert/strict";
import { chromium, type Browser } from "playwright";
import { startDevServer, type DevServer } from "../helpers/devServer.ts";

// These tests exercise the built site end to end via a real browser
// against the real (local) Worker + D1, covering the U21 scenarios that
// unit tests cannot: no-JS submission, duplicate idempotency, invalid
// input, and rate limiting as observed by an actual client.
//
// Requires `npm run build` to have produced `dist/` before running.

let server: DevServer;
let browser: Browser;
let nextTestIp = 30;

/**
 * Returns a fresh RFC 5737 documentation-range IP for each call. Local
 * `wrangler pages dev` does not set `cf-connecting-ip` the way production
 * Cloudflare does, so every browser-driven form submission in this file
 * shares one "unknown" rate-limit bucket unless each test context is
 * given its own synthetic client IP, matching how distinct real visitors
 * would each get their own bucket in production.
 */
function uniqueTestIp(): string {
  nextTestIp += 1;
  return `203.0.113.${nextTestIp}`;
}

test.before(async () => {
  server = await startDevServer(8799);
  browser = await chromium.launch();
});

test.after(async () => {
  await browser.close();
  await server.stop();
});

test("submitting the hero form without JavaScript reaches the confirmation page", async () => {
  const context = await browser.newContext({
    javaScriptEnabled: false,
    extraHTTPHeaders: { "cf-connecting-ip": uniqueTestIp() },
  });
  const page = await context.newPage();

  await page.goto(`${server.baseUrl}/`);
  const uniqueEmail = `no-js-${Date.now()}@example.com`;
  await page.fill("#join-hero-email", uniqueEmail);
  await Promise.all([page.waitForURL(/\/join\/thanks\/?$/, { timeout: 10_000 }), page.click('#join-hero button[type="submit"]')]);

  await assertHeadingContains(page, "on the list");
  await context.close();
});

test("an invalid email is rejected with a clear message and no crash", async () => {
  const context = await browser.newContext({
    extraHTTPHeaders: { "cf-connecting-ip": uniqueTestIp() },
  });
  const page = await context.newPage();

  await page.goto(`${server.baseUrl}/`);
  // "person@localhost" passes the browser's native `type="email"`
  // constraint validation (no TLD is required by the HTML5 spec), so this
  // exercises the *server-side* rejection path (missing top-level domain)
  // rather than being blocked client-side before the form ever submits.
  await page.fill("#join-hero-email", "person@localhost");
  await Promise.all([
    page.waitForURL(/\/join\/invalid\/?$/, { timeout: 10_000 }),
    page.click('#join-hero button[type="submit"]'),
  ]);

  await assertHeadingContains(page, "valid email address");
  await context.close();
});

test("submitting the same email twice is idempotent, not an error", async () => {
  const context = await browser.newContext({
    extraHTTPHeaders: { "cf-connecting-ip": uniqueTestIp() },
  });
  const page = await context.newPage();
  const email = `dup-${Date.now()}@example.com`;

  await page.goto(`${server.baseUrl}/`);
  await page.fill("#join-hero-email", email);
  await Promise.all([page.waitForURL(/\/join\/thanks\/?$/, { timeout: 10_000 }), page.click('#join-hero button[type="submit"]')]);

  await page.goto(`${server.baseUrl}/`);
  await page.fill("#join-hero-email", email);
  await Promise.all([page.waitForURL(/\/join\/thanks\/?$/, { timeout: 10_000 }), page.click('#join-hero button[type="submit"]')]);

  await assertHeadingContains(page, "on the list");
  await context.close();
});

test("the footer form posts independently of the hero form", async () => {
  const context = await browser.newContext({
    extraHTTPHeaders: { "cf-connecting-ip": uniqueTestIp() },
  });
  const page = await context.newPage();

  await page.goto(`${server.baseUrl}/`);
  const uniqueEmail = `footer-${Date.now()}@example.com`;
  await page.fill("#join-footer-email", uniqueEmail);
  await Promise.all([
    page.waitForURL(/\/join\/thanks\/?$/, { timeout: 10_000 }),
    page.click('#join-footer button[type="submit"]'),
  ]);

  await assertHeadingContains(page, "on the list");
  await context.close();
});

test("rate limiting blocks a burst of submissions from one client", async () => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(`${server.baseUrl}/`);

  const testIp = uniqueTestIp();

  let sawRateLimited = false;
  for (let i = 0; i < 15; i += 1) {
    const response = await page.request.post(`${server.baseUrl}/api/waitlist`, {
      headers: { "cf-connecting-ip": testIp },
      form: { email: `burst-${i}-${Date.now()}@example.com`, source: "hero" },
      maxRedirects: 0,
    });
    const location = response.headers()["location"] ?? "";
    if (location.includes("/join/rate-limited")) {
      sawRateLimited = true;
      break;
    }
  }

  assert.ok(sawRateLimited, "expected a burst of 15 submissions to trigger rate limiting");
  await context.close();
});

test("a normal single visitor is not rate limited", async () => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(`${server.baseUrl}/`);

  const response = await page.request.post(`${server.baseUrl}/api/waitlist`, {
    headers: { "cf-connecting-ip": uniqueTestIp() },
    form: { email: `single-${Date.now()}@example.com`, source: "hero" },
    maxRedirects: 0,
  });

  assert.equal(response.status(), 303);
  assert.ok(response.headers()["location"]?.includes("/join/thanks"));
  await context.close();
});

test("keyboard-only navigation can reach and submit the hero form", async () => {
  const context = await browser.newContext({
    extraHTTPHeaders: { "cf-connecting-ip": uniqueTestIp() },
  });
  const page = await context.newPage();
  await page.goto(`${server.baseUrl}/`);

  // Skip link is the very first focusable element.
  await page.keyboard.press("Tab");
  const skipLinkFocused = await page.evaluate(
    () => document.activeElement?.classList.contains("skip-link") ?? false,
  );
  assert.ok(skipLinkFocused, "skip link should be the first tab stop");

  const email = `keyboard-${Date.now()}@example.com`;
  await page.locator("#join-hero-email").focus();
  await page.keyboard.type(email);
  await Promise.all([page.waitForURL(/\/join\/thanks\/?$/, { timeout: 10_000 }), page.keyboard.press("Enter")]);

  await assertHeadingContains(page, "on the list");
  await context.close();
});

async function assertHeadingContains(page: import("playwright").Page, text: string) {
  const heading = page.locator("h1");
  await heading.waitFor({ state: "visible" });
  const content = (await heading.textContent()) ?? "";
  assert.ok(
    content.toLowerCase().includes(text.toLowerCase()),
    `expected heading "${content}" to contain "${text}"`,
  );
}
