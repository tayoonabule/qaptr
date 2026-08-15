# U20 opened-app memory measurement

**Date:** 2026-08-15 UTC
**Result:** the production `QaptrReview.app` release build stays far under the R-C7 opened-app budget in a cold-launch smoke measurement.

## Scope and limitation

This is a **smoke measurement**, not the plan's full opened-app budget assertion. The Measurement protocol's Opened-app budget (R-C7) specifies a 10-minute scripted review session against a committed 24-capture fixture: open, analyze the fixture session, open three observations, generate one workflow, and export all four Markdown formats. That fixture, its scripted driver, and the full end-to-end analysis/export flow are U17/U19's already-landed logic wired through U23's release-validation suite, not something this unit re-implements or re-drives. U20 only builds the review UI and its native FFI bridge; it does not own the fixture session or the release-validation harness.

What this measurement does show: the actual compiled SwiftUI review app, opened cold with a freshly-created, effectively-empty durable-history SQLite WAL database (no prior `history.sqlite3` existed on this machine before the first run), idling on the Observation Sheet's empty state.

## Command

```sh
bash bench/scripts/review_budget.sh --seconds 20
```

The script builds `qaptr-review-ffi` in release mode, builds and bundles `QaptrReview.app` via `apps/review/build_app.sh release`, launches the real production executable (not a probe), samples `footprint --noCategories -f bytes` on the app's process once per second for 20 seconds, and reports the median and peak `phys_footprint` exactly as the plan's Measurement protocol defines it (not RSS).

## Reference machine

- MacBook Air (`Mac17,4`), Apple M5, 24 GB RAM, arm64
- macOS 27.0, build `26A5388g`
- Swift 6.3.3, Rust 1.97.1

This matches the machine used for U3's shell-shape spike and U4's capture-cost spike; it is not the plan's release reference configuration of 16 GB with an attached 5K display.

## Measurement

| Metric | Result | R-C7 budget |
|---|---:|---:|
| Samples | 20 (once per second) | — |
| Median `phys_footprint` | **29.118 MiB** | < 150 MiB |
| Peak `phys_footprint` | **30.032 MiB** | < 180 MiB |
| First frame paint (cold launch) | recorded via `QAPTR_REVIEW_PAINT_FILE`; consistent with U3's ~150–200 ms SwiftUI first-paint measurements | Informational for this smoke run; the plan's 1200 ms cold-launch budget is asserted against the full scripted session, not this smoke run |

Both numbers sit close to U3's own trivial-probe measurement (25.75 MiB median / 26.52 MiB peak), which is expected: U20's Observation Sheet, Settings, and Onboarding views add a small, mostly-text SwiftUI view tree over the same native shell U3 measured, plus one dynamically-loaded native library (`libqaptr_review_ffi.dylib`, ~2.4 MB on disk) and a real bundled-SQLite WAL-mode connection to the durable-history store, with no additional resident cost that approaches the budget.

## What this does not prove

- The full 24-capture fixture session, three-observation open, one workflow generation, and four-export flow are not exercised here. That full-session measurement belongs to U23's release-validation suite once the fixture exists.
- Peak memory during active analysis (which is owned by U17, already landed) is not measured by this script; `review_budget.sh` measures the opened, idling app.
- This is a single run, not the plan's three-consecutive-run regression rule. `bench/scripts/review_budget.sh` is reusable for that purpose once U23 wires it into the full release-validation sequence.

## Verification pointer

`bash bench/scripts/review_budget.sh` is a new, runnable, standalone script following the same shape as `bench/scripts/capture_soak.sh`. It can be re-run by U23 as part of `bench/scripts/release_validate.sh` once the fixture-driven scripted session exists, and can be re-run today for a same-shape regression check on an idling opened app.
