import type { APIRoute } from "astro";
import { validateSubmission } from "../../lib/validate";
import { checkRateLimit, hashClientKey } from "../../lib/ratelimit";
import { getWaitlistDb } from "@waitlist-db";

// This route is the one server-rendered endpoint in the site (KTD12).
// Everything else in web/, including every /join/* confirmation page, is prerendered static output.
export const prerender = false;

const RATE_LIMIT = { limit: 10, windowSeconds: 60 };

/**
 * Redirects to one of a fixed set of static confirmation pages. The
 * target is always same-origin and always one of these four literal
 * paths, so this can never become an open redirect regardless of what a
 * client sends in the request.
 */
function redirectTo(
  origin: string,
  path: "/join/thanks/" | "/join/invalid/" | "/join/rate-limited/" | "/join/error/",
): Response {
  // 303 See Other: browsers without JS follow this as a plain GET, so the
  // no-JS path still lands on a real confirmation or error page instead
  // of re-submitting the form on refresh (AE10: "confirmed without a
  // full page reload failure path").
  return new Response(null, { status: 303, headers: { Location: new URL(path, origin).toString() } });
}

function isSameOrigin(request: Request): boolean {
  const originHeader = request.headers.get("origin");
  if (!originHeader) return false;

  let submittedOrigin: URL;
  try {
    submittedOrigin = new URL(originHeader);
  } catch {
    return false;
  }

  const requestUrl = new URL(request.url);
  const forwardedHost = request.headers.get("x-forwarded-host")?.split(",", 1)[0]?.trim();
  const forwardedProtocol = request.headers.get("x-forwarded-proto")?.split(",", 1)[0]?.trim();
  const expectedHost = forwardedHost || request.headers.get("host") || requestUrl.host;
  const expectedProtocol = forwardedProtocol ? `${forwardedProtocol}:` : requestUrl.protocol;

  return (
    submittedOrigin.host.toLowerCase() === expectedHost.toLowerCase() &&
    submittedOrigin.protocol === expectedProtocol
  );
}

export const POST: APIRoute = async ({ request, locals }) => {
  if (!isSameOrigin(request)) {
    return new Response("Cross-site POST form submissions are forbidden", { status: 403 });
  }

  const origin = request.headers.get("origin")!;
  const db = await getWaitlistDb(locals);

  if (!db) {
    return new Response("Service unavailable: storage is not configured.", { status: 503 });
  }

  const clientIp =
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",", 1)[0]?.trim() ??
    "unknown";
  const clientKey = await hashClientKey(clientIp);

  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return redirectTo(origin, "/join/invalid/");
  }

  const rate = await checkRateLimit(db, clientKey, RATE_LIMIT);
  if (!rate.allowed) {
    return redirectTo(origin, "/join/rate-limited/");
  }

  const result = validateSubmission({
    email: formData.get("email"),
    source: formData.get("source"),
  });

  if (!result.ok) {
    return redirectTo(origin, "/join/invalid/");
  }

  const createdAt = new Date().toISOString();

  try {
    // Duplicate submissions are idempotent, not an error (U21 test
    // scenario): re-inserting the same email is a silent success.
    await db
      .prepare(
        "INSERT INTO waitlist (email, created_at, source) VALUES (?, ?, ?) ON CONFLICT(email) DO NOTHING",
      )
      .bind(result.email, createdAt, result.source)
      .run();
  } catch (error) {
    console.error("waitlist insert failed", error);
    return redirectTo(origin, "/join/error/");
  }

  return redirectTo(origin, "/join/thanks/");
};
