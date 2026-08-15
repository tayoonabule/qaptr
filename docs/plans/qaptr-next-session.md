---
title: Qaptr next-session implementation plan
artifact_contract: ce-unified-plan/v1
artifact_readiness: planning-ready
created: 2026-08-15
source_plans:
  - docs/plans/qaptr-v1.md
  - docs/design/full-product-visual-redesign.md
  - bench/release_validation.md
---

# Qaptr next-session implementation plan

## Why this plan exists

The existing V1 plan describes the intended architecture and release gates, but the current packaged app does not yet deliver the core user outcome. In a real use of the app, it currently appears not to capture useful sessions, generate observations, connect through a usable provider flow, or provide a simple reliable model choice.

This document supersedes the immediate execution order from `docs/plans/qaptr-v1.md` for the next planning session. It does not weaken the privacy or release requirements. It converts the current evidence into an implementation-first plan.

## Current truth, not aspiration

### Confirmed working or substantially implemented

- Rust formatting, linting, workspace tests, docs, and selected integration tests pass.
- The helper has real capture, scheduling, sealing, interval persistence, and link-boundary tests.
- The new capture control direction is a single 5–300 second interval slider. Pause, sparse, frequency, and stale active terminology should not return.
- Privacy preparation is fail-closed. Durable history is image-free. Provenance and mismatch checks exist.
- Codex and Jcode local detection pass their sandboxed capability checks.
- The website checks and accessibility checks pass.
- Local packaged-app assembly, bundle identity, helper placement, ad-hoc signing, and dylib audits pass.

### Confirmed missing or not proven

- The review app is largely a read-only history/settings surface. It does not yet drive a real review session from captures to observations.
- There is no complete production path for analyze, observe, inspect in detail, generate a Workflow, or export the four Markdown variants.
- The provider UI does not yet provide a simple, trustworthy provider/model selection experience.
- There is no reliable default model policy that selects a usable model without requiring the user to update the app when a provider changes its fastest or preferred model.
- Real OpenRouter endpoint/key proof is not configured. Claude authentication remains unverified because its session is Keychain-backed and the sandbox intentionally does not read credentials.
- The real-image Vision/masking preparation gate fails closed because masked-image recognition verification is not configured.
- Clean-machine install, Developer ID notarization, Gatekeeper, reference-machine measurements, and bit-identical reproducibility remain unverified or blocked.

## Product decisions to lock before implementation

1. **The primary product loop is capture → local preparation → provider analysis → observations → detail → Workflow → export.** Every implementation task must connect to this loop.
2. **The current capture setting is one interval slider from 5 to 300 seconds.** Do not restore pause/sparse/frequency concepts in code, UI, tests, or copy.
3. **Provider selection must be simple.** The user chooses a provider, then sees only models that provider currently makes available or that Qaptr has validated through a capability/configuration check.
4. **A reliable default model is mandatory.** Qaptr must ship with a versioned default policy, not a hardcoded model name scattered through the UI. If a configured model is unavailable, Qaptr must select a validated fallback or explain that setup is incomplete. It must never silently send to an unknown or stale model.
5. **Model discovery must not require an app update for routine provider model changes.** OpenRouter should use a safe model-list/configuration path where possible. CLI providers should use their own supported default/model capability rather than pretending Qaptr knows every model name.
6. **No provider request occurs before explicit consent.** Local capture ingestion, preparation, model availability checks, and validation may occur before consent, but provider payload transmission may not.
7. **Fail closed remains non-negotiable.** Missing credentials, unavailable models, failed masking, failed sanitization, timeout, malformed provider output, or ambiguous provider state must produce a truthful unavailable/error state.
8. **The app must show real status, not optimistic status.** Capture state, connection state, provider readiness, model readiness, last capture, and last analysis must be derived from actual runtime evidence.

## Desired end-to-end acceptance flow

Given a fresh install with Screen Recording permission and a selected display:

