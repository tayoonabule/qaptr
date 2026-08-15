# Qaptr next-session execution checklist

> Generated from [`qaptr-next-session.md`](qaptr-next-session.md) on 2026-08-15.
> **Rule:** Close an item only with its linked test, measured evidence, or explicitly recorded external blocker. Do not represent unavailable credentials, hardware, signing identity, or permission grants as complete.
> **HEAD audit:** Items closed on 2026-08-15 are supported by [`qaptr-next-session-head-audit-2026-08-15.md`](../reports/qaptr-next-session-head-audit-2026-08-15.md).

## Milestone guardrails

- [ ] Preserve the product loop: sealed capture → local preparation → explicit consent → provider analysis → observations → detail → Workflow → four Markdown exports.
- [ ] Keep capture configuration to one 5–300 second slider. Do not introduce pause, sparse, or frequency vocabulary.
- [ ] Do not transmit to a provider before per-session explicit consent.
- [ ] Keep durable history scalar and image-free. Do not persist screenshot bytes, thumbnails, provider payloads, or credentials.
- [ ] Fail closed for missing credentials/models, unavailable providers, failed privacy preparation, timeouts, and malformed output.
- [ ] Do not add automatic tool execution, cloud accounts, managed credits, continuous recording, clipboard capture, keystroke logging, background OCR, or background provider calls.

## 0. Baseline and reality spike

### 0.1 Establish a reproducible local baseline
- [ ] Refresh `graphify-out/` and capture the current affected paths before edits.
- [ ] Record the exact app, helper, Rust workspace, and Swift package revisions under test.
- [ ] Run `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test --workspace`, `cargo doc --workspace --no-deps`, and `swift test --package-path apps/helper`.
- [ ] Run `swift test --package-path apps/review` and record any existing failures independently from new work.
- [ ] Confirm fixture inventory and document which fixture captures can exercise real local preparation.

### 0.2 Prove packaged capture behavior
- [x] Build the packaged helper and review app with the normal packaging entrypoint. `bench/scripts/packaged_fixture_smoke.sh` invokes `packaging/release.sh --dry-run` by default and validates the resulting hierarchy.
- [ ] Install the package in an isolated local app location, with a selected display and Screen Recording permission.
- [ ] Configure a short valid capture interval and start the helper through its login-item/product path, not from an ad hoc binary only.
- [ ] Verify that an attempted capture updates scalar capture status.
- [ ] Verify that a successful capture creates a sealed bundle and updates the scalar last-success time/count.
- [ ] Relaunch the review app and confirm that it reports the same persisted state.
- [ ] Capture and classify failure evidence for denied Screen Recording, no selected display, inaccessible/locked display, and vault/disk write failure.
- [ ] Add this real capture/review path to U23/release validation so idle launches cannot pass it.

## 1. Capture status boundary

### 1.1 Define and persist production-safe status
- [x] Specify a shared, versioned scalar capture-status schema that contains: last attempted capture, last successful capture, successful capture count, selected display IDs, active interval, state, and concise failure reason.
- [x] Ensure the schema has no image bytes, image-derived thumbnails, raw window text, secrets, or provider content.
- [ ] Make the helper update state before an attempt, after a sealed bundle, and for every fail-closed terminal/temporary outcome.
- [x] Atomically write status and tolerate absent/corrupt previous status by surfacing unavailable rather than inventing success.
- [x] Add a monotonic status revision/timestamp so the review app can recognize a fresh helper update after relaunch.

### 1.2 Show truthful capture status in review
- [ ] Decode the shared schema in `QaptrReviewCore` with forward-compatible unknown-state handling.
- [x] Map real state to exactly: never configured, permission denied, waiting for first tick, capturing, capture failed, and capture ready.
- [x] Show last successful capture and count only when a sealed bundle has actually succeeded.
- [ ] Show selected displays and configured interval from the same state/control boundary.
- [x] Surface one concise actionable reason for unavailable/failed states.
- [x] Add unit tests for absent, corrupt, stale, denied, no-display, disk-failure, waiting, and successful progress files.

### 1.3 Test and package the boundary
- [ ] Add deterministic helper tests covering every `CaptureEvent` → persisted status mapping.
- [x] Add review-core decoding/UI-model tests covering every visible capture state.
- [ ] Add a fixture ingestion mode that creates scalar status plus sealed bundles without exposing image material to the test UI.
- [x] Verify the helper remains free of OCR and provider imports/calls after the change.

## 2. Production review-session driver

