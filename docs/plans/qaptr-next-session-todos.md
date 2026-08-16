# Qaptr next-session execution checklist

> Generated from [`qaptr-next-session.md`](qaptr-next-session.md) on 2026-08-15.
> **Rule:** Close an item only with its linked test, measured evidence, or explicitly recorded external blocker. Do not represent unavailable credentials, hardware, signing identity, or permission grants as complete.
> **Execution update (2026-08-16):** Remaining code-backed work is being executed in parallel by Rust session, bridge, provider-readiness, review-app UX, and release-evidence workers. External permission, credential, hardware, signing, and soak items remain blocked unless independently evidenced. This note will be updated with verified commits and test results as workers finish.
> **Verified during this pass:** `cargo test -p qaptr-workflow --test analyze` passes 14/14, including `cancellation_requested_by_consent_stops_before_provider_invocation`; this closes only the consent-boundary cancellation regression, not the full cooperative-cancellation checklist row.
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
- [x] Refresh `graphify-out/` and capture the current affected paths before edits. Refreshed on 2026-08-15 before the provider-failure acceptance work; `graphify affected AnalysisRunner --depth 2` identifies the session coordinator plus analysis regression surface, and `graphify affected ProviderChoice --depth 2` identifies the persisted-preferences and review UI consumers.
- [x] Record the exact app, helper, Rust workspace, and Swift package revisions under test. The validated source baseline includes review app/UI `caff528f6fa5eeff32b3e0ecd4b322bc449502fe`, helper fixture boundary `28503e650460d963f8801a72e901d29470a5bd6f`, workflow acceptance `de99c299ff18efc1de811acab3a0ae242b1cf7f2`, review FFI `6186047d383317b5a0b1770224b41ecbc9a23f6b`, policy catalog `2d78708006d5184528d959bba5c40c72adefeac5`, and macOS Vision correction `4d32ab27525a8872ee0ce50e0909aa0d44288a96`.
- [x] Run `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test --workspace`, `cargo doc --workspace --no-deps`, and `swift test --package-path apps/helper`. All commands passed on 2026-08-15 after the Vision helper cold-start correction; the helper suite ran 20 tests.
- [x] Run `swift test --package-path apps/review` and record any existing failures independently from new work. The full review package passed 65 tests on 2026-08-15 after restoring the missing view layer; no existing test failure remains.
- [x] Confirm fixture inventory and document which fixture captures can exercise real local preparation. `fixtures/session/manifest.csv` enumerates 24 1600×1000 logical captures across the existing `text`, `rotated`, `no_text`, `single_color`, `low_contrast`, and `qr` Vision fixture sources; `fixtures/session/README.md` records that the repeated sources are intentional and are suitable for the real local Vision preparation measurement.

### 0.2 Prove packaged capture behavior
- [x] Build the packaged helper and review app with the normal packaging entrypoint. `bench/scripts/packaged_fixture_smoke.sh` invokes `packaging/release.sh --dry-run` by default and validates the resulting hierarchy.
- [ ] Install the package in an isolated local app location, with a selected display and Screen Recording permission.
- [ ] Configure a short valid capture interval and start the helper through its login-item/product path, not from an ad hoc binary only.
- [ ] Verify that an attempted capture updates scalar capture status.
- [ ] Verify that a successful capture creates a sealed bundle and updates the scalar last-success time/count.
- [ ] Relaunch the review app and confirm that it reports the same persisted state.
- [ ] Capture and classify failure evidence for denied Screen Recording, no selected display, inaccessible/locked display, and vault/disk write failure.
- [x] Add this real capture/review path to U23/release validation so idle launches cannot pass it. `release_validate.sh` now requires explicit helper-capture and review-result evidence records, reporting absent environment evidence as `BLOCKED` and malformed/contradictory records as `FAIL`; deterministic validator contracts cover idle/first-paint rejection (`6f1b821`; `bench/scripts/test_validate_release_evidence.sh` passes).

## 1. Capture status boundary