1. Onboarding explains capture, local privacy preparation, provider use, and consent.
2. The helper captures at the configured interval and writes sealed bundles.
3. The review app can show the last successful capture time and capture count from real state.
4. Opening Review ingests available bundles and runs local OCR, masking, coverage, and sanitization without provider access.
5. Settings shows provider readiness and model readiness with a concise reason.
6. The user selects a provider and, when applicable, a model. The UI shows a validated default immediately.
7. The first analysis request shows provider, model, payload kinds, capture count, and exclusions, then waits for consent.
8. Analysis produces a small set of observations with confidence and source metadata, or a precise empty/error state.
9. Selecting an observation opens detail and allows starting a recommended detailed-capture interval using the current slider model.
10. The user can generate a canonical Workflow and export four Markdown documents without Qaptr launching another tool.
11. History contains summaries, observations, workflows, and notices only. No screenshot bytes or thumbnails are persisted.

## Workstream 1: make capture visibly real

### Goal
Prove that the helper is capturing in the packaged product and make the state visible to the review app.

### Tasks

- Add a production-safe capture status/state boundary shared by helper and review app.
- Expose last attempted capture, last successful capture, capture count, selected displays, current interval, and failure reason without exposing image bytes.
- Make the review app distinguish: never configured, permission denied, waiting for first tick, capturing, capture failed, and capture ready.
- Add a deterministic fixture/session ingestion path for tests and a real packaged-app smoke path.
- Verify the helper is actually running as a login item in the packaged app, not merely building successfully.
- Preserve no-background-OCR/provider behavior in the helper.

### Acceptance

- A real packaged-app run with permission granted creates observable capture metadata at the configured interval.
- The review app reports the actual last capture state after relaunch.
- Permission denial, locked display, missing display, and disk failure are truthful and fail closed.
- No capture UI claims success before a real sealed bundle exists.

## Workstream 2: build the production review-session driver

### Goal
Turn the read-only review shell into the actual product loop.

### Tasks

- Add a review-session coordinator that ingests sealed bundles, applies retention, runs local privacy preparation, aggregates exclusions, and streams progress.
- Add explicit consent state before the first provider request.
- Add provider invocation through the existing capability-gated adapter boundary.
- Normalize provider output into observations and candidate workflows.
- Persist observations, notices, and workflow summaries through the allowlisted store API.
- Add cancellation and retry semantics with no partial observation rows.
- Expose narrow FFI/Swift bridge calls for start, progress, consent, cancel, retry, detail, workflow generation, and export.
- Keep the bridge coarse. Do not mirror the entire Rust domain model into Swift.

### Acceptance

- The 24-capture fixture runs through a production-shaped review driver.
- Local preparation completes before any provider call.
- Declined consent produces zero provider requests.
- One excluded capture produces one aggregated notice and does not block safe captures.
- A successful run creates observations visible in the actual app.
- A failed provider or malformed response does not create misleading observations.

## Workstream 3: simple provider and model setup

### Goal
Make provider setup understandable, reliable, and low-maintenance.

### Provider UX

- Show four supported V1 choices only: OpenRouter, Claude CLI, Codex CLI, and Jcode CLI.
- Use simple rows with status, short reason, and one next action.
- Never show detected-but-unusable providers as selectable.
- Separate provider readiness from model readiness.
- Keep credential entry and authentication ownership truthful: OpenRouter uses a Qaptr-held Keychain key; CLI providers use their existing authenticated CLI sessions.

### Model policy

- Define a typed `ModelPolicy` with provider-specific strategy:
  - OpenRouter: fetch or validate a model catalog when credentials are present, filter to supported structured-output/capability requirements, and select a versioned preferred default with fallback ordering.
  - Claude/Codex/Jcode CLI: use the CLI's documented default model unless an explicit supported override is available; surface the resolved model in the consent view and result metadata.
- Store the selected provider and optional model override separately from the default policy.
- Revalidate the selected model before analysis.
- If a model disappears, automatically choose the next validated fallback and explain the change, or stop with a setup action. Never silently downgrade to an arbitrary model.
- Make model catalog/configuration cacheable with a bounded freshness period and no sensitive payloads.
- Add a test matrix for missing credentials, stale catalogs, unavailable preferred models, fallback selection, malformed catalogs, and provider-specific defaults.

### Acceptance

- A new user can reach a valid default configuration without knowing model names.
- The UI clearly says which provider and model will receive the next request.
- Routine OpenRouter model changes do not require an app update when the catalog endpoint remains compatible.
- A missing or invalid model cannot produce a provider request.
- Provider and model selection has no network side effect until the user starts analysis and consents.

## Workstream 4: observations, detail, Workflow, and exports

### Tasks

