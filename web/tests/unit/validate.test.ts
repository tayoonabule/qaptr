import { test } from "node:test";
import assert from "node:assert/strict";
import { validateSubmission } from "../../src/lib/validate.ts";

test("accepts a normal email and normalizes case", () => {
  const result = validateSubmission({ email: "Test@Example.COM", source: "hero" });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.email, "test@example.com");
    assert.equal(result.source, "hero");
  }
});

test("trims surrounding whitespace", () => {
  const result = validateSubmission({ email: "  someone@example.com  ", source: "footer" });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.email, "someone@example.com");
  }
});

test("rejects an empty email", () => {
  const result = validateSubmission({ email: "", source: "hero" });
  assert.equal(result.ok, false);
});

test("rejects a missing email field", () => {
  const result = validateSubmission({ email: null, source: "hero" });
  assert.equal(result.ok, false);
});

test("rejects an address with no domain", () => {
  const result = validateSubmission({ email: "nodomain@", source: "hero" });
  assert.equal(result.ok, false);
});

test("rejects an address with no @ sign", () => {
  const result = validateSubmission({ email: "not-an-email", source: "hero" });
  assert.equal(result.ok, false);
});

test("rejects an address with no top-level domain", () => {
  const result = validateSubmission({ email: "person@localhost", source: "hero" });
  assert.equal(result.ok, false);
});

test("rejects an address over the maximum length", () => {
  const longLocal = "a".repeat(250);
  const result = validateSubmission({ email: `${longLocal}@example.com`, source: "hero" });
  assert.equal(result.ok, false);
});

test("accepts a plus-addressed email", () => {
  const result = validateSubmission({ email: "person+tag@example.com", source: "hero" });
  assert.equal(result.ok, true);
});

test("falls back to 'unknown' for an unrecognized source tag", () => {
  const result = validateSubmission({ email: "person@example.com", source: "malicious<script>" });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.source, "unknown");
  }
});

test("falls back to 'unknown' for a missing source tag", () => {
  const result = validateSubmission({ email: "person@example.com", source: null });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.source, "unknown");
  }
});

test("accepts the 'footer' source tag", () => {
  const result = validateSubmission({ email: "person@example.com", source: "footer" });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.source, "footer");
  }
});
