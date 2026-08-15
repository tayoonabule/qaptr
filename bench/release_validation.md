# U23 release validation

**Run:** `2026-08-15T03:00:22Z`
**Overall:** **BLOCKED**
**Output directory:** `/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z`

This report is intentionally evidence-first. `UNVERIFIED` is not a pass or a fail; it means this machine cannot prove the release claim. A blocked release is reported as blocked rather than being made green by weakening a gate.

## Machine configuration

```text
validated_commit=484de89cf9b386c799cc7ebb0313e1aea2ecc02d
date_utc=2026-08-15T02:58:49Z
uname=Darwin MacBook-Air.local 27.0.0 Darwin Kernel Version 27.0.0: Tue Jul 14 21:40:57 PDT 2026; root:xnu-13432.0.94.501.4~1/RELEASE_ARM64_T8142 arm64
arch=arm64
sw_vers:
ProductName:		macOS
ProductVersion:		27.0
BuildVersion:		26A5388g
sysctl:
Mac17,4
25769803776
rustc=rustc 1.97.1 (8bab26f4f 2026-07-14)
swift:
swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
Target: arm64-apple-macosx28.0
xcodebuild:
Xcode 26.6
Build version 17F113
displays:
Graphics/Displays:

    Apple M5:

      Chipset Model: Apple M5
      Type: GPU
      Bus: Built-In
      Total Number of Cores: 10
      Vendor: Apple (0x106b)
      Metal Support: Metal 4
      Displays:
        Color LCD:
          Display Type: Built-in Liquid Retina Display
          Resolution: 2880 x 1864 Retina
          Main Display: Yes
          Mirror: Off
          Online: Yes
          Automatically Adjust Brightness: No
          Connection Type: Internal

```

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| `fixture_session` | **PASS** | captures=24 image_size=1600x1000 manifest=/Users/light/Documents/GitHub/qaptr/fixtures/session/manifest.csv |
| `rust_format` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/rust_format.log |
| `rust_lint` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/rust_lint.log |
| `rust_tests` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/rust_tests.log |
| `rust_docs` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/rust_docs.log |
| `macos_os_integration` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/macos_os_integration.log |
| `helper_tests` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/helper_tests.log |
| `real_vision_preparation` | **FAIL** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/real_vision_preparation.log |
| `image_provenance` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/image_provenance.log |
| `history_encoding` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/history_encoding.log |
| `fresh_store_bootstrap` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/fresh_store_bootstrap.log |
| `fresh_install_bootstrap` | **UNVERIFIED** | no clean-machine packaged-app install, permission, login-item, and first-review-state driver exists |
| `review_session_driver` | **FAIL** | current review app has capture-progress/settings and read-only durable history, but no analyze/detail/workflow/export driver exists |
| `review_budget_smoke_1` | **FAIL** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/review_smoke_1.log |
| `review_budget_smoke_2` | **FAIL** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/review_smoke_2.log |
| `review_budget_smoke_3` | **FAIL** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/review_smoke_3.log |
| `helper_soak` | **PASS** | median_mib=5.922 peak_mib=5.969 skips=0 log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/helper_soak.log |
| `privacy_payload_proof` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/privacy_payload_proof.log |
| `privacy_gate_refusal` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/privacy_gate_refusal.log |
| `privacy_corpus` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/privacy_corpus.log |
| `provider_contract` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/provider_contract.log |
| `openrouter_contract` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/openrouter_contract.log |
| `cli_contract` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/cli_contract.log |
| `provider_codex_real_detection` | **PASS** | Codex CLI 0.147.0 installed and sandboxed detection passed log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/provider_codex.log |
| `provider_jcode_real_detection` | **PASS** | Jcode CLI 0.75.23 installed and sandboxed detection passed log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/provider_jcode.log |
| `provider_claude_real_detection` | **UNVERIFIED** | genuine Claude CLI and version reached; sandbox cannot verify Keychain-backed auth without granting Keychain access log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/provider_claude.log |
| `provider_openrouter_real_detection` | **UNVERIFIED** | no OpenRouter credential is configured; only the in-process contract is proven |
| `helper_link_audit` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/helper_link_audit.log |
| `export_snapshots` | **UNVERIFIED** | cargo-insta is not installed on this machine |
| `web_checks` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/web_checks.log |
| `web_accessibility` | **PASS** | log=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/logs/web_accessibility.log |
| `packaging` | **UNVERIFIED** | not run by U23; dry-run is credential-free, but Developer ID signing, notarization, stapling, Gatekeeper, and fresh-profile persistence still require release credentials and a clean runner |

## Measurements and interpretation