- Render real observation cards from the review-session result.
- Add observation detail with evidence confidence, chronology, tools, and exclusions.
- Implement the detailed-capture lifecycle using the current interval-slider vocabulary and explicit start/stop semantics.
- Generate the canonical Workflow document from a selected observation.
- Wire automation, handoff, onboarding, and SOP Markdown exports to the app.
- Add stable export snapshots and install/run the required snapshot tooling.
- Ensure exports never launch agents or execute automations.

### Acceptance

- A real analyzed session produces at least one honest observation when the fixture supports it.
- A selected observation can produce a canonical Workflow and all four exports.
- Low-confidence evidence is marked as uncertain.
- Export output contains no privacy placeholders or raw capture material.
- Export is usable from the app without manual file-path or developer steps.

## Workstream 5: reconcile and finish the UX

- Update `docs/plans/qaptr-v1.md` to remove obsolete sparse/pause/frequency language and reflect the single interval model.
- Complete the full-product visual redesign against the real runtime states, not placeholder history.
- Add explicit loading, empty, permission, provider unavailable, model unavailable, capture failed, exclusion, consent, analysis failed, success, and export states.
- Ensure settings contains only capture interval, displays, cache lifetime, provider/model, and privacy/permission status.
- Validate keyboard traversal, VoiceOver labels, light/dark appearance, and reduced motion on the live surfaces.
- Do not invest in visual polish that masks absent runtime behavior. Runtime truth precedes polish.

## Workstream 6: privacy and provider release proof

- Configure the real Vision recognizer/masked-image verification path and rerun the 24-capture preparation gate.
- Preserve the published recall disclosure of 5/6 = 0.833 unless a new measured corpus changes it.
- Configure OpenRouter credentials on a controlled validation machine and prove endpoint/model behavior without recording the key.
- Decide whether a narrowly scoped, user-approved macOS authentication integration is acceptable for Claude. Do not grant broad sandbox access or read Claude credential files.
- Run the full four-provider end-to-end observation flow once the review-session driver exists.

## Workstream 7: release validation

- Add a real packaged-app capture/review driver to U23.
- Run the clean-machine install/bootstrap flow.
- Repeat helper and review measurements on the required 16 GB plus attached 5K reference machine.
- Run the full 12-hour helper soak and production-shaped opened-app budget.
- Run credentialed Developer ID signing, notarization, stapling, Gatekeeper assessment, and reboot/login-item persistence.
- Resolve or explicitly document the Mach-O UUID reproducibility policy before claiming bit-identical artifacts.
- Require `release_validate.sh` to report the real session, not idle smoke launches.

## Proposed execution order for the next session

1. **Reality spike:** run the packaged app with a short interval and instrument the capture-status path. Prove whether capture bundles are actually being created and where the chain stops.
2. **Session vertical slice:** fixture bundles → local preparation → fake provider through the real adapter boundary → observations in the real review UI.
3. **Provider/model UX:** implement readiness states, default model policy, fallback selection, and consent summary.
4. **Real provider slice:** OpenRouter first, then one CLI provider, with no credential leakage and explicit model reporting.
5. **Workflow/export slice:** observation → canonical Workflow → four exports from the actual app.
6. **Detailed capture and onboarding:** connect the current interval setting to the real helper lifecycle and complete fresh-user flow.
7. **Privacy proof:** configure real masked-image verification and rerun the corpus.
8. **Release evidence:** clean machine, reference machine, credentialed packaging, soak, reproducibility.
9. **Visual polish pass:** only after the live loop is observable and reliable.

## Definition of done for the next planning milestone

The next milestone is not “the app builds.” It is:

- A packaged app visibly captures at least one real bundle.
- The review app visibly analyzes a fixture or real session and shows observations.
- A provider is connected through a truthful readiness gate.
- A model is selected by a reliable default policy and displayed before consent.
- The user can consent, analyze, inspect an observation, create a Workflow, and export it.
- Failures and unavailable states are explicit and recoverable where safe.
- No provider request bypasses consent or the privacy gate.
- The relevant bridge, Rust, Swift, provider, privacy, and UI tests cover the full path.

## Explicit non-goals for this plan

- No automatic agent execution or workflow launching.
- No cloud account system or Qaptr-managed credits.
- No continuous recording, clipboard capture, keystroke logging, or background OCR/provider analysis.
- No weakening of privacy gates, sandbox isolation, authentication boundaries, or release evidence to make validation green.
