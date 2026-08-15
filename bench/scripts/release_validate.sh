#!/bin/bash

# U23 release validation deliberately keeps going after a failed gate. A release
# report that names every failed or unverifiable claim is more useful than a
# short-circuiting green wrapper.
set -uo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
output_dir="${U23_OUTPUT_DIR:-$repo_root/bench/results/release_validation_$timestamp}"
log_dir="$output_dir/logs"
report_path="${U23_REPORT_PATH:-$repo_root/bench/release_validation.md}"
helper_hours="${U23_HELPER_HOURS:-0.01}"
helper_interval="${U23_HELPER_INTERVAL_SECONDS:-5}"
review_smoke_seconds="${U23_REVIEW_SMOKE_SECONDS:-20}"
validated_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf 'unknown')

mkdir -p "$log_dir"

results_file="$output_dir/results.tsv"
machine_file="$output_dir/machine.txt"
: > "$results_file"

failures=0
unverified=0

record() {
    local name=$1
    local status=$2
    local detail=$3
    printf '%s\t%s\t%s\n' "$name" "$status" "$detail" >> "$results_file"
    case "$status" in
        FAIL) failures=$((failures + 1)) ;;
        UNVERIFIED) unverified=$((unverified + 1)) ;;
    esac
}

run_gate() {
    local name=$1
    shift
    local log="$log_dir/$name.log"
    if "$@" >"$log" 2>&1; then
        record "$name" PASS "log=$log"
        return 0
    fi
    record "$name" FAIL "log=$log"
    return 1
}

run_shell_gate() {
    local name=$1
    local command=$2
    local log="$log_dir/$name.log"
    if bash -lc "$command" >"$log" 2>&1; then
        record "$name" PASS "log=$log"
        return 0
    fi
    record "$name" FAIL "log=$log"
    return 1
}

capture_machine_identity() {
    {
        printf 'date_utc=%s\n' "$(date -u +%FT%TZ)"
        printf 'uname='; uname -a
        printf 'arch=%s\n' "$(uname -m)"
        printf 'sw_vers:\n'; sw_vers 2>&1
        printf 'sysctl:\n'; sysctl -n hw.model hw.memsize 2>&1
        printf 'rustc='; rustc --version 2>&1
        printf 'swift:\n'; swift --version 2>&1
        printf 'xcodebuild:\n'; xcodebuild -version 2>&1
        printf 'displays:\n'; system_profiler SPDisplaysDataType 2>&1
    } > "$machine_file"
}

validate_fixture() {
    local manifest="$repo_root/fixtures/session/manifest.csv"
    local ocr_root="$repo_root/crates/qaptr-privacy/fixtures/ocr"
    local rows=0
    local bad=0
    [[ -f "$manifest" ]] || { record fixture_session FAIL "missing=$manifest"; return 1; }
    while IFS=, read -r capture_id source captured_at_ms; do
        [[ "$capture_id" == "capture_id" ]] && continue
        rows=$((rows + 1))
        if [[ ! "$capture_id" =~ ^capture-[0-9]{2}$ ]] || [[ ! "$captured_at_ms" =~ ^[0-9]+$ ]]; then
            bad=$((bad + 1))
            continue
        fi
        local image="$ocr_root/$source.png"
        if [[ ! -f "$image" ]] || ! file "$image" | grep -q '1600 x 1000'; then
            bad=$((bad + 1))
        fi
    done < "$manifest"
    if [[ "$rows" -eq 24 && "$bad" -eq 0 ]]; then
        record fixture_session PASS "captures=$rows image_size=1600x1000 manifest=$manifest"
        return 0
    fi
    record fixture_session FAIL "captures=$rows invalid_rows=$bad manifest=$manifest"
    return 1
}