### 2.1 Establish the review-session coordinator
- [ ] Create one review-app-owned coordinator above the existing analysis runner; it must be the only production owner of vault opening, local preparation, provider dispatch, and scalar persistence.
- [ ] Ingest eligible sealed bundles deterministically, deduplicate against durable capture metadata, and apply configured retention before preparation.
- [ ] Decode bundles only inside the vault/privacy boundary and construct `PreparationInput` without returning image bytes.
- [ ] Run OCR, masking, coverage, and sanitization locally for every eligible capture before any consent/provider step.
- [ ] Aggregate exclusions into one quiet notice per review session, while continuing safely prepared captures.
- [ ] Stream coarse progress suitable for Swift: ingesting, preparing counts, ready for consent, analyzing, completed, failed, cancelled.
- [ ] Include exact capture count, prepared count, excluded count, provider, resolved model, and payload kinds in the consent summary.

### 2.2 Consent, retry, cancellation, and error semantics
- [ ] Make consent explicit and scoped to one session immediately before the first request.
- [x] Verify declined consent results in zero provider invocations and leaves prepared local state non-durable except permitted scalar notices.
- [ ] Revalidate provider and resolved model after local preparation and before consent/request dispatch.
- [ ] Make cancellation cooperative at ingest, preparation, consent, and between provider operations.
- [ ] Ensure provider timeout, malformed output, or cancellation rolls back staged observations and workflows.
- [ ] Define retry to reuse sealed captures safely but never reuse a stale provider/model validation decision without revalidation.
- [ ] Add distinct user-facing messages and recovery actions for unavailable provider, unavailable model, privacy exclusion, provider failure, malformed output, cancellation, and empty honest result.

### 2.3 Persist and expose results safely
- [ ] Normalize only schema-valid provider responses into bounded observations and candidate workflows.
- [ ] Persist observation summaries, workflow summaries, and exclusion notices through `qaptr-store` allowlisted writers only.
- [ ] Confirm the store rejects encoded-image-looking scalar text at every new writer boundary.
- [ ] Extend the bridge with coarse operations only: start, progress, grant/decline consent, cancel, retry, observation detail, workflow generation, and export.
- [ ] Do not mirror vault, privacy, provider, or raw domain models across the C/Swift bridge.
- [ ] Add bridge contract tests for output shape, errors, no-image invariant, and restart persistence.

### 2.4 Vertical-slice acceptance tests
- [ ] Make the 24-capture fixture run through the production-shaped coordinator using a fake provider behind the real adapter/gate boundary.
- [ ] Assert all local preparation finishes before the fake provider sees a request.
- [ ] Assert declined consent causes no fake-provider calls.
- [ ] Assert one excluded capture creates exactly one aggregate notice without suppressing observations from safe captures.
- [ ] Assert malformed/failed provider responses produce no partial observation/workflow rows.
- [ ] Assert a successful fixture run is visible through the same review-app snapshot API as the actual app.

## 3. Provider readiness and model policy

### 3.1 Define typed, durable configuration
- [x] Add a typed, versioned `ModelPolicy` with a single current policy version and explicit fallback ordering.
- [ ] Store provider choice and optional explicit model override separately from policy/default resolution.
- [ ] Store only non-secret configuration and bounded catalog metadata. Keep the OpenRouter key solely in its Keychain credential boundary.
- [ ] Define model-readiness statuses with a concise reason and next action: no provider, provider unavailable, authentication needed, catalog stale/unavailable, preferred unavailable with fallback, override unavailable, ready.
- [ ] Make the resolved provider/model immutable for one consented request and record it in scalar result metadata.

### 3.2 OpenRouter catalog strategy
- [ ] Add a bounded OpenRouter model-catalog/configuration transport that uses credentials transiently and never logs or persists the key/response payload.
- [ ] Parse catalog responses defensively, rejecting malformed/unstructured entries and only accepting models that satisfy Qaptr’s structured-output/capability requirements.
- [ ] Select the versioned preferred model if valid; otherwise select the next validated fallback and emit a clear change notice.
- [ ] Cache validated catalog entries with a bounded freshness period and invalidate/revalidate before analysis.
- [ ] Make an unavailable explicit override block analysis with setup guidance rather than falling back silently.
- [ ] Do not fetch the catalog merely from provider/model selection UI; model availability validation must be consent-safe and distinctly disclosed.

### 3.3 CLI provider strategy
- [ ] Keep the supported provider list limited to OpenRouter, Claude CLI, Codex CLI, and Jcode CLI.
- [ ] Derive CLI availability from each adapter’s supported detection/authentication capability check.
- [ ] Do not expose detected-but-unusable CLI providers as selectable.
- [ ] Resolve a CLI’s documented default model unless a supported explicit override exists.
- [ ] Surface the resolved CLI model or an honest “provider default” label in consent and result metadata.
- [ ] Do not read or widen access to Claude credentials. Any macOS authentication integration requires separate explicit user approval and a narrow design review.

