# Production review orchestration status

> Updated 2026-08-20. Source, tests, and release scripts are authoritative.

## Implemented

- The review app bootstraps `generation-1` through `qaptr-review-ffi`; private
  age/X25519 key material remains in the non-synchronizing Keychain namespace,
  while the helper receives only the matching public key.
- A provider-aware native review-session driver lists committed vault bundles,
  performs OCR, masking, coverage checks, and context sanitization locally,
  then stops at an explicit per-session consent boundary.
- After approval, the driver invokes only the selected verified provider through
  `AnalysisRunner`, reports bounded progress, supports cancellation/retry, and
  persists scalar observations and canonical workflows. Captured image bytes and
  provider payloads are not written to durable history.
- The Swift review app exposes analysis state, observation detail, workflow
  generation, and the four Markdown exports through the scalar FFI contract.
- Provider readiness distinguishes installation from a successful bounded
  connection check. Missing credentials, failed privacy preparation, timeouts,
  malformed output, and unavailable providers fail closed.

## Acceptance boundary

The signed installed app has prepared real committed captures and reached the
Jcode consent sheet. That acceptance run declined consent and confirmed that
nothing was sent. Deterministic integration tests cover successful provider
responses and durable observation/workflow persistence. A real provider
transmission is intentionally never performed by unattended validation because
it would send the user's captured context.