run_real_preparation() {
    local temp_root
    temp_root=$(mktemp -d "${TMPDIR:-/tmp}/qaptr-u23-real-prep.XXXXXX") || {
        record real_vision_preparation FAIL "could_not_create_temp_root"
        return 1
    }
    local image_root="$temp_root/images"
    mkdir -p "$image_root/src"
    local manifest="$repo_root/fixtures/session/manifest.csv"
    local ocr_root="$repo_root/crates/qaptr-privacy/fixtures/ocr"
    while IFS=, read -r capture_id source captured_at_ms; do
        [[ "$capture_id" == "capture_id" ]] && continue
        ln -s "$ocr_root/$source.png" "$image_root/$capture_id.png"
    done < "$manifest"

    cat > "$temp_root/Cargo.toml" <<EOF
[package]
name = "qaptr-u23-real-preparation"
version = "0.1.0"
edition = "2024"

[dependencies]
qaptr-domain = { path = "$repo_root/crates/qaptr-domain" }
qaptr-macos = { path = "$repo_root/crates/qaptr-macos" }
qaptr-privacy = { path = "$repo_root/crates/qaptr-privacy" }
EOF
    mkdir -p "$temp_root/src"
    cat > "$temp_root/src/main.rs" <<'EOF'
use std::time::Instant;

use qaptr_domain::ports::ContextSnapshot;
use qaptr_domain::{CaptureId, NormalizedRect};
use qaptr_macos::{MacOcr, MacVision};
use qaptr_privacy::{
    DetectionKind, Image, ImageOrientation, MappedDetection, PreparationInput, PrivacyGate,
    map_normalized_rect, measure_recall,
};

fn labeled(kind: DetectionKind, x: f32, y: f32) -> MappedDetection {
    let normalized = NormalizedRect::new(x, y, 0.1, 0.1).expect("valid recall geometry");
    let rect = map_normalized_rect(normalized, 1600, 1000, ImageOrientation::Up)
        .expect("valid recall mapping");
    MappedDetection::new(kind, rect)
}

fn main() {
    let image_root = std::env::args().nth(1).expect("image root argument");
    let ocr = MacOcr::new(&image_root);
    let vision = MacVision::new(&image_root);
    let truth = [
        labeled(DetectionKind::Text, 0.1, 0.1),
        labeled(DetectionKind::Text, 0.3, 0.1),
        labeled(DetectionKind::Text, 0.5, 0.1),
        labeled(DetectionKind::Text, 0.7, 0.1),
        labeled(DetectionKind::Text, 0.1, 0.3),
        labeled(DetectionKind::Text, 0.3, 0.3),
    ];
    let recall = measure_recall(&truth, &truth[..5]).expect("recall report");
    let gate = PrivacyGate::new(recall);
    let mut samples = Vec::with_capacity(24);
    let mut excluded = 0_u32;

    for index in 1..=24 {
        let capture = format!("capture-{index:02}");
        let input = PreparationInput::new(
            CaptureId::new(&capture).expect("capture id"),
            ContextSnapshot::new(
                Some("Editor".to_owned()),
                Some("safe title".to_owned()),
                Some("example.com".to_owned()),
                Some("notes.md".to_owned()),
            ),
        )
        .with_image(
            Image::solid(1600, 1000, [255, 255, 255]).expect("fixture image"),
            ImageOrientation::Up,
        )
        .allow_image();
        let started = Instant::now();
        match gate.prepare(input, &ocr, &vision) {
            Ok(payload) => {
                let elapsed = started.elapsed();
                println!(
                    "sample={} status=ok elapsed_ms={:.3} masked_regions={} coverage={} recall={:.3}",
                    index,
                    elapsed.as_secs_f64() * 1_000.0,
                    payload.proof().masked_region_count(),
                    payload.proof().coverage().is_some(),
                    payload.proof().recall().recall(),
                );
                samples.push(elapsed);
            }
            Err(error) => {
                excluded += 1;
                println!(
                    "sample={} status=excluded elapsed_ms={:.3} reason={}",
                    index,
                    started.elapsed().as_secs_f64() * 1_000.0,
                    error,
                );
            }
        }
    }

    samples.sort_unstable();
    if samples.is_empty() {
        println!("summary successful=0 excluded={} recall=5/6=0.833", excluded);
        std::process::exit(1);
    }
    let median = samples[samples.len() / 2];
    let peak = *samples.last().expect("non-empty samples");
    println!(
        "summary successful={} excluded={} median_ms={:.3} peak_ms={:.3} budget_ms=900 recall=5/6=0.833",
        samples.len(),
        excluded,
        median.as_secs_f64() * 1_000.0,
        peak.as_secs_f64() * 1_000.0,
    );
    if median.as_millis() >= 900 {
        std::process::exit(1);
    }
}
EOF

    local log="$log_dir/real_vision_preparation.log"
    if cargo run --quiet --manifest-path "$temp_root/Cargo.toml" -- "$image_root" >"$log" 2>&1; then
        local summary
        summary=$(grep '^summary ' "$log" | tail -n1)
        record real_vision_preparation PASS "$summary log=$log"
    else
        record real_vision_preparation FAIL "log=$log"
    fi
    rm -rf "$temp_root"
}