### 3.4 Provider/model UI and tests
- [ ] Render provider rows with readiness, short reason, and exactly one next action.
- [ ] Render model readiness separately from provider readiness.
- [ ] Show the selected provider, resolved model, payload kinds, capture count, and exclusions in the consent view.
- [ ] Ensure provider/model selection alone cannot invoke analysis or send a provider payload.
- [ ] Add test cases for missing credential, stale catalog, malformed catalog, preferred unavailable, fallback selected, unavailable override, CLI defaults, CLI unauthenticated, and model revalidation failure.
- [ ] Add request-boundary tests proving missing/invalid provider/model configuration causes zero provider requests.

## 4. Observation detail, Workflow, and exports

### 4.1 Real observation surfaces
- [ ] Render cards from actual review-session observations rather than seeded/read-only history only.
- [ ] Show title, summary, confidence band, source/session metadata, chronology, observed tools, and exclusions.
- [x] Mark low-confidence evidence as uncertain instead of strengthening its wording.
- [ ] Add honest empty states for no captures, no safely prepared captures, no observations, and analysis failure.

### 4.2 Detail and detailed capture
- [ ] Add observation detail actions driven by scalar durable data only.
- [ ] Implement explicit start/stop detailed-capture lifecycle through the same 5–300 second interval-control vocabulary.
- [ ] Do not restore pause, sparse, or frequency copy, tests, or settings.
- [ ] Show detailed-capture action result from real helper state, including permission or startup failure.
- [ ] Add lifecycle tests for start, stop, helper unavailable, permission denied, and interval persistence.

### 4.3 Canonical Workflow generation
- [x] Generate a canonical `WorkflowDocument` from the selected observation/candidate workflow using only observed or explicitly supplied scalar material.
- [ ] Persist the scalar workflow summary through `qaptr-store` and make it visible after relaunch.
- [x] Ensure missing sequence/details remain visibly missing rather than inferred.
- [x] Test generation from high, low, and sparse evidence; validate stable IDs and honest confidence/provenance.

### 4.4 Four in-app exports
- [x] Wire canonical Workflow rendering to automation, handoff, onboarding, and SOP Markdown variants.
- [ ] Add an app-owned save/export flow that needs no developer path entry and does not launch another application, agent, or automation.
- [ ] Write files atomically and surface cancellation/write errors truthfully.
- [ ] Verify rendered Markdown contains no raw capture material, thumbnails, privacy placeholders, or secrets.
- [ ] Add stable golden/snapshot tests for all four export variants, including low-confidence and sparse workflows.
- [x] Install/document the required snapshot tool if it is not already available in CI and local development. No external tool is required: the golden tests use Rust's built-in `include_str!` assertions.

## 5. Onboarding, settings, and runtime-state UX

### 5.1 Complete real onboarding
- [x] Explain periodic capture, local privacy preparation, provider transmission, and just-in-time consent in fresh-user onboarding.
- [ ] Show Screen Recording status and selected displays from live state.
- [ ] Let the user select a provider only when readiness checks make it usable.
- [ ] Show the validated default/resolved model at setup time where available, without pretending network validation occurred if it did not.
- [ ] Make onboarding completion durable only after required local setup decisions are complete.

### 5.2 Reconcile the settings surface
- [ ] Restrict settings to capture interval, displays, cache lifetime, provider/model, privacy/permission status, and justified exclusion controls.
- [ ] Remove obsolete sparse/pause/frequency vocabulary from `docs/plans/qaptr-v1.md`, source, tests, and user-visible copy.
- [ ] Keep login-item state and permissions live rather than cached as optimistic success.
- [ ] Add visible provider/model readiness and one recovery action per unavailable state.

### 5.3 Runtime-state visual coverage
- [ ] Implement loading, empty, permission denied, provider unavailable, model unavailable, capture failed, exclusion, consent, analysis failed, success, and export-complete states using real model state.
- [ ] Apply `docs/design/full-product-visual-redesign.md` only after the state is backed by live behavior.
- [ ] Verify keyboard traversal, VoiceOver labels, light mode, dark mode, and reduced motion for every added action/state.
- [ ] Add focused SwiftUI/UI-model tests for state copy and accessibility labels where practical.

## 6. Privacy and provider release proof

### 6.1 Masked-image verification
- [ ] Configure the approved real Vision recognizer/masked-image verification path on a controlled macOS validation machine.
- [ ] Run the 24-capture preparation corpus and record the raw measured result and environment.
- [ ] Preserve the published 5/6 = 0.833 recall disclosure unless a newly measured corpus changes it.
- [ ] Treat missing recognizer configuration or an inconclusive result as fail-closed, not as a passing test.

