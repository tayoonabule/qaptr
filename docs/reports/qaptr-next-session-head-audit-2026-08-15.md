# Qaptr next-session checklist audit against HEAD

**Audited revision:** `02b6d60` (`test(review): cover capture status readiness states`)

This report records only checklist items that are fully supported by code or tests already committed at HEAD. No source files were changed for this audit.

## Completed evidence

| Checklist item | Evidence at HEAD |
| --- | --- |
| 1.1 versioned scalar capture-status schema | `CaptureProgress` is schema version 1 and contains attempt/success timestamps, successful count, selected display IDs, active interval, state, failure reason, revision, and update timestamp (`apps/helper/Sources/QaptrHelperCore/CaptureCore.swift:299-395`). |
| 1.1 scalar-only schema | The schema has scalar fields only, and `testCaptureProgressV1RoundTripsFieldsWithoutImages` asserts the persisted JSON contains no image fields (`apps/helper/Tests/QaptrHelperTests/CaptureCoreTests.swift:36-66`). |
| 1.1 atomic/unavailable status behavior | Helper writes use `.atomic` (`CaptureCore.swift:576-595`); missing or malformed review status maps to `.unavailable` without an invented count (`apps/review/Sources/QaptrReviewCore/CaptureProgress.swift:112-121,215-216,306-317`; `CaptureProgressTests.swift:23-34`). |
| 1.1 monotonic freshness marker | Every tracker transition increments `revision` and updates the timestamp (`CaptureCore.swift:419-573`), covered by `testCaptureProgressCountsOnlySuccessfulSealsAcrossStates` and `testTrackerTransitionsCarryV1FieldsAndConciseFailureReason`. |
| 1.2 six truthful capture states | `CaptureReadiness` contains exactly the six required states, with a total mapping from persisted state/evidence (`CaptureProgress.swift:251-303`). |
| 1.2 successful count/time only after a sealed capture | The production helper counts only `.sealed` events before updating success count/time (`apps/helper/Sources/QaptrHelper/main.swift:297-349`), covered by `testCaptureProgressCountsOnlySuccessfulSealsAcrossStates`; the review UI renders those scalar fields (`ObservationSheetView.swift:70-96`). |
| 1.2 actionable failure reason | `actionableReason` prefers the bounded helper reason and otherwise supplies one concise recovery-oriented reason (`CaptureProgress.swift:273-290`), covered by `testActionableReasonPrefersHelperSuppliedReasonOverGenericCopy`. |
| 1.2 status decoding/state tests | `CaptureProgressSnapshotTests` covers absent, malformed, stale process, denied permission, no displays, disk failure text, waiting, capturing, and successful ready states (`apps/review/Tests/QaptrReviewCoreTests/CaptureProgressTests.swift:23-166`). |
| 1.3 every visible capture state has review-core tests | The same test suite exercises every `CaptureReadiness` case and the forward-compatible v1 field decoder (`CaptureProgressTests.swift:60-166`). |
| 1.3 helper has no OCR/provider integration | A source scan of `apps/helper` found no OCR, provider, `qaptr-provider`, or `qaptr-privacy` import/call. The helper remains limited to capture/sealing/status responsibilities. |
| 2.2 declined consent invokes no provider | `declined_consent_keeps_preparation_local` asserts one explicit consent request, zero provider invocations, and zero durable observations (`crates/qaptr-workflow/tests/analyze.rs:512-533`). |
| 3.1 typed versioned model policy | `ModelPolicy`, `PolicyVersion::CURRENT`, ordered fallbacks, and explicit override resolution are implemented (`crates/qaptr-policy/src/model_policy.rs:64-125,275-323`) and covered by version, fallback-order, unavailable-override, and CLI-default tests (`model_policy.rs:343-532`). |
| 4.1 low confidence remains uncertain | Observation rows/details display the computed confidence band, and `testNeverInventsCertaintyForAZeroScore` requires “Low confidence” (`ObservationSheetView.swift:121-169`; `QaptrReviewCoreTests.swift:5-24`). |
| 4.3 canonical Workflow generation | `WorkflowDocument::from_observation` and `from_candidate` accept durable scalar evidence and preserve missing material (`crates/qaptr-workflow/src/document.rs:19-136`). |
| 4.3 missing sequence stays missing | Both constructors leave unobserved steps/details empty; export tests assert “No steps were captured” and reject invented steps (`crates/qaptr-workflow/tests/export.rs:143-182,214-273`). |
| 4.3 high/low/sparse generation evidence | Export tests cover a high-confidence candidate, a low-confidence observation/workflow, a sparse unknown-confidence workflow, stable IDs, and provenance (`export.rs:143-182,214-273`). |
| 4.4 four Markdown renderers | Automation, handoff, onboarding, and SOP renderers all consume `WorkflowDocument`; tests prove deterministic, distinct output (`export.rs:106-141`). |
| 4.4 snapshot tooling requirement | Golden files use Rust's built-in `include_str!` assertions (`export.rs:196-212`), so no external snapshot tool is required in CI or local development. |
| 5.1 truthful onboarding explanation | `OnboardingCopy` explains periodic capture, local preparation, provider transmission, and per-session just-in-time consent (`apps/review/Sources/QaptrReviewCore/OnboardingCopy.swift:3-47`), with focused tests (`QaptrReviewCoreTests.swift:224-269`). |

## Deliberately left open

The audit did not close items requiring unknown-enum-state decoding, exhaustive `CaptureEvent` mapping tests, selected-display controls, app wiring for `ReviewSessionCoordinator`, model catalog transport, request-boundary model revalidation, app-owned export/save flows, real hardware/permission/credential evidence, signing, or soak/performance runs.

No test suite was rerun during this documentation-only audit. The evidence above points to committed tests and implementation at the audited HEAD.