### 1.1 Define and persist production-safe status
- [x] Specify a shared, versioned scalar capture-status schema that contains: last attempted capture, last successful capture, successful capture count, selected display IDs, active interval, state, and concise failure reason.
- [x] Ensure the schema has no image bytes, image-derived thumbnails, raw window text, secrets, or provider content.
- [x] Make the helper update state before an attempt, after a sealed bundle, and for every fail-closed terminal/temporary outcome. `HelperApplication.runTick` atomically persists `capturing` before display enumeration/capture, then persists sealed-count or concise capture/sealing failure, permission-required, no-display, and enumeration-error transitions; `CaptureCoreTests` covers the event-to-status mappings and the packaged helper build passed in the release dry run.
- [x] Atomically write status and tolerate absent/corrupt previous status by surfacing unavailable rather than inventing success.
- [x] Add a monotonic status revision/timestamp so the review app can recognize a fresh helper update after relaunch.

### 1.2 Show truthful capture status in review
- [x] Decode the shared schema in `QaptrReviewCore` with forward-compatible unknown-state handling. Unknown helper states decode without losing the scalar snapshot and surface an honest update/recovery message (`eb0477e`; isolated `QaptrReviewCoreTests` target builds cleanly).
- [x] Map real state to exactly: never configured, permission denied, waiting for first tick, capturing, capture failed, and capture ready.
- [x] Show last successful capture and count only when a sealed bundle has actually succeeded.
- [x] Show selected displays and configured interval from the same state/control boundary. `ObservationSheetView` now renders the scalar `selectedDisplayIDs` and the helper’s active interval, falling back only to the same local interval control when no helper update exists (`35d9405`; review Swift tests pass).
- [x] Surface one concise actionable reason for unavailable/failed states.
- [x] Add unit tests for absent, corrupt, stale, denied, no-display, disk-failure, waiting, and successful progress files.

### 1.3 Test and package the boundary
- [x] Add deterministic helper tests covering every `CaptureEvent` → persisted status mapping. `CaptureCoreTests` covers sealed, refused overlap, skipped permission, skipped no displays, skipped sealing, and generic skipped outcomes (`3300ff4`; `swift test --package-path apps/helper` passes 18 tests).
- [x] Add review-core decoding/UI-model tests covering every visible capture state.
- [x] Add a fixture ingestion mode that creates scalar status plus sealed bundles without exposing image material to the test UI. `FixtureIngestion` accepts only a bounded manifest, seals source images directly through the helper vault boundary, persists capture progress, and rejects unsafe paths (`28503e6`; `swift test --package-path apps/helper` passes 20 tests).
- [x] Verify the helper remains free of OCR and provider imports/calls after the change.

## 2. Production review-session driver

