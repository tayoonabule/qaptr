# U9 OCR and Vision measurement

## Scope

This file records the U9 recognition share only. It does **not** measure the 900 ms
full-preparation budget. Masking and context sanitization belong to U10 and U12.
The adapters run Apple's on-device Vision framework through the compiled local
Swift helper. No network API, URL session, or provider code is involved.

## Reference machine

Measured 2026-08-14 UTC on:

- MacBook Air, Apple M5, 24 GB RAM
- macOS 27.0, build 26A5388g
- Built-in Retina display, 2880 x 1864
- Rust 1.97.1, Swift 6.3.3 / Xcode 26.6

## Reproducible procedure

The integration test measures 24 sequential OCR recognitions over the committed
fixture session, timing only `MacOcr::recognize` for each capture. The five OCR
fixture images are 1600 x 1000 PNGs at the recognition input size: normal text,
rotated text, no text, a single-color image, and deliberately low-contrast text.
The QR/barcode fixture is exercised by the detector and recall tests separately.
The helper is warmed by the first measured invocation, but every recognition
includes the local helper process startup and Vision work.

```sh
for run in 1 2 3; do
  cargo test -p qaptr-macos --test ocr_integration \
    recognition_budget_is_measured_on_the_committed_fixture_session -- --nocapture
done
```

## Results

| run | samples | median | peak | budget |
|---:|---:|---:|---:|---:|
| 1 | 24 | 68.994 ms | 121.516 ms | median < 500 ms |
| 2 | 24 | 64.845 ms | 95.277 ms | median < 500 ms |
| 3 | 24 | 65.243 ms | 93.127 ms | median < 500 ms |

The median of the three recorded run medians was **65.243 ms**. The largest
observed sample was **121.516 ms**. All three runs passed the 500 ms median gate.
These are measured values, not estimates.

## Human-labeled recall

The committed corpus is `crates/qaptr-privacy/fixtures/ocr/ground_truth.csv`.
Labels were written by hand before running recognition and include five positive
regions plus one intentionally difficult low-contrast text region. The measured
result was **5/6 = 0.833 recall**. The recognizer missed:

- `low_contrast.png`: `Low contrast secret label`

The negative `no_text.png` and `single_color.png` fixtures returned empty OCR
successes. The QR fixture produced a barcode finding with geometry. The corpus
is deliberately small and is not evidence of perfect recall. Face detection is
implemented in the Vision adapter, but this U9 corpus does not claim a human
face recall result because no non-synthetic face image was committed.

## Verification notes

- OCR failures become `DomainError::Failed`.
- Deadline expiry becomes `DomainError::TimedOut`, never an empty result.
- Empty and single-color images return complete empty results.
- Recognition results include Vision-normalized geometry; `qaptr-privacy` owns
  the single tested mapping function to pixel space.
- The full preparation budget remains unmeasured here by design and is owned by
  U12 after masking and sanitization exist.