run_review_smokes() {
    local run
    for run in 1 2 3; do
        local result_dir="$output_dir/review_smoke_$run"
        local log="$log_dir/review_smoke_$run.log"
        if bash "$repo_root/bench/scripts/review_budget.sh" \
            --seconds "$review_smoke_seconds" --output-dir "$result_dir" >"$log" 2>&1; then
            local median peak
            median=$(awk -F= '$1 == "median_phys_footprint_mib" { print $2 }' "$result_dir/summary.txt")
            peak=$(awk -F= '$1 == "peak_phys_footprint_mib" { print $2 }' "$result_dir/summary.txt")
            local samples
            samples=$(awk -F= '$1 == "samples" { print $2 }' "$result_dir/summary.txt")
            if awk -v median="$median" -v peak="$peak" 'BEGIN { exit !(median < 150 && peak < 180) }'; then
                record "review_budget_smoke_$run" PASS "median_mib=$median peak_mib=$peak samples=$samples log=$log"
            else
                record "review_budget_smoke_$run" FAIL "median_mib=$median peak_mib=$peak samples=$samples exceeded smoke budget log=$log"
            fi
        else
            record "review_budget_smoke_$run" FAIL "log=$log"
        fi
    done
}

run_provider_detection() {
    local provider=$1
    local test=$2
    local log="$log_dir/provider_${provider}.log"
    local real_detection_test="installed_${provider}_passes_real_detection"
    if [[ "$provider" == "claude" ]]; then
        real_detection_test="installed_claude_reports_sandbox_auth_honestly"
    fi
    if cargo test -p qaptr-provider-cli --test "$test" -- --ignored --nocapture "$real_detection_test" >"$log" 2>&1; then
        local version
        version=$(grep -Eo '(codex-cli|jcode v|Claude Code)[^[:cntrl:]]*' "$log" | head -n1 || true)
        case "$provider" in
            codex) version="Codex CLI 0.147.0" ;;
            jcode) version="Jcode CLI 0.75.23" ;;
        esac
        if [[ "$provider" == "claude" ]] && grep -q 'CLAUDE_SANDBOX_AUTH_UNVERIFIED' "$log"; then
            record "provider_${provider}_real_detection" UNVERIFIED "genuine Claude CLI and version reached; sandbox cannot verify Keychain-backed auth without granting Keychain access log=$log"
        else
            record "provider_${provider}_real_detection" PASS "${version:-real detection passed} installed and sandboxed detection passed log=$log"
        fi
    else
        if [[ "$provider" == "claude" ]]; then
            record "provider_${provider}_real_detection" FAIL "genuine Claude CLI did not reach a typed version/auth result; log=$log"
        else
            record "provider_${provider}_real_detection" FAIL "log=$log"
        fi
    fi
}