### 2.1 Establish the review-session coordinator
- [ ] Create one review-app-owned coordinator above the existing analysis runner; it must be the only production owner of vault opening, local preparation, provider dispatch, and scalar persistence. `ReviewSessionCoordinator` now owns lifecycle timing, ingestion, retention, cancellation, retry, and progress, while `AnalysisRunner` still owns the vault/privacy/provider/store boundary (`crates/qaptr-workflow/src/session.rs:143-168`, `crates/qaptr-workflow/src/analyze.rs:202-224`). The implementation is production-shaped, but this exact single-owner wording is not closed until that boundary is intentionally reconciled.
- [x] Ingest eligible sealed bundles deterministically, deduplicate against durable capture metadata, and apply configured retention before preparation. `ReviewSessionCoordinator` orders/deduplicates capture IDs, filters captures already represented in durable history, writes eligible metadata, and applies retention before runner preparation; `cargo test -p qaptr-workflow --test session` passes `repeated_coordinator_session_skips_captures_already_in_history`, `first_run_retention_reaps_ingested_capture_before_runner_processing`, and `retention_reaps_expired_capture_even_when_history_filters_it`.
- [x] Decode bundles only inside the vault/privacy boundary and construct `PreparationInput` without returning image bytes. The coordinator passes sealed metadata to `AnalysisRunner`; `AnalysisRunner` opens through `Vault`, decodes through `CaptureDecoder`, and hands only `PreparationInput` to `PrivacyGate`. The session fixture decoder exercises image access only inside the vault callback and `cargo test -p qaptr-workflow --test session` passes.
- [x] Run OCR, masking, coverage, and sanitization locally for every eligible capture before any consent/provider step. `AnalysisRunner` performs local privacy preparation for every eligible capture before constructing the consent request or detecting/invoking a provider; the 24-capture integration test asserts all 24 preparations before provider detection, and `cargo test -p qaptr-workflow --test session` passes `twenty_four_captures_prepare_before_provider_and_keep_safe_observations`.
- [x] Aggregate exclusions into one quiet notice per review session, while continuing safely prepared captures. `AnalysisReport` exposes one aggregate exclusion notice while safe captures continue to observations; `cargo test -p qaptr-workflow --test session` passes the 24-capture exclusion scenario and verifies 23 scalar observations plus one notice.
- [x] Stream coarse progress suitable for Swift: ingesting, preparing counts, ready for consent, analyzing, completed, failed, cancelled. `ReviewProgress` defines these bridge-safe states and the FFI driver maps them to scalar JSON state; the coordinator progress tests cover state naming and the review FFI contract suite covers state transitions and cancellation.
- [x] Include exact capture count, prepared count, excluded count, provider, resolved model, and payload kinds in the consent summary. `ConsentRequest` is built after local preparation with capture/prepared/exclusion counts, provider, request-scoped resolved model, and payload kind; `cargo test -p qaptr-workflow --test analyze` passes 13 tests including `consent_receives_request_scoped_resolved_model` and `provider_payload_kind_is_text_without_image_opt_in`.

### 2.2 Consent, retry, cancellation, and error semantics
- [x] Make consent explicit and scoped to one session immediately before the first request. `ConsentPort::request` is called once after every eligible capture has completed local privacy preparation and provider verification, immediately before the first `ProviderGate::invoke`; the immutable `ConsentRequest` carries the request-scoped provider/model and payload summary. `declined_consent_keeps_preparation_local`, `consent_receives_request_scoped_resolved_model`, and `declined_consent_through_coordinator_makes_zero_provider_calls` pass in `cargo test -p qaptr-workflow --test analyze --test session`.
- [x] Verify declined consent results in zero provider invocations and leaves prepared local state non-durable except permitted scalar notices.
- [x] Revalidate provider and resolved model after local preparation and before consent/request dispatch. `AnalysisRunner` now routes the post-preparation boundary through `ProviderGate::revalidate_model`, which performs a fresh provider handshake and adapter-owned model validation before consent; provider contract coverage and the full workflow analysis/session integration suites pass. The active cancellation fixture helper was generalized to accept any `ConsentPort` without changing its safety assertions.
- [ ] Make cancellation cooperative at ingest, preparation, consent, and between provider operations.
- [ ] Ensure provider timeout, malformed output, or cancellation rolls back staged observations and workflows.
- [ ] Define retry to reuse sealed captures safely but never reuse a stale provider/model validation decision without revalidation.
- [ ] Add distinct user-facing messages and recovery actions for unavailable provider, unavailable model, privacy exclusion, provider failure, malformed output, cancellation, and empty honest result.

