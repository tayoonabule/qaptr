# Production review orchestration status

This note records the intentionally narrow August 2026 production bridge work
and the remaining blockers. It is not a claim that U17 or U19 are complete.

## Implemented now

- The review app bootstraps `generation-1` through `qaptr-review-ffi` before it
  opens durable history. The private age/X25519 key remains in the review app's
  non-synchronizing Keychain namespace. The helper can read only the matching
  public key from the vault.
- Existing key halves are reconciled rather than replaced. A missing public key
  can be restored from its private key. An orphaned public key or mismatched
  pair fails closed so existing encrypted captures are not made unreadable.
- Onboarding cannot finish while that secure bootstrap is unavailable.
- Observation rows can open a read-only detail sheet containing only the scalar
  observation, confidence, timestamp, and durable provenance identifiers. The
  detail path does not open a vault bundle or invoke a provider.

## Why analysis is not wired yet

`qaptr-workflow::AnalysisRunner` already enforces the important provider rule:
it accepts only payloads returned by `PrivacyGate` and never launches tools or
automations. The production review bridge cannot safely construct its inputs
yet:

1. `Vault` exposes `bundle_metadata(capture_id)` but no committed-bundle listing
   API. The helper also does not write capture metadata to `qaptr-store`.
   Scanning the vault's private directory layout from the bridge would bypass
   the vault abstraction and was deliberately not added.
2. Bundle metadata contains capture and generation identifiers, but not the
   capture timestamp or an analysis session identifier required by
   `CaptureRecordInput`.
3. The review bridge has no production `CaptureDecoder`, consent port, provider
   adapter selection, or cancellation/progress contract. Wiring a provider
   without those boundaries would risk bypassing the privacy gate or claiming
   consent that was never obtained.

The smallest safe next unit is therefore a vault-owned committed-bundle listing
API plus explicit capture metadata written by the helper, followed by a review
FFI orchestration API that takes an explicit consent decision and always routes
through `AnalysisRunner`.

## Why canonical workflow generation and exports are not wired yet

The pure `WorkflowDocument` and four Markdown renderers are complete and do not
perform I/O or execute anything. Durable `WorkflowRecord`, however, is a flat
summary. It omits typed inputs, outputs, per-step confidence and provenance, and
stores tools, sequence, decisions, and variations as undifferentiated strings.
There is no lossless conversion between that record and `WorkflowDocument`.

Inventing structure while rebuilding a document would violate Qaptr's evidence
rules. Exporting the flat record through the canonical renderers would therefore
misrepresent its provenance. The safe next unit is a versioned, lossless scalar
serialization for `WorkflowDocument`, persisted by the store and returned by
the review bridge. Only then should the app expose automation, handoff,
onboarding, and SOP export actions. Those actions must remain file/text export
only. They must never launch a tool or execute the described automation.
