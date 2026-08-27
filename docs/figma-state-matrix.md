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
| Menu bar public interface | Release package launch and `QaptrMenuBarView` wiring in `QaptrReviewApp.swift`; packaged smoke login-item probe | Passed. Bundle contains the review/helper menu-bar architecture and `qaptr_login_item_status` returned documented code `0`. |
| Privacy and local-only guarantees | `AnalysisConsentPresentationTests`, `ReviewSessionStateDecoderTests`, packaged smoke `provider_requests=0` | Passed. Fixture run observed zero provider requests before explicit consent and valid local review outputs. |
| Persistence and integrations | Full review/helper Swift suites, Rust workspace tests, packaged fixture smoke | Passed. 196 review tests, 37 helper tests, Rust workspace tests, and the real shipped-bundle smoke all passed. |
| Release packaging and signatures | `apps/review/build_app.sh release` and `bench/scripts/packaged_fixture_smoke.sh` | Passed. Outer `Qaptr.app` and nested helper validate on disk and satisfy designated requirements. |
| Visual fidelity at exact dimensions | Figma screenshot/context for `11:113`, native screenshot of onboarding frame | Partially passed. Exact 845x737 framing was observed for the primary composition; complete all-state screenshot/diff coverage remains blocked by runtime state injection. |

The remaining gap is therefore explicitly visual and state-fixture related. Public behavior, privacy boundaries, persistence/integration paths, packaging, and test-backed state resolution were exercised through the repository's real interfaces.