### 2.3 Persist and expose results safely
- [x] Normalize only schema-valid provider responses into bounded observations and candidate workflows. `ProviderGate` normalizes every raw adapter response through `normalize_response` before it reaches `AnalysisRunner`; malformed fields become a quiet `MalformedOutput` failure, and the workflow acceptance tests persist only normalized scalar observation/workflow values (`1f17cc8`; `cargo test -p qaptr-workflow --test analyze` passes 12 tests).
- [x] Persist observation summaries, workflow summaries, and exclusion notices through `qaptr-store` allowlisted writers only. `AnalysisRunner` writes its staged normalized results through `Store` observation/workflow/notice APIs, which enforce the shared scalar-material guard; store tests cover all writer types and workflow acceptance tests verify persisted scalar rows (`d7d3f4d`, `de99c29`; `cargo test -p qaptr-store` passes 21 tests).
- [x] Confirm the store rejects encoded-image-looking scalar text at every new writer boundary. Capture, observation, workflow, and notice writer coverage rejects PNG-like encoded strings while accepting legitimate scalar text (`d7d3f4d`; `cargo test -p qaptr-store` passes 21 tests).
- [ ] Extend the bridge with coarse operations only: start, progress, grant/decline consent, cancel, retry, observation detail, workflow generation, and export.
- [x] Do not mirror vault, privacy, provider, or raw domain models across the C/Swift bridge. The current C ABI exposes opaque store handles and bounded JSON snapshots/status only, while Swift decodes local DTOs; its contract tests exercise JSON shape rather than sharing Rust domain objects (`6186047`; `swift test --package-path apps/review` passes 65 tests).
- [x] Add bridge contract tests for output shape, errors, no-image invariant, and restart persistence. The FFI suite validates UTF-8 JSON snapshot shape and status, invalid-input/last-error paths, excludes the stored vault record identifier from bridge JSON, and reopens the opaque handle before asserting scalar history survives (`qaptr-review-ffi` 12 tests pass with targeted clippy).

### 2.4 Vertical-slice acceptance tests
- [x] Make the 24-capture fixture run through the production-shaped coordinator using a fake provider behind the real adapter/gate boundary. The coordinator integration test seals 24 real vault bundles, runs the real privacy gate and shared provider gate, and uses a fake provider only at the adapter endpoint (`de99c29`; `cargo test -p qaptr-workflow --test session` passes).
- [x] Assert all local preparation finishes before the fake provider sees a request. The 24-capture adapter checks the decoder counter at provider detection and observes all 24 local preparations before it is allowed to receive a request (`de99c29`; `cargo test -p qaptr-workflow --test session` passes).
- [x] Assert declined consent causes no fake-provider calls. The production-shaped `ReviewSessionCoordinator` integration test seals a real fixture bundle, runs local preparation, records consent, and asserts zero provider invocations after a decline (`6a5592c`; `cargo test -p qaptr-workflow --test session` passes).
- [x] Assert one excluded capture creates exactly one aggregate notice without suppressing observations from safe captures. The 24-capture coordinator test excludes one unsafe context, asserts one notice, and verifies 23 scalar observations persist for safe capture ids (`de99c29`; `cargo test -p qaptr-workflow --test session` passes).
- [x] Assert malformed/failed provider responses produce no partial observation/workflow rows. The analysis integration suite now drives one valid staged result followed by malformed output and asserts that the quiet failed outcome leaves both observations and workflows empty; the provider-failure regression asserts the same for invocation failure (`1f17cc8`; `cargo test -p qaptr-workflow --test analyze` passes 12 tests and targeted clippy passes).
- [ ] Assert a successful fixture run is visible through the same review-app snapshot API as the actual app. The scalar bridge now has focused coverage for a successful fixture-shaped store result: `successful_fixture_result_is_visible_through_snapshot_and_status_apis` verifies observation/workflow counts through both snapshot and status JSON, excludes the vault record id and image/provider material, and keeps live provider analysis honestly unavailable. A true end-to-end successful production-driver run remains blocked because `ProductionResources` intentionally uses `UnavailableProvider` until provider configuration/model validation is wired.

## 3. Provider readiness and model policy

