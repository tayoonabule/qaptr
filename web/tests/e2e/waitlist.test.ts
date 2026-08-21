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
 * `wrangler dev` does not set `cf-connecting-ip` the way production
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
  const passages = page.locator(".passage");
  assert.equal(await passages.count(), 3, "home should retain all three explanatory passages");
  for (let index = 0; index < 3; index += 1) {
    assert.ok(await passages.nth(index).isVisible(), `passage ${index + 1} should be readable without JavaScript`);
  }
  const uniqueEmail = `no-js-${Date.now()}@example.com`;
  await page.fill("#join-hero-email", uniqueEmail);
  await Promise.all([page.waitForURL(/\/join\/thanks\/?$/, { timeout: 10_000 }), page.click('#join-hero button[type="submit"]')]);

  await assertHeadingContains(page, "on the list");
  await context.close();
});

test("the five-card surface stays separated across responsive breakpoints", async () => {
  const context = await browser.newContext();
  const page = await context.newPage();

  for (const width of [320, 640, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`${server.baseUrl}/`);

    const result = await page.evaluate(() => {
      const cards = [...document.querySelectorAll<HTMLElement>(".product-bento__intro, .product-card")];
      const rects = cards.map((card) => {
        const rect = card.getBoundingClientRect();
        return { top: rect.top + window.scrollY, left: rect.left, right: rect.right, bottom: rect.bottom + window.scrollY };
      });
      return {
        cardCount: cards.length,
        hasHorizontalOverflow: document.documentElement.scrollWidth > window.innerWidth + 1,
        ordered: rects.every((rect, index) => index === 0 || rect.top >= rects[index - 1].top - 1),
        separated: rects.slice(1).every(
          (rect, index) =>
            rect.top >= rects[index].bottom - 1 ||
            rect.left >= rects[index].right - 1 ||
            rects[index].left >= rect.right - 1,
        ),
      };
    });

    assert.deepEqual(result, {
      cardCount: 5,
      hasHorizontalOverflow: false,
      ordered: true,
      separated: true,
    }, `responsive card layout should remain stable at ${width}px`);
  }

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

  await assertHeadingContains(page, "does not look right");
  const retryField = page.locator("#retry-waitlist-email");
  await retryField.waitFor({ state: "visible" });
  assert.equal(
    await page.evaluate(() => document.activeElement?.id),
    "retry-waitlist-email",
    "invalid submissions should return focus to the recovery field",
  );
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

test("cross-site waitlist submissions are rejected", async () => {
  const context = await browser.newContext();
  const page = await context.newPage();
  const response = await page.request.post(`${server.baseUrl}/api/waitlist`, {
    headers: { origin: "https://attacker.example" },
    form: { email: `cross-site-${Date.now()}@example.com`, source: "hero" },
    maxRedirects: 0,
  });

  assert.equal(response.status(), 403);
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
      headers: { "cf-connecting-ip": testIp, origin: server.baseUrl },
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
    headers: { "cf-connecting-ip": uniqueTestIp(), origin: server.baseUrl },
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
