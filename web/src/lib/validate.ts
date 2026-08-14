// Server-side email and source validation for the waitlist form.
// No dependency, pure functions, kept small and directly testable.

const MAX_EMAIL_LENGTH = 254;

// A pragmatic RFC 5322-inspired pattern: local part + @ + domain with a
// TLD. Deliberately not attempting a fully spec-compliant grammar; the
// goal is to reject obviously malformed input, not to be the last line of
// defense (the unique index and any real delivery attempt are that).
const EMAIL_PATTERN =
  /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;

export type ValidationResult =
  | { ok: true; email: string; source: string }
  | { ok: false; error: string };

const ALLOWED_SOURCES = new Set(["hero", "footer", "unknown"]);

/**
 * Normalizes and validates a submitted email address and source tag.
 * Returns a typed result rather than throwing, so callers always handle
 * both branches explicitly.
 */
export function validateSubmission(input: {
  email: FormDataEntryValue | null;
  source: FormDataEntryValue | null;
}): ValidationResult {
  const rawEmail = typeof input.email === "string" ? input.email.trim() : "";

  if (rawEmail.length === 0) {
    return { ok: false, error: "Enter an email address." };
  }

  if (rawEmail.length > MAX_EMAIL_LENGTH) {
    return { ok: false, error: "That email address is too long." };
  }

  const email = rawEmail.toLowerCase();

  if (!EMAIL_PATTERN.test(email)) {
    return { ok: false, error: "Enter a valid email address." };
  }

  const rawSource = typeof input.source === "string" ? input.source.trim() : "";
  const source = ALLOWED_SOURCES.has(rawSource) ? rawSource : "unknown";

  return { ok: true, email, source };
}