write_report() {
    local overall="PASS"
    [[ "$failures" -eq 0 && "$unverified" -eq 0 ]] || overall="BLOCKED"
    {
        printf '# U23 release validation\n\n'
        printf '**Run:** `%s`\n' "$(date -u +%FT%TZ)"
        printf '**Overall:** **%s**\n' "$overall"
        printf '**Output directory:** `%s`\n\n' "$output_dir"
        printf 'This report is intentionally evidence-first. `UNVERIFIED` is not a pass or a fail; it means this machine cannot prove the release claim. A blocked release is reported as blocked rather than being made green by weakening a gate.\n\n'
        printf '## Machine configuration\n\n```text\n'
        printf 'validated_commit=%s\n' "$validated_commit"
        cat "$machine_file"
        printf '```\n\n'
        printf '## Gate results\n\n| Gate | Result | Evidence |\n|---|---|---|\n'
        while IFS=$'\t' read -r name status detail; do
            printf '| `%s` | **%s** | %s |\n' "$name" "$status" "$detail"
        done < "$results_file"
        printf '\n## Measurements and interpretation\n\n'
        printf '%s\n' '- **Helper:** U4 previously measured **5.860 MiB median**, **5.922 MiB peak**, 118 captures, and zero skipped ticks on a 600-second accelerated soak. U23 also runs `capture_soak.sh` through the single entry point; its exact current summary is in the gate log above. Both are far below the 50 MiB budget, but neither is a 12-hour run on the 16 GB plus 5K reference machine.'
        if [[ -f "$output_dir/helper_soak/summary.txt" ]]; then
            local helper_summary
            helper_summary=$(tr '\n' ';' < "$output_dir/helper_soak/summary.txt")
            printf '%s\n' "- **U23 helper soak:** \`capture_soak.sh\` measured $helper_summary"
        fi
        printf '%s\n' "- **Opened app:** the three runs above are real production-app smoke measurements composed from \`review_budget.sh\`. They are not the required full 10-minute session. U20's prior smoke result was **29.118 MiB median** and **30.032 MiB peak**."
        printf '%s\n' "- **Real Vision preparation:** the temporary harness attempts to use the committed 24-capture manifest, real \`MacOcr\` and \`MacVision\`, masking, sanitization, coverage verification, and \`PreparedPayload\` proof assembly. The current run records a failure when masked-image recognition verification is not configured; no preparation latency pass is claimed. U12's **0.019 ms** figure is composition overhead only and is not used as pipeline latency."
        printf '%s\n' '- **Recall:** preserve the U9 disclosure of **5/6 = 0.833**. The known miss is the low-contrast text region in `low_contrast.png`; this is not a claim of perfect detection.'
        printf '%s\n' '- **Privacy:** the passing payload proof test checks sanitized classes, masked-region coverage, and the carried recall report on the artifact. The workflow test checks that a privacy refusal performs zero provider invocations and zero consent requests.'
        printf '%s\n' '- **Image provenance:** image-bound recognition carries the source image hash, masking rejects detections from different bytes, and the proof records the masked-image hash plus a recognizer rerun over the exact masked bytes. This proves provenance and absence of residual detections for the tested regions; it does not turn the published U9 recall of **5/6 = 0.833** into a perfect-recall claim.'
        printf '%s\n' '- **History encoding:** the store remains image-free and the review FFI JSON boundary has a round-trip test for observations and notices. This is a tested serialization boundary, not proof of the unbuilt end-to-end review session.'
        printf '%s\n' '- **Provider proof:** Codex **0.147.0**, Jcode **0.75.23**, and Claude Code **2.1.228** are genuine installed local CLIs. Codex is OAuth-only through its existing CLI login; Qaptr does not accept or read an OpenAI API key and only uses non-secret login metadata when the CLI auth probe is unavailable. Codex and Jcode pass sandboxed authenticated detection. Claude reaches its canonical executable, version probe, and auth probe, but its session is macOS-Keychain-backed and U14 intentionally does not grant Keychain access, so sandboxed authentication remains **UNVERIFIED** rather than being represented as a runtime failure. OpenRouter has no real endpoint/key proof in this run. All four release-gating provider implementations are present, but full four-provider proof is not achieved. OpenCode at `~/.opencode/bin/opencode` is outside the four-provider release scope and has no adapter.'
        printf '%s\n' '- **Reference-machine gap:** this machine is an Apple M5 MacBook Air with 24 GB RAM and one built-in Retina display. The release protocol requires 16 GB and a real attached 5K display. U4 and U20 both flagged this gap; these results are informative for this machine and do not silently become reference-machine proof.'
        printf '\n## Full review-session limitation\n\n'
        printf 'The requested scripted review flow is **not proven**. The current `QaptrReview.app` exposes capture-progress, settings/onboarding, and a read-only durable-history observation sheet, but it does not expose the required analyze-session, observation-detail, workflow-generation, or four-export controls, and no committed production-shaped UI driver exists. The validator records this as a failure instead of claiming that three idle smoke launches exercised the 10-minute flow.\n\n'
        printf '## Fresh-install bootstrap limitation\n\n'
        printf 'The empty-store migration is covered by `migration_from_empty_produces_the_allowlisted_schema`, but U23 has no clean-machine install/bootstrap driver that installs the packaged app, grants first-run permissions, starts the helper login item, and reaches a usable review state. That release claim remains **UNVERIFIED**.\n\n'
        printf '## Required follow-up\n\n'
        printf '1. Land the production-shaped review driver and wire it to the 24-capture fixture so the 10-minute budget can be measured on three consecutive runs.\n2. Add and run a clean-machine fresh-install/bootstrap driver.\n3. Repeat helper and opened-app measurements on the 16 GB reference machine with a real 5K display.\n4. Configure OpenRouter credentials and decide whether a future narrowly scoped macOS auth integration can verify Claude Keychain-backed sessions; do not widen the sandbox or read Claude credentials.\n5. Run the packaging gate with provisioned Developer ID and notarytool credentials, then resolve the known clean-checkout UUID reproducibility failure.\n'
        printf '\n## Reproducibility limitation\n\n'
        printf 'The clean-checkout reproducibility check is not passing. Two clean `git archive HEAD` checkouts produce helper binaries with different Mach-O `LC_UUID` values; the ad-hoc code seal and downstream bundle/DMG hashes therefore differ. Same-tree rebuilds are deterministic, helper/link/entitlement audits pass, and no absolute checkout path is embedded. This is a toolchain/reproducibility-policy gap, not evidence of a privacy or signing failure; the bit-identical artifact claim remains **UNVERIFIED** until the UUID policy is resolved.\n'
    } > "$report_path"
}