### 3.1 Define typed, durable configuration
- [x] Add a typed, versioned `ModelPolicy` with a single current policy version and explicit fallback ordering.
- [x] Store provider choice and optional explicit model override separately from policy/default resolution. `SettingsPreferences` persists `ProviderChoice` and a normalized optional explicit model override in separate preference keys, while `ModelPolicy` resolves the override independently; `testPersistsAnExplicitModelOverrideSeparatelyFromProvider` locks the contract (`9d61ce1`; `swift test --package-path apps/review` passes 65 tests).
- [ ] Store only non-secret configuration and bounded catalog metadata. Keep the OpenRouter key solely in its Keychain credential boundary.
- [x] Define model-readiness statuses with a concise reason and next action: no provider, provider unavailable, authentication needed, catalog stale/unavailable, preferred unavailable with fallback, override unavailable, ready. `ModelReadiness` now provides typed reason/recovery guidance for all seven states, with no recovery action for ready or safe fallback selection (`cdf2e8b`; 21 policy unit tests pass).
- [ ] Make the resolved provider/model immutable for one consented request and record it in scalar result metadata.

### 3.2 OpenRouter catalog strategy
- [x] Add a bounded OpenRouter model-catalog/configuration transport that uses credentials transiently and never logs or persists the key/response payload. `OpenRouterAdapter::fetch_catalog` enforces the response bound at its public adapter boundary, treats credentials as read-only/transient, redacts adapter debug output, and makes zero transport calls when credentials are absent (`b1f9265`, `1bcb939`; `cargo test -p qaptr-provider-openrouter` passes 14 tests).
- [x] Parse catalog responses defensively, rejecting malformed/unstructured entries and only accepting models that satisfy Qaptr’s structured-output/capability requirements. Parser and public adapter contract tests reject oversized, malformed, and unstructured catalogs without partial results while accepting only capability-qualified models in source order (`b1f9265`, `1bcb939`; `cargo test -p qaptr-provider-openrouter` passes 14 tests).
- [x] Select the versioned preferred model if valid; otherwise select the next validated fallback and emit a clear change notice. `ModelPolicy` tests cover validated preferred selection, deterministic first-valid fallback selection, and typed readiness/change guidance (`cdf2e8b`; `cargo test -p qaptr-policy` passes 32 tests).
- [x] Cache validated catalog entries with a bounded freshness period and invalidate/revalidate before analysis. `OpenRouterCatalogCache` stores one policy-safe `ModelCatalog`, re-reads the current credential on every lookup, serves only within the caller-supplied freshness window, invalidates on expiry/explicit invalidation, and discards stale data after malformed or failed refreshes (`ccf4471`; `cargo test -p qaptr-provider-openrouter` passes 3 unit and 15 contract tests, including expiry, invalidation, conservative refresh failure, and authentication-boundary cases; strict package Clippy and workspace formatting pass).
- [x] Make an unavailable explicit override block analysis with setup guidance rather than falling back silently. `unavailable_override_blocks_resolution_without_falling_back` verifies the typed blocked result and recovery guidance (`cdf2e8b`; `cargo test -p qaptr-policy` passes 32 tests).
- [ ] Do not fetch the catalog merely from provider/model selection UI; model availability validation must be consent-safe and distinctly disclosed.

### 3.3 CLI provider strategy
- [x] Keep the supported provider list limited to OpenRouter, Claude CLI, Codex CLI, and Jcode CLI. `ProviderChoice` is an exact closed enum and its isolated review-core contract test locks the four presentation identifiers (`7fe77b8`; `QaptrReviewCoreTests` target builds cleanly).
- [x] Derive CLI availability from each adapter’s supported detection/authentication capability check. Claude, Codex, and Jcode adapters each probe the executable, version, and documented authentication boundary, returning typed not-installed/not-authenticated outcomes rather than optimistic selection; `cargo test -p qaptr-provider-cli` passes its deterministic suite with only three explicitly environment-dependent real-CLI tests ignored, and targeted clippy passes.
- [x] Do not expose detected-but-unusable CLI providers as selectable. `ProviderDetection::is_usable` now requires location, version, and typed authenticated status before the shared provider gate can verify a provider; contract regressions cover unauthenticated and incomplete detection (`02571ee`; `cargo test -p qaptr-provider --test contract` passes 9 tests).
- [x] Resolve a CLI’s documented default model unless a supported explicit override exists. The policy-level CLI default path resolves without a fallback list, while validated explicit overrides retain precedence (`cdf2e8b`; `cargo test -p qaptr-policy` passes 32 tests). Review-session/consent display wiring remains open below.
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
- [x] Persist the scalar workflow summary through `qaptr-store` and make it visible after relaunch. The FFI snapshot contract now writes a scalar workflow, destroys and reopens the opaque review-store handle, and verifies the same workflow is returned in snapshot JSON (`qaptr-review-ffi` test `snapshot_json_round_trips_scalar_history_after_reopen`; 12 FFI tests and targeted clippy pass).
- [x] Ensure missing sequence/details remain visibly missing rather than inferred.
- [x] Test generation from high, low, and sparse evidence; validate stable IDs and honest confidence/provenance.