### 6.2 Credentialed provider evidence
- [ ] On a controlled validation machine, configure an OpenRouter key through Keychain without placing it in source, logs, fixtures, shell history, or reports.
- [ ] Prove OpenRouter detection, catalog/model resolution, consent summary, invocation, normalized response, and result metadata.
- [ ] Run one CLI provider end-to-end with its existing authenticated session and document the boundary used.
- [ ] Run the four-provider observation flow only where each provider can be authentically validated; record unavailable providers as blocked with reason rather than fabricating completion.
- [ ] Scrub all reports and artifacts for credentials, raw provider payloads, and raw capture material.

## 7. Packaging and release validation

### 7.1 Packaged-app coverage
- [ ] Extend U23/release checks to require a real helper-generated capture and review-session result, not an idle app launch.
- [ ] Verify the helper is embedded at the expected location, starts as the login item, and is visible to the review app through scalar status.
- [x] Add a deterministic packaged smoke fixture for environments where Screen Recording cannot be granted. See [`fixtures/packaged-smoke/`](../../fixtures/packaged-smoke/) and [`docs/release-packaged-smoke.md`](../release-packaged-smoke.md). The fixture is explicitly not a substitute for real Screen Recording evidence.

### 7.2 External validation environments
- [ ] Run clean-machine install/bootstrap and record macOS version, architecture, permission prompts, helper startup, first capture, review, analysis fixture, Workflow, and export results.
- [ ] Repeat helper/review performance measurements on the specified 16 GB machine with attached 5K display.
- [ ] Run the 12-hour helper soak and production-shaped opened-app budget with the real session driver.
- [ ] Investigate and fix regressions before changing a budget or describing it as passing.

### 7.3 Distribution proof
- [ ] Obtain/use a credentialed Developer ID signing identity under the release owner’s control.
- [ ] Sign, notarize, staple, assess Gatekeeper, reboot, and verify login-item persistence on a validation machine.
- [ ] Resolve/document the Mach-O UUID reproducibility policy before asserting bit-identical artifacts.
- [ ] Run reproducibility checks against two independently built artifacts and retain only non-sensitive diffs/evidence.

## 8. Final acceptance and handoff

- [ ] Execute the desired fresh-install flow end to end with a fixture and, where credentials/permissions permit, a real capture/provider path.
- [ ] Confirm every claimed completion has a linked test, measured run, or externally constrained blocker record.
- [ ] Re-run all Rust, Swift helper, Swift review, documentation, website/accessibility, and release-validation gates relevant to changed files.
- [ ] Refresh the knowledge graph and re-check impact for every shared type changed.
- [ ] Update `bench/release_validation.md`, plan status, and release evidence with actual dates/results only.
- [ ] Review the final diff for prohibited vocabulary, secret leakage, raw capture persistence, provider calls before consent, and unsupported UI optimism.
- [ ] Commit implementation work in small, independently testable commits. Do not commit generated build output or sensitive validation artifacts.

### Code/documentation evidence completed in this pass

- [x] The U23 validator now runs `packaged_fixture_smoke`, so an idle review launch cannot be the only packaged-app evidence.
- [x] `docs/release.md` documents the command, fixture contents, and the boundary between deterministic fixture proof and real helper capture proof.
- [x] `docs/release-packaged-smoke.md` records the manual handoff needed because `bench/release_validation.md` was already user-modified and was not edited.
- [ ] Real helper capture, clean-machine install, permissions, login-item startup, provider analysis, and distribution signing remain external blockers and are intentionally not checked off.

## External blockers that cannot be closed by code alone

- [ ] A user or release owner grants Screen Recording permission on a packaged build.
- [ ] A controlled validation machine provides an OpenRouter credential.
- [ ] A user/release owner decides whether to approve a narrow Claude authentication integration.
- [ ] A validation machine has the required Vision recognizer configuration.
- [ ] A clean macOS reference machine with 16 GB RAM and attached 5K display is available.
- [ ] A release owner provides a Developer ID signing/notarization identity.
- [ ] A 12-hour soak can run uninterrupted on the approved validation hardware.

## Definition-of-done checklist

- [ ] A packaged Qaptr app visibly reports at least one real sealed capture.
- [ ] The review app analyzes a fixture or real session and visibly shows observations.
- [ ] Provider readiness is truthful and prevents unavailable providers from being selected/invoked.
- [ ] A versioned model policy resolves and displays a validated default before consent.
- [ ] The user can consent, analyze, inspect, generate a Workflow, and produce all four exports from the app.
- [ ] Failure/unavailable states are explicit, accurate, and recoverable when safe.
- [ ] No provider request bypasses local privacy preparation and explicit consent.
- [ ] Relevant Rust, bridge, Swift, provider, privacy, UI, packaging, and release tests provide evidence for the full path.