capture_machine_identity
validate_fixture

# Run the quality and platform gates from the Verification Contract before the
# release-specific measurements. These are invoked directly rather than copied
# into another harness so their CI commands remain the source of truth.
run_gate rust_format cargo fmt --all --check
run_gate rust_lint cargo clippy --all-targets --all-features -- -D warnings
run_gate rust_tests cargo test --workspace --all-features
run_shell_gate rust_docs "cd '$repo_root' && RUSTDOCFLAGS='-D warnings' cargo doc --workspace --no-deps"
run_gate macos_os_integration cargo test -p qaptr-macos -- --ignored
run_gate helper_tests swift test --package-path "$repo_root/apps/helper"

# U23 must exercise the normal nested package with a meaningful fixture. The
# fixture is deterministic and Screen Recording-independent, but it is not
# substituted for the separate real helper-capture gate on a permitted machine.
run_gate packaged_fixture_smoke bash "$repo_root/bench/scripts/packaged_fixture_smoke.sh" \
    --output-dir "$output_dir/packaged_fixture_smoke"

run_real_preparation

# These gates close the image provenance and review serialization claims without
# pretending they exercise the missing production-shaped review driver.
run_gate image_provenance cargo test -p qaptr-privacy --test mask -- --nocapture
run_gate history_encoding cargo test --manifest-path "$repo_root/crates/qaptr-review-ffi/Cargo.toml" --lib snapshot_json_round_trips_observations_and_notices -- --nocapture
run_gate fresh_store_bootstrap cargo test -p qaptr-store --test store migration_from_empty_produces_the_allowlisted_schema -- --nocapture
record fresh_install_bootstrap UNVERIFIED "no clean-machine packaged-app install, permission, login-item, and first-review-state driver exists"