- **Helper:** U4 previously measured **5.860 MiB median**, **5.922 MiB peak**, 118 captures, and zero skipped ticks on a 600-second accelerated soak. U23 also runs `capture_soak.sh` through the single entry point; its exact current summary is in the gate log above. Both are far below the 50 MiB budget, but neither is a 12-hour run on the 16 GB plus 5K reference machine.
- **U23 helper soak:** `capture_soak.sh` measured duration_seconds=36;samples=34;median_phys_footprint_bytes=6210184.000;median_phys_footprint_mib=5.922;peak_phys_footprint_bytes=6259336;peak_phys_footprint_mib=5.969;captures=14;median_capture_latency_ms=49.598;peak_capture_latency_ms=141.180;median_single_capture_latency_ms=50.659;peak_single_capture_latency_ms=141.180;median_multiple_capture_latency_ms=39.957;peak_multiple_capture_latency_ms=50.030;median_single_set_latency_ms=51.172;peak_single_set_latency_ms=164.159;median_multiple_set_latency_ms=40.014;peak_multiple_set_latency_ms=53.935;ticks=7;skips=0;median_tick_latency_ms=131.367;peak_tick_latency_ms=240.503;results_dir=/Users/light/Documents/GitHub/qaptr/bench/results/release_validation_20260815T025849Z/helper_soak;
- **Opened app:** the three runs above are real production-app smoke measurements composed from `review_budget.sh`. They are not the required full 10-minute session. U20's prior smoke result was **29.118 MiB median** and **30.032 MiB peak**.
- **Real Vision preparation:** the temporary harness attempts to use the committed 24-capture manifest, real `MacOcr` and `MacVision`, masking, sanitization, coverage verification, and `PreparedPayload` proof assembly. The current run records a failure when masked-image recognition verification is not configured; no preparation latency pass is claimed. U12's **0.019 ms** figure is composition overhead only and is not used as pipeline latency.
- **Recall:** preserve the U9 disclosure of **5/6 = 0.833**. The known miss is the low-contrast text region in `low_contrast.png`; this is not a claim of perfect detection.
- **Privacy:** the passing payload proof test checks sanitized classes, masked-region coverage, and the carried recall report on the artifact. The workflow test checks that a privacy refusal performs zero provider invocations and zero consent requests.
- **Image provenance:** image-bound recognition carries the source image hash, masking rejects detections from different bytes, and the proof records the masked-image hash plus a recognizer rerun over the exact masked bytes. This proves provenance and absence of residual detections for the tested regions; it does not turn the published U9 recall of **5/6 = 0.833** into a perfect-recall claim.
- **History encoding:** the store remains image-free and the review FFI JSON boundary has a round-trip test for observations and notices. This is a tested serialization boundary, not proof of the unbuilt end-to-end review session.
- **Provider proof:** Codex **0.147.0**, Jcode **0.75.23**, and Claude Code **2.1.228** are genuine installed local CLIs. Codex is OAuth-only through its existing CLI login; Qaptr does not accept or read an OpenAI API key and only uses non-secret login metadata when the CLI auth probe is unavailable. Codex and Jcode pass sandboxed authenticated detection. Claude reaches its canonical executable, version probe, and auth probe, but its session is macOS-Keychain-backed and U14 intentionally does not grant Keychain access, so sandboxed authentication remains **UNVERIFIED** rather than being represented as a runtime failure. OpenRouter has no real endpoint/key proof in this run. All four release-gating provider implementations are present, but full four-provider proof is not achieved. OpenCode at `~/.opencode/bin/opencode` is outside the four-provider release scope and has no adapter.
- **Reference-machine gap:** this machine is an Apple M5 MacBook Air with 24 GB RAM and one built-in Retina display. The release protocol requires 16 GB and a real attached 5K display. U4 and U20 both flagged this gap; these results are informative for this machine and do not silently become reference-machine proof.

## Full review-session limitation

The requested scripted review flow is **not proven**. The current `QaptrReview.app` exposes capture-progress, settings/onboarding, and a read-only durable-history observation sheet, but it does not expose the required analyze-session, observation-detail, workflow-generation, or four-export controls, and no committed production-shaped UI driver exists. The validator records this as a failure instead of claiming that three idle smoke launches exercised the 10-minute flow.

## Fresh-install bootstrap limitation

The empty-store migration is covered by `migration_from_empty_produces_the_allowlisted_schema`, but U23 has no clean-machine install/bootstrap driver that installs the packaged app, grants first-run permissions, starts the helper login item, and reaches a usable review state. That release claim remains **UNVERIFIED**.

## Required follow-up

1. Land the production-shaped review driver and wire it to the 24-capture fixture so the 10-minute budget can be measured on three consecutive runs.
2. Add and run a clean-machine fresh-install/bootstrap driver.
3. Repeat helper and opened-app measurements on the 16 GB reference machine with a real 5K display.
4. Configure OpenRouter credentials and decide whether a future narrowly scoped macOS auth integration can verify Claude Keychain-backed sessions; do not widen the sandbox or read Claude credentials.
5. Run the packaging gate with provisioned Developer ID and notarytool credentials, then resolve the known clean-checkout UUID reproducibility failure.

## Reproducibility limitation

The clean-checkout reproducibility check is not passing. Two clean `git archive
HEAD` checkouts produce helper binaries with different Mach-O `LC_UUID` values;
the ad-hoc code seal and downstream bundle/DMG hashes therefore differ.
Same-tree rebuilds are deterministic, helper/link/entitlement audits pass, and
no absolute checkout path is embedded. This is a toolchain/reproducibility-policy
gap, not evidence of a privacy or signing failure; the bit-identical artifact
claim remains **UNVERIFIED** until the UUID policy is resolved.