### 4.4 Four in-app exports
- [x] Wire canonical Workflow rendering to automation, handoff, onboarding, and SOP Markdown variants.
- [x] Add an app-owned save/export flow that needs no developer path entry and does not launch another application, agent, or automation. `save_markdown_export` accepts an explicit caller-owned destination and one of the four canonical variants, using no default developer path or process-launch API (`63aeadf`; `cargo test -p qaptr-workflow --test export` passes 13 tests). Swift save-panel/bridge wiring remains open.
- [x] Write files atomically and surface cancellation/write errors truthfully. Export saving reuses the vault atomic-write primitive, preserves an existing target on failed replacement, cleans temporary output, and exposes typed destination-aware write and cooperative cancellation errors (`63aeadf`; `cargo test -p qaptr-workflow --test export` passes 13 tests).
- [x] Verify rendered Markdown contains no raw capture material, thumbnails, privacy placeholders, or secrets. Export sanitization now replaces recognized redaction markers with neutral natural-language prose rather than bracketed placeholder tokens; the export safety test rejects both the original marker and the old placeholder while all four golden exports remain stable (`cargo test -p qaptr-workflow --test export` passes 7 tests and targeted clippy passes).
- [x] Add stable golden/snapshot tests for all four export variants, including low-confidence and sparse workflows. `all_exports_match_golden_documents` asserts automation, handoff, onboarding, and SOP Markdown against committed goldens, alongside low-confidence/sparse and byte-determinism coverage (`cargo test -p qaptr-workflow --test export` passes 7 tests and targeted clippy passes).
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
- [x] Remove obsolete sparse/pause/frequency vocabulary from `docs/plans/qaptr-v1.md`, source, tests, and user-visible copy. `CaptureProfileState::Sparse` is now `Interval`; profile docs/tests and the public website now describe one fixed 5–300 second interval, and a case-insensitive scan of `web/src`, the v1 plan, and website design doc finds no prohibited terms (`11af093`; focused policy tests/clippy and `npm --prefix web run build` pass).
- [x] Keep login-item state and permissions live rather than cached as optimistic success. `ReviewAppModel.refreshSettings` queries `ReviewBridge.permissionState` and `loginItemEnabled` on each refresh, and bridge/system tests map the native codes without treating unknown/error as granted (`QaptrReviewCoreTests.testMapsBridgeCodesToTheCorrectStatus`; review package previously passed 65 tests).
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
- [x] Preserve ordinary sampled text, including surnames, while redacting contact PII such as email addresses and phone numbers. `sanitize_text` now keeps surrounding content and replaces only detected email/phone values; deterministic regressions lock ordinary-text preservation and contact-PII redaction (`f60f9d9`; `cargo test -p qaptr-privacy` passes 46 tests).

### 6.2 Credentialed provider evidence
- [ ] On a controlled validation machine, configure an OpenRouter key through Keychain without placing it in source, logs, fixtures, shell history, or reports.
- [ ] Prove OpenRouter detection, catalog/model resolution, consent summary, invocation, normalized response, and result metadata.
- [ ] Run one CLI provider end-to-end with its existing authenticated session and document the boundary used.
- [ ] Run the four-provider observation flow only where each provider can be authentically validated; record unavailable providers as blocked with reason rather than fabricating completion.
- [ ] Scrub all reports and artifacts for credentials, raw provider payloads, and raw capture material.

