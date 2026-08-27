# Figma Main App state matrix

Authoritative root: `Main App` canvas `2:12` in Qaptr Figma file. All primary review frames are 845 x 737 points. The menu-bar board is 400 x 480 and the toast specification board is 560 x 360.

## Traversal inventory

| Area | Figma roots | Implemented native surface |
|---|---|---|
| Onboarding | `10:22` screen-recording permission, `27:1034` not yet requested, `27:1069` denied | `WelcomeView` with permission-driven copy, CTA, privacy footer, and system-settings recovery |
| Home | `13:22` empty, `13:46` findings, `13:93` paused, `13:140` attention, `13:194` analyzing, `11:113` ready, `11:137` quiet result, `11:183` context nudge, `65:110` watching closely, `65:164` done watching | `WorkflowSuggestionsView` / `HomeReviewView`, status toolbar, findings feed, banners, detailed-capture actions |
| Consent | `29:6533` review, `29:6593` choose provider | `ConsentReviewView`, provider selection, explicit approve/decline boundary |
| Finding detail | `34:248` complete, `36:141` incomplete, `36:175` correction, `65:225` saved | `FindingDetailView`, suggestion/correction/save actions and honest unavailable messaging |
| Settings | `29:6787` baseline, `61:107` never-capture sheet | `SettingsView`, capture/privacy/provider sections, exclusion editor |
| Menu bar | `66:128` capturing, `66:151` attention, `66:174` detailed, `66:197` approval | `QaptrMenuBarView` with state-specific status and actions |
| Transient feedback | `66:220` toast spec | `ReviewToastView`, bottom-center placement, three-second dismissal |

## Token bindings

Figma variables were resolved before metadata/context inspection. Native code binds repeated values through the existing Qaptr design tokens and the Figma-derived constants: SF Pro global body sizing, 24-point control height, 16-point button horizontal padding, 6-point button radius, blue/orange/red accents, vibrant secondary fill, primary label, and liquid-glass opacity/dispersion/depth behavior. Existing font and logo resources remain authoritative vector boundaries.

## Requirement-to-check traceability

| Requirement / changed output | Concrete check | Observed result |
|---|---|---|
| Figma variables precede node details | `get_variable_defs(2:12)` before `get_metadata(2:12)` and context calls | Passed. Variable map returned SF Pro, button, accent, fill, radius, and liquid-glass values first. |
| Complete Main App state inventory | `get_metadata(2:12)` plus the root inventory above | Passed. Onboarding, home, consent, detail, settings, menu bar, and toast roots recorded. |
| Onboarding permission states | `QaptrReview` release launch with `QAPTR_REVIEW_SURFACE_FILE`; direct packaged screenshot | Passed for the observed not-yet-requested onboarding state. Surface probe returned `review` after the app transitioned. |
| Home empty/ready/finding/paused/attention/analyzing/detail states | `ReviewWorkspaceState` resolver tests plus 845x737 Figma context and native screenshot | Passed for resolver coverage and the observed onboarding/ready composition. Per-state pixel overlays are blocked by missing deterministic state injection. |
| Consent and provider boundary | Review Swift tests `AnalysisConsentPresentationTests`, `AnalysisSessionModelTests`, `ProviderSelectionTests` | Passed. Explicit consent, decline, provider readiness, and no-provider behavior are covered. |
| Settings and never-capture behavior | Review Swift tests `CaptureSettingsPresentationTests`, `SettingsEntryPolicyTests`, `SettingsViewOpenRouterReadinessTests`; packaged smoke fixture | Passed. Settings policy and provider readiness tests pass; packaged smoke confirms the shipped bundle loads. |
| Menu bar public interface | Release package launch, `QaptrReviewApp.swift` `MenuBarExtra` wiring, and packaged smoke login-item probe | Passed. The outer `Qaptr.app` launched as a background/menu-bar app with no ordinary windows, which matches the LSUIElement/menu-bar contract; `qaptr_login_item_status` returned documented code `0`. |
| Privacy and local-only guarantees | `AnalysisConsentPresentationTests`, `ReviewSessionStateDecoderTests`, packaged smoke `provider_requests=0` | Passed. Fixture run observed zero provider requests before explicit consent and valid local review outputs. |
| Persistence and integrations | Full review/helper Swift suites, Rust workspace tests, packaged fixture smoke | Passed. 196 review tests, 37 helper tests, Rust workspace tests, and the real shipped-bundle smoke all passed. |
| Release packaging and signatures | `apps/review/build_app.sh release` and `bench/scripts/packaged_fixture_smoke.sh` | Passed. Outer `Qaptr.app` and nested helper validate on disk and satisfy designated requirements. |
| Visual fidelity at exact dimensions | Figma screenshot/context for `11:113`, native screenshot of onboarding frame | Partially passed. Exact 845x737 framing was observed for the primary composition; complete all-state screenshot/diff coverage remains blocked by runtime state injection. |



## Whole-result acceptance rerun (2026-08-27)

The committed result was re-run through the real packaged path, not only unit tests:

| Requirement / changed output | Acceptance path exercised | Observed result |
|---|---|---|
| Figma root geometry and Home surface | Built and launched the current executable; observed the Qaptr window at `845 × 737`; captured the live Home surface | Pass. The current binary rendered the rebuilt Home surface at the Figma frame size. |
| Home state presentation | Ran the real executable with `QAPTR_DEV_MOCK_DATA=1`; observed capture status, optional-context banner, findings cards, Analyze, and Settings | Pass for the reachable fixture state. Every Figma variant cannot be driven live because the product has no public deterministic state injection. Resolver tests cover the remaining transitions. |
| Settings presentation and navigation | Clicked Settings from the live Home window; observed Capture, Privacy, Never capture, and Analysis cards; returned/relaunched | Pass. The same Figma-sized window rendered the rebuilt Settings surface with no legacy Form surface. |
| Onboarding, consent, provider, finding detail, correction, and save boundaries | Full review Swift suite, including permission, consent, provider selection, cancellation, unavailable provider, typed finding actions, and persistence cases | Pass. Explicit approval remains required, privacy-safe summaries remain scalar, and unavailable correction remains honest. |
| Settings persistence and helper integration | Review/helper Swift suites plus packaged smoke | Pass. Settings and helper integration completed against real package interfaces. |
| Menu bar public interface | Release package smoke launched outer `Qaptr.app`, checked login-item behavior, and validated the nested helper | Pass. `login_item_status_code=0`; outer app, helper, and dylibs were valid on disk and satisfied designated requirements. |
| Privacy/local-only guarantee | Packaged fixture smoke before and after explicit consent | Pass. `provider_requests=0` before consent; smoke completed with `review_observations=1`, `review_workflows=1`, and `exports=4`. |
| Packaging and release boundaries | `apps/review/build_app.sh release` and `bench/scripts/packaged_fixture_smoke.sh` | Pass. Release build, signing, dylib loading, nested helper validation, package launch, and login-item probe completed. |
| Typography, spacing, colors, glass, vectors | Figma `11:113` reference capture and live Home/Settings screenshots after relaunch | Pass for the inspected reachable surfaces and visibly improved after deleting legacy wrappers. A machine pixel diff remains blocked because Figma returned inline-only image data and the desktop screenshot tool exposed no writable PNG path. |

This rerun closes the real public acceptance loop for reachable workflows. The remaining constraint is exhaustive live rendering of every Figma state without a synthetic state injector or safely manufacturing TCC/provider failure states on the host.
