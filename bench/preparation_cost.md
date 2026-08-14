# U12 full preparation measurement

## Scope

This is the U12 end-to-end preparation measurement. It times the complete local
pipeline: U9 recognition through the real macOS OCR and Vision ports, U10
mapping, masking, and coverage verification, and U11 structured-context
sanitization. It does not time any provider request.

The prepared-payload proof carries U9's measured recall disclosure. U9 measured
**5/6 = 0.833 recall**, with the low-contrast text region as the known miss. That
is a limitation of what the recognizers report, not a claim that the image is
secret-free.

## Reference machine

Measured 2026-08-14 UTC on the same reference machine as U9:

- MacBook Air, Apple M5, 24 GB RAM
- macOS 27.0, build 26A5388g
- Built-in Retina display, 2880 x 1864
- Rust 1.97.1, Swift 6.3.3 / Xcode 26.6

## Reproducible procedure

The run uses 24 sequential captures cycling through the committed U9 fixture
session: `text`, `rotated`, `no_text`, `single_color`, and `low_contrast`.
Each capture is passed through `PrivacyGate::prepare` with:

- the real `MacOcr` and `MacVision` ports;
- a 1600 x 1000 RGB image, matching the U9 recognition input size;
- image sending explicitly opted in, so U10 masking and proof verification run;
- structured context containing an email and credential shape for U11;
- the 900 ms U12 budget.

The ephemeral measurement harness used path dependencies on the three core
crates and was run from the repository root with `cargo run --release`. The
privacy crate deliberately does not depend on `qaptr-macos`, so the harness is
kept outside the workspace to avoid a dependency cycle. The committed
`measured_gate_pipeline_stays_within_full_budget` test provides the hermetic
core-pipeline check; this file records the real adapter-backed run required by
U12.

Three consecutive recorded runs used 24 samples each:

| run | samples | median | peak | budget |
|---:|---:|---:|---:|---:|
| 1 | 24 | 153.237 ms | 190.791 ms | median < 900 ms |
| 2 | 24 | 154.688 ms | 170.286 ms | median < 900 ms |
| 3 | 24 | 154.631 ms | 162.962 ms | median < 900 ms |

The median of the three run medians was **154.631 ms**. The largest sample in
those recorded runs was **190.791 ms**. All three runs passed the 900 ms median
budget. These are measured values, not estimates.

The first post-build exploratory invocation had a 446.269 ms peak while warming
the compiled helper process. It was not included in the three-run result above;
the recorded runs follow the plan's warm-helper procedure.

## Interpretation and confidence

Confidence is **high for this reference configuration and fixture session**.
The measurement includes real local OCR/Vision process work and all three U12
stages, but it does not establish perfect recognizer recall. The labeled corpus
is intentionally small and retains the published low-contrast miss.

The gate refuses to emit on typed recognition errors and timeouts, partial
recognition, masking or coverage failures, sanitizer errors, and an observed
end-to-end deadline overrun. No prepared payload can be constructed outside the
gate: its fields and constructor are private to the privacy crate, and a
`compile_fail` doctest asserts that external callers cannot invoke the
constructor.