## 7. Packaging and release validation

### 7.1 Packaged-app coverage
- [x] Extend U23/release checks to require a real helper-generated capture and review-session result, not an idle app launch. `release_validate.sh` delegates to `validate_release_evidence.sh`, which accepts only explicit externally produced helper-capture and review-result records and otherwise reports `BLOCKED`, never passing idle app evidence (`6f1b821`; `bench/scripts/test_validate_release_evidence.sh` passes).
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
- [x] The coordinator persists newly ingested scalar capture metadata before retention, filters reaped inputs before analysis, and passes the request-scoped resolved model into the consent request. `first_run_retention_reaps_ingested_capture_before_runner_processing` and `consent_receives_request_scoped_resolved_model` cover the ordering and disclosure boundaries (`e659c44`; independently rerun `cargo test -p qaptr-workflow --test analyze --test session` passes 17 tests and targeted clippy passes). This is an underlying workflow prerequisite, not yet the app-owned review-driver acceptance row.
- [x] `bench/scripts/external_acceptance_preflight.py` validates a scrubbed evidence manifest for the remaining permission-, credential-, hardware-, and signing-dependent rows without requesting permissions, reading credentials, using the network, or treating fixtures as external proof. Its 7-test suite verifies blocked-default, evidence-complete, scrubbed-output, and nonzero-blocked behavior (`a2a0386`; independently rerun `python3 -m unittest bench/tests/test_external_acceptance_preflight.py` passes). It records blockers rather than closing the external acceptance rows.
- [x] Detailed-capture core now has an explicit start/stop and bounded 5–300-second interval seam, persisted scalar interval state, and truthful unavailable, permission-denied, and startup-failure outcomes (`481d8f1`; independently rerun `swift test --package-path apps/helper` passes 23 tests and `swift test --package-path apps/review` passes 73 tests). This supports rows 137–140 but does not close their real helper RPC and production-view wiring requirements.
- [x] Sealed bundle decoding now accepts bounded scalar context and PNG inputs only through `OpenedBundle::with_image_for_privacy`; local exact-image recognition stages a 0700/0600 temporary PNG and deletes it before return, while the FFI exposes only a text-first `PreparationInput`, never image bytes (`2a583fd`; independently rerun `cargo test -p qaptr-macos` passes 12 executed tests with 3 real-system tests explicitly ignored, and `cargo test --manifest-path crates/qaptr-review-ffi/Cargo.toml` passes 18 tests; strict clippy passes for both crates). This supplies the local boundary for rows 63–64 but does not close the app-owned coordinator/driver integration.
- [x] Provider settings visibly distinguish a Keychain key that is merely saved from a provider connection that this process has actually verified. A saved OpenRouter key now displays `Key saved` with a verification action, while only a successful explicit check displays `Connected`; saved-but-unverified state remains unusable for onboarding (`swift test --package-path apps/review` passes 74 tests). CLI readiness and review-driver catalog validation remain separate open work.
- [x] Re-selecting OpenRouter with a saved key no longer reopens the setup sheet. The app offers an explicit accessible `Change key` action instead, while preserving the truthful distinction between `Key saved` and network-verified `Connected` (`fcb74e9`; review Swift tests passed 89 tests in the scoped validation).
- [x] The release package now embeds `QaptrHelper.app` as the Review app's login item, targets the helper's bundle identifier with `SMAppService`, and asks the user before launching periodic local capture after onboarding. A clean-checkout package build verified the helper executable and nested signatures, and the deterministic packaged fixture smoke passed (`db91c5c`). The installed `/Applications/Qaptr.app` was updated from that verified package. Real Screen Recording permission and a real sealed capture remain external acceptance work.
- [x] `5eb9da2` adds review-driver replay, retry, retention/history, cancellation, and consent regressions; `7e79fd5` restores clean Rust formatting for that scoped source. Fresh public-boundary evidence on 2026-08-16: the follow-up `4408ec1` makes the C ABI replay boundary use an explicit caller request token and keeps failed/incomplete capture metadata retryable after SQLite reopen. With the installed Rust 1.97.1 toolchain, `cargo fmt --manifest-path crates/qaptr-review-ffi/Cargo.toml -- --check`, strict review-FFI Clippy, `cargo test --manifest-path crates/qaptr-review-ffi/Cargo.toml` (50/50), focused workflow analysis/session tests (13/13 and 8/8), and strict workflow Clippy all pass. This closes the scoped Rust replay/retry recovery evidence only; it does not claim Swift wiring, real capture, credentials, provider acceptance, or external release acceptance.
- [x] OpenRouter now has a bounded one-entry cache for its policy-safe `ModelCatalog` projection. Every lookup still authenticates from the credential port, cache hits are bounded by a caller-supplied freshness window, and expiry, malformed refreshes, transport failures, and explicit invalidation never serve stale data. Independently rerun `cargo test -p qaptr-provider-openrouter`, `cargo test -p qaptr-policy`, strict OpenRouter clippy, and workspace formatting pass (`ccf4471`). App-driver use of this cache and review model-selection UI remain open.
- [x] Helper startup now owns its Screen Recording preflight and persists versioned scalar startup/progress state before capture scheduling. Permission denial is surfaced by the helper itself, successful startup is recorded, and explicit-capture/login-item behavior is unchanged (`0ec9838`; `swift test --package-path apps/helper` passes 25 tests). This is helper-core evidence only: real Screen Recording consent and Review UI consumption remain open.
- [x] The native Review package now includes `ApplicationCatalog.swift` in committed source, and native Settings entry is gated by the shared onboarding completion policy (`3fed4cb`, `2f6438b`). A clean `git archive` Review package test passes 92/92 tests, and `packaging/release.sh --dry-run --skip-reproducibility` builds, signs, verifies nested signatures, and creates the DMG. This closes the prior compile/settings-entry audit finding only. It does not close real helper startup, Screen Recording, provider readiness, or review-driver acceptance.
- [ ] Production onboarding/provider audit: the package embeds the helper, but onboarding can complete before helper registration/startup is proven; capture permission is requested for the Review identity while the helper separately preflights its own permission; attached displays are treated as selected; provider verification can run before the final privacy stage; and the packaged bridge remains read-only with `UnavailableProvider`, so post-onboarding analysis is unavailable. CLI detection is now exposed only as a bounded, read-only readiness snapshot: it omits executable paths, environment data, credentials, and process output, and never labels a path-only detection usable (`753a547`; independently rerun review Swift tests pass 98/98 and provider-cli detection tests pass 4/4). A visible CLI readiness UI and all other listed onboarding/provider gaps remain open. Scoped package/FFI tests and the packaging dry run are implementation evidence, not external acceptance.
- [x] Provider/model revalidation boundary: `ProviderGate::revalidate_model` performs a fresh provider handshake and invokes an adapter-owned model-validation hook after local preparation, while `AnalysisRunner` uses its returned fresh proof before consent (`crates/qaptr-provider/src/adapter.rs:407-501`, `crates/qaptr-workflow/src/analyze.rs:389-403`). The provider contract suite passes 10/10, workflow analysis passes 14/14, workflow session passes 8/8, and strict focused Clippy passes. No provider or credential data was used.
- [x] Final deterministic gates for this pass: fail-fast `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test --workspace`, and `cargo doc --workspace --no-deps` passed; Review Swift tests passed 98/98; Helper Swift tests passed 25/25; the helper product build passed directly with an explicit Cargo path; and `packaging/release.sh --dry-run --skip-reproducibility` built, ad-hoc signed, verified nested apps, and created the DMG. A combined Helper Swift command also attempted its nested product build but exited when that test environment omitted Cargo from PATH; the direct build reproduced the same product boundary successfully. These validate code and deterministic packaging only; they do not close permission-, credential-, hardware-, signing-, or soak-dependent rows.

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