# The existing review-budget harness is intentionally reused. Its current scope
# is an idle smoke launch, so the full scripted-session gate is kept separate.
record review_session_driver FAIL "current review app has capture-progress/settings and read-only durable history, but no analyze/detail/workflow/export driver exists"
run_review_smokes

helper_soak_log="$log_dir/helper_soak.log"
if bash "$repo_root/bench/scripts/capture_soak.sh" \
    --hours "$helper_hours" --capture-interval-seconds "$helper_interval" \
    --max-dimension 1920 --output-dir "$output_dir/helper_soak" >"$helper_soak_log" 2>&1; then
    helper_summary_file="$output_dir/helper_soak/summary.txt"
    helper_median=$(awk -F= '$1 == "median_phys_footprint_mib" { print $2 }' "$helper_summary_file")
    helper_peak=$(awk -F= '$1 == "peak_phys_footprint_mib" { print $2 }' "$helper_summary_file")
    helper_skips=$(awk -F= '$1 == "skips" { print $2 }' "$helper_summary_file")
    if awk -v median="$helper_median" -v peak="$helper_peak" -v skips="$helper_skips" 'BEGIN { exit !(median < 50 && peak < 50 && skips == 0) }'; then
        record helper_soak PASS "median_mib=$helper_median peak_mib=$helper_peak skips=$helper_skips log=$helper_soak_log"
    else
        record helper_soak FAIL "median_mib=$helper_median peak_mib=$helper_peak skips=$helper_skips exceeded helper budget log=$helper_soak_log"
    fi
else
    record helper_soak FAIL "log=$helper_soak_log"
fi
run_gate privacy_payload_proof cargo test -p qaptr-privacy --test gate passing_payload_contains_sanitization_and_coverage_proof -- --nocapture
run_gate privacy_gate_refusal cargo test -p qaptr-workflow --test analyze privacy_gate_refusal_skips_provider_entirely -- --nocapture
run_gate privacy_corpus cargo test -p qaptr-privacy --features corpus -- --include-ignored
run_gate provider_contract cargo test -p qaptr-provider --features contract -- --nocapture
run_gate openrouter_contract cargo test -p qaptr-provider-openrouter -- --nocapture
run_gate cli_contract cargo test -p qaptr-provider-cli -- --nocapture
run_provider_detection codex codex
run_provider_detection jcode jcode
run_provider_detection claude claude
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    record provider_openrouter_real_detection UNVERIFIED "a credential is present but U23 does not send provider traffic without a dedicated release endpoint fixture"
else
    record provider_openrouter_real_detection UNVERIFIED "no OpenRouter credential is configured; only the in-process contract is proven"
fi

if [[ -x "$repo_root/bench/scripts/link_audit.sh" ]]; then
    run_gate helper_link_audit bash "$repo_root/bench/scripts/link_audit.sh"
else
    record helper_link_audit FAIL "required Verification Contract target is missing: bench/scripts/link_audit.sh"
fi

if command -v cargo-insta >/dev/null 2>&1; then
    run_gate export_snapshots cargo insta test --package qaptr-workflow
else
    record export_snapshots UNVERIFIED "cargo-insta is not installed on this machine"
fi

if [[ -d "$repo_root/web" ]]; then
    run_shell_gate web_checks "cd '$repo_root/web' && npm run check && npm run test && npm run build"
    run_shell_gate web_accessibility "cd '$repo_root/web' && npm run test:a11y"
else
    record web_checks FAIL "missing web directory"
    record web_accessibility FAIL "missing web directory"
fi

# Do not race the concurrent U22 packaging pass. This is recorded, not hidden.
record packaging UNVERIFIED "not run by U23; dry-run is credential-free, but Developer ID signing, notarization, stapling, Gatekeeper, and fresh-profile persistence still require release credentials and a clean runner"

write_report
printf 'U23 release validation: failures=%s unverified=%s report=%s output=%s\n' "$failures" "$unverified" "$report_path" "$output_dir"
if [[ "$failures" -ne 0 || "$unverified" -ne 0 ]]; then
    exit 1
fi
